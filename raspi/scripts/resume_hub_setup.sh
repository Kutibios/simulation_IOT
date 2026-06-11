#!/usr/bin/env bash
# InfluxDB zaten kuruluysa 3-5. adımlardan devam et.
set -euo pipefail
log() { echo "[$(date +%H:%M:%S)] $*" ; }
SUDO_PW="${SUDO_PW:-kutay123}"

log "=== Adım 3-5 devam (hub-api + Node-RED) ==="
cd ~/hub-api
python3 -m venv .venv 2>/dev/null || true
REQ="requirements-pi.txt"
[[ -f "${REQ}" ]] || REQ="requirements.txt"
./.venv/bin/pip install --upgrade pip
while IFS= read -r pkg; do
  [[ -z "${pkg}" || "${pkg}" =~ ^# ]] && continue
  log "pip → ${pkg}"
  ./.venv/bin/pip install --prefer-binary --no-cache-dir "${pkg}"
done < "${REQ}"

echo "${SUDO_PW}" | sudo -S cp iot-hub-api.service /etc/systemd/system/
echo "${SUDO_PW}" | sudo -S systemctl daemon-reload
echo "${SUDO_PW}" | sudo -S systemctl enable iot-hub-api
echo "${SUDO_PW}" | sudo -S systemctl restart iot-hub-api
sleep 2
curl -s http://127.0.0.1:5000/health || true

cd ~/.node-red
npm install --no-fund --no-audit node-red-contrib-influxdb
echo "${SUDO_PW}" | sudo -S systemctl restart nodered
log "=== Bitti ==="
