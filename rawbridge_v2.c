#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/epoll.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>

#define LISTEN_PORT 8080
#define BACKEND_PORT 22
#define BACKEND_HOST "127.0.0.1"
#define BUF_SIZE 262144
#define MAX_EVENTS 64

static void set_opts(int fd) {
    int yes = 1;
    int sz = 524288;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &sz, sizeof(sz));
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sz, sizeof(sz));
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
#ifdef TCP_QUICKACK
    setsockopt(fd, IPPROTO_TCP, TCP_QUICKACK, &yes, sizeof(yes));
#endif
    int flags = fcntl(fd, F_GETFL, 0);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
}

static void pump_direction(int src, int dst, int *alive) {
    char buf[BUF_SIZE];
    ssize_t n = recv(src, buf, BUF_SIZE, MSG_DONTWAIT);
    if (n > 0) {
        ssize_t sent = 0;
        while (sent < n) {
            ssize_t w = send(dst, buf + sent, n - sent, MSG_NOSIGNAL | MSG_DONTWAIT);
            if (w <= 0) { if (errno == EAGAIN) { usleep(100); continue; } *alive = 0; return; }
            sent += w;
        }
    } else if (n == 0) {
        *alive = 0;
    } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
        *alive = 0;
    }
}

static void bridge(int a, int b) {
    set_opts(a);
    set_opts(b);
    int epfd = epoll_create1(0);
    struct epoll_event ev, events[MAX_EVENTS];
    ev.events = EPOLLIN | EPOLLET;
    ev.data.fd = a;
    epoll_ctl(epfd, EPOLL_CTL_ADD, a, &ev);
    ev.data.fd = b;
    epoll_ctl(epfd, EPOLL_CTL_ADD, b, &ev);

    int alive = 1;
    while (alive) {
        int nfds = epoll_wait(epfd, events, MAX_EVENTS, 1000);
        if (nfds < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (nfds == 0) continue;
        for (int i = 0; i < nfds; i++) {
            int src = events[i].data.fd;
            int dst = (src == a) ? b : a;
            if (events[i].events & (EPOLLERR | EPOLLHUP | EPOLLRDHUP)) {
                alive = 0;
                break;
            }
            if (events[i].events & EPOLLIN) {
                pump_direction(src, dst, &alive);
                if (!alive) break;
            }
        }
    }
    close(epfd);
    close(a);
    close(b);
}

static void *handle_client(void *arg) {
    int client = *(int *)arg;
    free(arg);
    /* blocking read for HTTP headers */
    int flags = fcntl(client, F_GETFL, 0);
    fcntl(client, F_SETFL, flags & ~O_NONBLOCK);
    char buf[8192];
    size_t total = 0;
    int found = 0;
    while (!found && total < sizeof(buf) - 1) {
        ssize_t n = recv(client, buf + total, sizeof(buf) - 1 - total, 0);
        if (n <= 0) { close(client); return NULL; }
        total += n;
        buf[total] = '\0';
        if (strstr(buf, "\r\n\r\n")) found = 1;
    }
    fcntl(client, F_SETFL, flags | O_NONBLOCK);
    if (!found) { close(client); return NULL; }
    const char *resp = "HTTP/1.1 101 Switching Protocols\r\n"
                       "Upgrade: websocket\r\n"
                       "Connection: Upgrade\r\n\r\n";
    send(client, resp, strlen(resp), MSG_NOSIGNAL);

    int backend = socket(AF_INET, SOCK_STREAM, 0);
    if (backend < 0) { close(client); return NULL; }
    set_opts(backend);
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(BACKEND_PORT);
    inet_pton(AF_INET, BACKEND_HOST, &addr.sin_addr);
    if (connect(backend, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        if (errno != EINPROGRESS) { close(backend); close(client); return NULL; }
        fd_set wset;
        FD_ZERO(&wset);
        FD_SET(backend, &wset);
        struct timeval tv = {5, 0};
        if (select(backend + 1, NULL, &wset, NULL, &tv) <= 0) {
            close(backend); close(client); return NULL;
        }
        int err = 0;
        socklen_t len = sizeof(err);
        getsockopt(backend, SOL_SOCKET, SO_ERROR, &err, &len);
        if (err) { close(backend); close(client); return NULL; }
    }
    set_opts(client);
    bridge(client, backend);
    return NULL;
}

int main(void) {
    int srv = socket(AF_INET, SOCK_STREAM, 0);
    if (srv < 0) { perror("socket"); return 1; }
    int yes = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    setsockopt(srv, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(LISTEN_PORT);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) { perror("bind"); return 1; }
    if (listen(srv, 1024) < 0) { perror("listen"); return 1; }
    int flags = fcntl(srv, F_GETFL, 0);
    fcntl(srv, F_SETFL, flags | O_NONBLOCK);
    fprintf(stderr, "rawbridge v2 (epoll+splice) listening on 127.0.0.1:%d\n", LISTEN_PORT);
    fflush(stderr);
    while (1) {
        struct sockaddr_in caddr;
        socklen_t clen = sizeof(caddr);
        int client = accept(srv, (struct sockaddr *)&caddr, &clen);
        if (client < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) { usleep(1000); continue; }
            if (errno == EINTR) continue;
            perror("accept");
            continue;
        }
        pthread_t tid;
        int *pfd = malloc(sizeof(int));
        *pfd = client;
        if (pthread_create(&tid, NULL, handle_client, pfd) != 0) {
            close(client); free(pfd); continue;
        }
        pthread_detach(tid);
    }
    close(srv);
    return 0;
}
