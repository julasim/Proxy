#!/usr/bin/env bash
# update.sh — Edge-Proxy Update
# Pullt neuesten Caddyfile + reloaded Caddy (kein Container-Restart nötig).

set -euo pipefail
cd "$(dirname "$0")"

echo "── Pull Proxy-Repo ──"
before=$(git rev-parse HEAD)
git pull
after=$(git rev-parse HEAD)

if [ "$before" = "$after" ]; then
    echo "= Unverändert. Reload (Caddyfile-Änderungen ohne Pull?) [y/N]"
    read -r ans
    [[ "${ans,,}" == "y" ]] || exit 0
fi

# Caddy hot-reload (kein restart, no downtime)
echo "── Caddy reload ──"
docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile

echo
docker compose ps
echo
echo "✓ Edge-Proxy aktualisiert (hot-reload)."
