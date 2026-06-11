#!/usr/bin/env bash
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
MODEL="${GEMINI_MODEL:-gemini-2.5-flash}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 7: Gemini model → ${MODEL} ==="
ENV="${HOME}/.config/iot-hub/.env"
mkdir -p "${HOME}/.config/iot-hub"
touch "${ENV}"
if grep -q '^GEMINI_MODEL=' "${ENV}"; then
  sed -i.bak "s|^GEMINI_MODEL=.*|GEMINI_MODEL=${MODEL}|" "${ENV}"
else
  echo "GEMINI_MODEL=${MODEL}" >> "${ENV}"
fi
rm -f "${ENV}.bak"
chmod 600 "${ENV}"
echo "${PW}" | sudo -S systemctl restart iot-hub-api
sleep 2
curl -sf http://127.0.0.1:5000/health && log "  /health OK" || log "  UYARI: /health yok"
log "=== STEP 7 BİTTİ ==="
