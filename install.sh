#!/usr/bin/env bash
# install.sh — Edge-Proxy Erst-Installation
#
# Verwendung:
#   cd /opt
#   git clone https://github.com/julasim/KI_WIKI_Proxy.git proxy
#   cd /opt/proxy
#   bash install.sh

set -euo pipefail
cd "$(dirname "$0")"

echo "═══════════════════════════════════════════════"
echo "   KI-OS Edge-Proxy — Erst-Installation"
echo "═══════════════════════════════════════════════"
echo

# 1. Docker-Check
command -v docker >/dev/null 2>&1 || { echo "❌ Docker fehlt"; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "❌ docker compose plugin fehlt"; exit 1; }

# 2. Externes Docker-Netzwerk anlegen falls noch nicht da
if docker network inspect proxy >/dev/null 2>&1; then
    echo "✓ Netzwerk 'proxy' existiert bereits"
else
    echo "── Erstelle externes Docker-Netzwerk 'proxy' ──"
    docker network create proxy
fi

# 3. Ports 80/443 freigeben
if command -v ufw >/dev/null 2>&1; then
    ufw allow 80/tcp 2>/dev/null || true
    ufw allow 443/tcp 2>/dev/null || true
    echo "✓ UFW: 80/tcp + 443/tcp erlaubt"
fi

# 4. Caddy starten
echo "──── Caddy bauen + starten ────"
docker compose up -d

echo
echo "──── Status ────"
docker compose ps

echo
echo "✓ Edge-Proxy läuft."
echo
echo "Nächste Schritte:"
echo "  1. App-Stacks (ki-os, bauos, ...) so ändern dass die Container"
echo "     im 'proxy'-Netzwerk sind:"
echo
echo "       services:"
echo "         my-app:"
echo "           networks: [proxy, default]"
echo "       networks:"
echo "         proxy: { external: true }"
echo
echo "  2. Im /opt/proxy/Caddyfile einen Block pro Domain hinzufügen:"
echo
echo "       my-domain.tld {"
echo "         reverse_proxy my-app:<port>"
echo "       }"
echo
echo "  3. Caddy reload:"
echo "       docker compose -f /opt/proxy/docker-compose.yml restart caddy"
