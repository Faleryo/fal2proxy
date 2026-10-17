import socket, select, threading

LISTEN = ("127.0.0.1", 8080)
BACKEND = ("127.0.0.1", 22)
BUF = 65536

def set_opts(s):
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 262144)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 262144)
    try:
        s.setsockopt(socket.IPPROTO_TCP, socket.TCP_QUICKACK, 1)
    except (AttributeError, OSError):
        pass

def handle(client):
    set_opts(client)
    buf = b""
    while b"\r\n\r\n" not in buf:
        r, _, _ = select.select([client], [], [], 30)
        if not r:
            client.close()
            return
        c = client.recv(4096)
        if not c:
            client.close()
            return
        buf += c
    client.sendall(b"HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n")
    try:
        backend = socket.create_connection(BACKEND, timeout=10)
    except Exception:
        client.close()
        return
    set_opts(backend)
    # bidirectional forwarding with select
    sockets = [client, backend]
    try:
        while True:
            r, _, _ = select.select(sockets, [], [], 60)
            if not r:
                break
            for src in r:
                dst = backend if src is client else client
                try:
                    data = src.recv(BUF)
                except Exception:
                    data = b""
                if not data:
                    raise Exception("closed")
                # send all
                view = memoryview(data)
                while view:
                    n = dst.send(view)
                    view = view[n:]
    except Exception:
        pass
    finally:
        try: client.close()
        except: pass
        try: backend.close()
        except: pass

srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
srv.bind(LISTEN)
srv.listen(512)
while True:
    c, _ = srv.accept()
    set_opts(c)
    threading.Thread(target=handle, args=(c,), daemon=True).start()
