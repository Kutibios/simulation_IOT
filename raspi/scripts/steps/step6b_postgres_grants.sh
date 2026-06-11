#!/usr/bin/env bash
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 6b: PostgreSQL izinleri ==="
echo "${PW}" | sudo -S -u postgres psql -d iot_telemetry <<'SQL'
GRANT ALL PRIVILEGES ON TABLE telemetry TO iothub;
GRANT USAGE, SELECT ON SEQUENCE telemetry_id_seq TO iothub;
SQL
log "  GRANT tamam"
echo "${PW}" | sudo -S systemctl restart iot-mqtt-ingest iot-hub-api
sleep 2
curl -sf http://127.0.0.1:5000/health && log "  /health OK"
log "=== STEP 6b BİTTİ ==="
