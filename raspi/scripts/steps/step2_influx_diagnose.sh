#!/usr/bin/env bash
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 2: INFLUXDB TEŞHİS ==="
echo "${PW}" | sudo -S systemctl status influxdb --no-pager 2>&1 | tail -12 | sed 's/^/  /'
log "--- journal (son 10 satır) ---"
echo "${PW}" | sudo -S journalctl -u influxdb -n 10 --no-pager 2>&1 | sed 's/^/  /'
ARCH="$(uname -m)"
INFLUXD="$(command -v influxd 2>/dev/null || echo yok)"
log "  uname -m: ${ARCH}"
log "  influxd:  ${INFLUXD}"
if [[ -x /usr/bin/influxd ]]; then
  file /usr/bin/influxd | sed 's/^/  /'
fi
log "=== STEP 2 BİTTİ ==="
