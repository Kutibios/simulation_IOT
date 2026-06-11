#!/usr/bin/env bash
# node-red-dashboard eksikse /ui beyaz ekran + loading.html 404 verir.
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
DASH_VER="${DASHBOARD_VERSION:-3.6.6}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 8: node-red-dashboard ==="
cd "${HOME}/.node-red"

if [[ -d node_modules/node-red-dashboard ]]; then
  log "  mevcut: $(node -p "require('node-red-dashboard/package.json').version" 2>/dev/null || echo bilinmiyor)"
else
  log "  node-red-dashboard YOK — kuruluyor..."
fi

log "  npm install node-red-dashboard@${DASH_VER} (1-2 dk)..."
npm install --no-fund --no-audit "node-red-dashboard@${DASH_VER}"

if [[ ! -f node_modules/node-red-dashboard/ui/ui.html ]]; then
  log "  HATA: dashboard ui dosyaları eksik"
  exit 1
fi
log "  ui.html OK"

echo "${PW}" | sudo -S systemctl restart nodered
sleep 5
curl -sf -o /dev/null http://127.0.0.1:1880/ui/ && log "  /ui OK" || log "  UYARI: /ui yanıt vermiyor"
curl -sf -o /dev/null http://127.0.0.1:1880/ui/loading.html && log "  loading.html OK" || log "  UYARI: loading.html 404 (cache temizle, yeniden dene)"
log "=== STEP 8 BİTTİ ==="
