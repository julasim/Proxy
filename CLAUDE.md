# Proxy — Edge-Caddy für die ganze VPS

Single-TLS-Entry für ALLE App-Stacks auf VPS `srv1568905` (76.13.10.79). Caddy 2 als Container `edge-caddy`, belegt allein die VPS-Ports 80+443, terminiert TLS via Let's-Encrypt, routet per Hostname zu Container-Backends in einem gemeinsamen externen Docker-Netz.

## Schlüssel-Dateien

| Datei | Was |
|---|---|
| `Caddyfile` | Domain-Routing-Config — ein Block pro Public-Domain |
| `docker-compose.yml` | Caddy-Container, mapped 80→5080 + 443→5443, mountet Caddyfile + persistente Cert-Volumes |
| `install.sh` | Erst-Setup: legt externes `proxy`-Netzwerk an + bringt Caddy hoch |
| `update.sh` | Pull + restart |

## Architektur

```
                ┌── edge-caddy (80/443) ──────────┐
   Internet ───▶│  TLS-Termination + Routing      │
                │  Caddyfile in /opt/Proxy/       │
                └────────────┬─────────────────────┘
                             │ Docker-Network `proxy` (extern)
        ┌──────────┬─────────┼──────────┬──────────┐
        ▼          ▼         ▼          ▼          ▼
   ki-os-mcp  ki-os-dash  bauos-app  rag-api  (weitere...)
      :5002     :5000      :3000   :8000+:8501
```

**Aktuelle Domains (Stand 2026-05-11):**
| Domain | Backend | Stack | Security-Profile |
|---|---|---|---|
| `wiki-mcp.sima.business` | `ki-os-mcp:5002` | KI_WIKI | `api_security_headers` (strikt) |
| `76-13-10-79.sslip.io` | `ki-os-mcp:5002` | KI_WIKI | dito (Fallback ohne Domain) |
| `wiki-dashboard.sima.business` | `ki-os-dashboard:5000` | KI_WIKI | `html_security_headers` |
| `bauos.sima.business` | `bauos-app:3000` | Bau-OS | `html_security_headers` |
| `rag-os.sima.business` | `rag-api:8000` (`/api/*`,`/mcp/*`) + `rag-api:8501` (Streamlit) | RAG_OS | `html_security_headers` + WebSocket-Upgrade |

**Snippets (DRY in Caddyfile):**
- `api_security_headers` — strenge CSP, für JSON-APIs (MCP)
- `html_security_headers` — lockere CSP, für Web-UIs (Dashboard, Bau-OS, RAG-Streamlit)
- `access_log` — strukturiertes JSON-Log nach stdout

## Goldene Regeln (Verstoß bricht die ganze VPS-Topologie)

1. **Nur EIN Stack auf der VPS darf 80/443 belegen** — das ist `/opt/Proxy/`. Niemals anderen Caddy/Nginx/Traefik mit `ports: "80:80"` deployen.
2. **App-Container müssen ans externe `proxy`-Netz** — in ihrem `docker-compose.yml`:
   ```yaml
   services:
     myapp:
       networks: [proxy, default]
   networks:
     proxy:
       external: true
   ```
3. **Container-Name = Caddy-Routing-Target** — Container-Name nicht ändern ohne Caddyfile-Block mitanzupassen.
4. **Edge-Proxy zuerst starten** beim Erst-Setup — andere Stacks brauchen das `proxy`-Netz, das edge-caddy anlegt.
5. **Standalone-Caddy in App-Repos ist okay**, aber nur über Opt-In-Override-Compose-File (Pattern: `docker-compose.standalone.yml` in `julasim/RAG_OS`). Default-Compose joint immer `proxy`.

## Neue Domain hinzufügen — Workflow

1. App-Container ans `proxy`-Netz hängen (siehe Regel 2)
2. `Caddyfile`-Block ergänzen — vorhandene Blöcke als Template nutzen
3. Lokal committen + pushen
4. VPS: `cd /opt/Proxy && git pull && docker compose up -d` (Caddy lädt Caddyfile automatisch beim Restart, oder manuell mit `docker exec edge-caddy caddy reload --config /etc/caddy/Caddyfile`)
5. DNS A-Record für neue Subdomain auf 76.13.10.79

## Häufige Fallen

- **Port 80/443 belegt von Fremdcontainer** → `docker ps --format '{{.Names}}: {{.Ports}}' | grep -E ':80->|:443->'` zeigt den Übeltäter. Fix: `docker stop <name> && docker rm <name>` + edge-caddy `up -d`.
- **`proxy`-Netzwerk fehlt** → `docker network create proxy` oder `bash install.sh`.
- **502 Bad Gateway** → Backend-Container nicht erreichbar. Diagnose: `docker exec edge-caddy wget -qO- http://<container>:<port>/health`. Möglich: Container nicht im `proxy`-Netz, Container down, oder Container-Name in Caddyfile falsch.
- **Cert-Issuance hängt** → DNS-Propagation (`dig <domain> +short`), Port 80 erreichbar (für ACME HTTP-01), Caddy-Logs (`docker compose logs caddy | grep -i cert`).
- **421 Misdirected Request** → Backend hat DNS-Rebinding-Whitelist die den Hostname nicht erlaubt (typisch FastMCP). Im Backend `allowed_hosts` ergänzen.

## Container

- Image `caddy:2-alpine`
- Lauscht intern auf 5080/5443 (Projekt-Konvention 5xxx), Docker mapped extern auf 80/443 (TCP + UDP für HTTP/3)
- Persistente Volumes: `caddy-data` (Cert-Storage), `caddy-config` (Auto-Config)
- Netzwerk: nur `proxy` (sieht alle App-Container darüber)
- Restart: `unless-stopped`

## Verbindungen zu anderen Repos

- KI_WIKI-MCP/Dashboard: `julasim/KI_WIKI_Stack` deployed Bot+Dashboard+MCP, alle joinen `proxy`
- Bau-OS: `julasim/Bau-OS` (Container `bauos-app`)
- RAG_OS: `julasim/RAG_OS` — Edge-Mode default, Standalone via `docker-compose.standalone.yml`

## Geschichte / Lessons Learned

- 2026-05-11: RAG_OS-Deployment brachte versehentlich eigenen `rag-caddy` mit, hat 80/443 weggeschnappt. KI_WIKI-MCP/Dashboard+Bau-OS extern nicht erreichbar. Fix: RAG_OS-Repo refactored (split in Edge-Mode-Default + Standalone-Override), `rag-caddy` removed, edge-caddy wieder up.
- Lesson: NEUE App-Repos die per Default einen eigenen Caddy mitbringen können — entweder rebuilden auf Edge-Mode oder mit `docker-compose.override.yml` auf der VPS Caddy-Service rausoperieren bevor `up -d`.
