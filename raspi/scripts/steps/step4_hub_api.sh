#!/usr/bin/env bash
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 4: HUB-API (.env + pip) ==="
CONFIG="${HOME}/.config/iot-hub"
ENV="${CONFIG}/.env"
mkdir -p "${CONFIG}"
[[ -f "${ENV}" ]] || cp "${HOME}/hub-api/.env.example" "${ENV}"
if [[ -f "${CONFIG}/influx-admin.token" ]]; then
  t="$(tr -d '[:space:]' < "${CONFIG}/influx-admin.token")"
  grep -q '^INFLUX_TOKEN=' "${ENV}" && \
    sed -i.bak "s|^INFLUX_TOKEN=.*|INFLUX_TOKEN=${t}|" "${ENV}" || \
    echo "INFLUX_TOKEN=${t}" >> "${ENV}"
  rm -f "${ENV}.bak"
fi
chmod 600 "${ENV}"
log "  .env hazır"

cd "${HOME}/hub-api"
python3 -m venv .venv 2>/dev/null || true
REQ="requirements-pi.txt"
[[ -f "${REQ}" ]] || REQ="requirements.txt"
./.venv/bin/pip install -q --upgrade pip

while IFS= read -r pkg; do
  [[ -z "${pkg}" || "${pkg}" =~ ^# ]] && continue
  log "  pip → ${pkg}"
  ./.venv/bin/pip install --prefer-binary --no-cache-dir "${pkg}"
done < "${REQ}"

echo "${PW}" | sudo -S cp iot-hub-api.service /etc/systemd/system/
echo "${PW}" | sudo -S systemctl daemon-reload
echo "${PW}" | sudo -S systemctl enable iot-hub-api
echo "${PW}" | sudo -S systemctl restart iot-hub-api
sleep 2
curl -sf http://127.0.0.1:5000/health && log "  /health OK" || log "  UYARI: /health yok"
log "=== STEP 4 BİTTİ ==="
