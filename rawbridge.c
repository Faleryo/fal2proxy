#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>

#define LISTEN_PORT 8080
#define BACKEND_PORT 22
#define BACKEND_HOST "127.0.0.1"
#define BUF_SIZE 65536

static void set_opts(int fd) {
    int yes = 1;
    int sz = 262144;
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &yes, sizeof(yes));
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &sz, sizeof(sz));
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &sz, sizeof(sz));
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
#ifdef TCP_QUICKACK
    setsockopt(fd, IPPROTO_TCP, TCP_QUICKACK, &yes, sizeof(yes));
#endif
}

static void bridge(int a, int b) {
    char buf[BUF_SIZE];
    fd_set rfds;
    int maxfd = (a > b ? a : b) + 1;
    while (1) {
        FD_ZERO(&rfds);
        FD_SET(a, &rfds);
        FD_SET(b, &rfds);
        struct timeval tv = {60, 0};
        int r = select(maxfd, &rfds, NULL, NULL, &tv);
        if (r <= 0) break;
        if (FD_ISSET(a, &rfds)) {
            ssize_t n = recv(a, buf, BUF_SIZE, 0);
            if (n <= 0) break;
            ssize_t sent = 0;
            while (sent < n) {
                ssize_t w = send(b, buf + sent, n - sent, MSG_NOSIGNAL);
                if (w <= 0) { n = -1; break; }
                sent += w;
            }
            if (n < 0) break;
        }
        if (FD_ISSET(b, &rfds)) {
            ssize_t n = recv(b, buf, BUF_SIZE, 0);
            if (n <= 0) break;
            ssize_t sent = 0;
            while (sent < n) {
                ssize_t w = send(a, buf + sent, n - sent, MSG_NOSIGNAL);
                if (w <= 0) { n = -1; break; }
                sent += w;
            }
            if (n < 0) break;
        }
    }
    close(a);
    close(b);
}

static void *handle_client(void *arg) {
    int client = *(int *)arg;
    free(arg);
    set_opts(client);
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
        close(backend);
        close(client);
        return NULL;
    }
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

    if (bind(srv, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        perror("bind");
        return 1;
    }
    if (listen(srv, 512) < 0) {
        perror("listen");
        return 1;
    }

    fprintf(stderr, "rawbridge (C) listening on 127.0.0.1:%d\n", LISTEN_PORT);
    fflush(stderr);

    while (1) {
        struct sockaddr_in caddr;
        socklen_t clen = sizeof(caddr);
        int client = accept(srv, (struct sockaddr *)&caddr, &clen);
        if (client < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            continue;
        }
        pthread_t tid;
        int *pfd = malloc(sizeof(int));
        *pfd = client;
        if (pthread_create(&tid, NULL, handle_client, pfd) != 0) {
            close(client);
            free(pfd);
            continue;
        }
        pthread_detach(tid);
    }
    close(srv);
    return 0;
}
