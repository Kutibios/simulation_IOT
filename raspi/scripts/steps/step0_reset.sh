#!/usr/bin/env bash
# Pi: takılı süreçleri durdur, servisleri sıfırla (veri silmez).
set -uo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 0: RESET ==="
pkill -f "pip install.*hub-api" 2>/dev/null || true
echo "${PW}" | sudo -S systemctl stop iot-hub-api 2>/dev/null || true
log "Servisler durduruldu (iot-hub-api)"
log "InfluxDB durumu:"
echo "${PW}" | sudo -S systemctl is-active influxdb 2>/dev/null || echo "  influxdb: inactive/unknown"
log "Node-RED:"
echo "${PW}" | sudo -S systemctl is-active nodered 2>/dev/null || echo "  nodered: unknown"
log "=== STEP 0 BİTTİ ==="
