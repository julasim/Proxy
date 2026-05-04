# KI-OS Edge-Proxy

Zentraler **Caddy** als Edge-Reverse-Proxy für ALLE App-Stacks am VPS.
Eine TLS-Stelle, eine Caddyfile, beliebig viele Apps darunter.

## Architektur

```
Internet
   │
   ▼
edge-caddy :80, :443      ←── nur DIESER Container hört auf 80/443
   │
   │  Routing per Host-Header
   │
   ├─→ mcp.ki.wiki         → ki-os-mcp:5002
   ├─→ bauos.sima.business → bauos-app:3000
   ├─→ andere.tld          → ...
   │
   ▼
Docker-Netzwerk `proxy` (external)
   │
   ├── ki-os-mcp        (vom KI_WIKI_Stack)
   ├── ki-os-dashboard  (vom KI_WIKI_Stack — optional)
   ├── bauos-app        (von BauOS-Stack)
   └── <weitere Apps>
```

## Deploy auf VPS

```bash
ssh root@VPS
cd /opt
git clone https://github.com/julasim/KI_WIKI_Proxy.git proxy
cd /opt/proxy
bash install.sh
# install.sh erstellt das `proxy`-Netzwerk + startet Caddy
```

## Eine neue App anbinden

### 1. App-Stack ins `proxy`-Netzwerk hängen

In `docker-compose.yml` der App:
```yaml
services:
  my-app:
    # ... bestehende config ...
    networks:
      - proxy        # ← NEU: Edge-Proxy kann mich erreichen
      - default      # ← App-internes Netz (DB etc.) bleibt

networks:
  proxy:
    external: true   # ← wird vom Edge-Proxy verwaltet
```

App restart:
```bash
docker compose up -d
```

### 2. Caddyfile-Block hinzufügen

`/opt/proxy/Caddyfile`:
```
my-domain.tld {
    import security_headers
    reverse_proxy my-app:5000      # ← container_name : container-port
    import access_log
}
```

### 3. DNS

A-Record für `my-domain.tld` → VPS-IP

### 4. Caddy reload (no downtime)

```bash
cd /opt/proxy
bash update.sh
# oder direkt:
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

Caddy holt automatisch ein Let's-Encrypt-Cert für die neue Domain (~30s).

## Aktuelle Domains

Siehe `Caddyfile`. Stand:
- `mcp.ki.wiki` → KI-OS MCP-Server (Phase 1+2 + Block-1-Hardening)
- `76-13-10-79.sslip.io` → Fallback (gleicher Backend)
- `bauos.sima.business` → BauOS (auskommentiert bis Container im proxy-Netzwerk)

## Caddyfile-Snippets (Reuseable)

- `import security_headers` — HSTS, X-Frame-Options, CSP, etc.
- `import access_log` — strukturierter Console-Log

Definitionen siehe `Caddyfile` Top-Bereich.

## Update / Reload

**Caddyfile geändert (ohne git push):**
```bash
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

**Mit git push:**
```bash
cd /opt/proxy && bash update.sh
```

**Caddy-Image-Update:**
```bash
cd /opt/proxy
docker compose pull
docker compose up -d
```

## Debugging

```bash
# Wer hört auf 80/443?
ss -tlnp | grep -E ':80 |:443 '
# Erwartet: docker-proxy für edge-caddy

# Caddy-Logs (live)
docker compose logs -f caddy

# Caddy-Config validieren
docker compose exec caddy caddy validate --config /etc/caddy/Caddyfile

# Welche Container sind im proxy-Netzwerk?
docker network inspect proxy --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}'
```

## Migration vom alten Setup

Wenn vorher Caddy im KI_WIKI_Stack lief:
```bash
# 1. Edge-Proxy installieren
cd /opt && git clone https://github.com/julasim/KI_WIKI_Proxy.git proxy
cd /opt/proxy && bash install.sh
# (das schlägt fehl beim ersten Start weil Port 443 noch von alter Caddy belegt ist)

# 2. Alten Caddy im ki-os-stack stoppen
cd /opt/ki-os
docker compose stop caddy
docker compose rm -f caddy

# 3. ki-os-Stack mit aktualisiertem docker-compose pullen (MCP joint proxy-Netzwerk)
git pull
docker compose up -d

# 4. Edge-Proxy starten
cd /opt/proxy
docker compose up -d
```
