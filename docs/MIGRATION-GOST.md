# Migration Guide: DarkTunnel → gost (v3)

## Overview
v2 uses DarkTunnel (Android app) + rawbridge (C bridge) + OpenSSH.  
v3 replaces everything with **gost** (Go Simple Tunnel) — a single binary that handles tunneling, encryption, and proxying.

## Why migrate?
- **Fewer layers**: gost does tunneling + encryption in one binary (no SSH + bridge + nginx)
- **Better performance**: Go is optimized for network I/O (goroutines, epoll)
- **WebSocket framing**: gost client and server speak the same protocol (compatible with Cloudflare)
- **ws:// + wss://**: both modes run in parallel (port 80 and 443)

## Architecture

### v2 (current)
```
DarkTunnel (Android) → Cloudflare → nginx → rawbridge (C) → OpenSSH → Internet
```

### v3 (gost)
```
gost client (Android/PC) → Cloudflare → gost server (VPS) → Internet
```

## Migration steps

### 1. Install gost server on VPS
```bash
# On VPS
bash deploy/gost-server.sh install
```
This installs gost, configures ws:// (port 8080) + wss:// (port 8443), and starts both services.

### 2. Install gost client on your device
```bash
# On Android (Termux) or PC
bash deploy/gost-client.sh install
```

### 3. Start the tunnel
```bash
# Zero-rating mode (ws:// via Cloudflare port 80)
bash deploy/gost-client.sh ws

# TLS mode (wss:// via Cloudflare port 443)
bash deploy/gost-client.sh wss
```

### 4. Configure your apps
Set SOCKS5 proxy to `127.0.0.1:1080` in your browser/apps.

### 5. Switch from v2 to v3
- v2 (DarkTunnel + rawbridge) remains active on the VPS
- v3 (gost) runs in parallel on different ports
- Test v3, then disable v2 when satisfied

## Comparison

| Feature | v2 (DarkTunnel) | v3 (gost) |
|---------|-----------------|-----------|
| Client | DarkTunnel (Android only) | gost (Android, PC, Mac, Linux) |
| Server | OpenSSH + rawbridge + nginx | gost serveur |
| Tunnel protocol | Raw TCP via HTTP upgrade | WebSocket (ws:// or wss://) |
| Encryption | SSH (OpenSSH) | gost (TLS/AES) |
| Zero-rating | Yes (Cloudflare) | Yes (Cloudflare) |
| Performance | ~6.3 Mbps up / ~1.7 Mbps down | ~6.1 Mbps up / ~3.5 Mbps down |
| Complexity | 4 layers | 2 layers |

## Throughput results (measured 2026-10-17)

| Mode | Upload | Download |
|------|--------|----------|
| v2 (DarkTunnel + rawbridge, via Cloudflare) | ~6.3 Mbps | ~1.7 Mbps |
| v3 (gost, via Cloudflare) | ~6.1 Mbps | ~3.5 Mbps |
| v3 (gost, direct, no Cloudflare) | ~4.3 Mbps | ~4.3 Mbps |

**Conclusion** : gost améliore significativement le débit en download (x2) via Cloudflare. Le débit en upload est comparable. Le goulot reste Cloudflare.

## Rollback
If v3 doesn't work, v2 is still running. Just stop gost and use DarkTunnel as before:
```bash
bash deploy/gost-client.sh stop
```

## Notes
- v3 is developed but NOT deployed by default
- To deploy: run `bash deploy/gost-server.sh install` on the VPS
- The gost client creates a SOCKS5 proxy on port 1080
- Both ws:// (port 80) and wss:// (port 443) can run simultaneously
EOF
echo "created"