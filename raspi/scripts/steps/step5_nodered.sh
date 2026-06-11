#!/usr/bin/env bash
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 5: NODE-RED ==="
cd "${HOME}/.node-red"
log "  npm install node-red-dashboard + contrib..."
npm install --no-fund --no-audit node-red-dashboard@3.6.6 node-red-contrib-influxdb
echo "${PW}" | sudo -S systemctl restart nodered
sleep 3
curl -sf -o /dev/null http://127.0.0.1:1880/ && log "  Node-RED OK" || log "  UYARI: 1880 yok"
log "=== STEP 5 BİTTİ ==="
