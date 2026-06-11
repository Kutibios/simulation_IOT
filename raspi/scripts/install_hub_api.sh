#!/usr/bin/env bash
# Raspberry Pi: FastAPI hub-api venv, bağımlılıklar ve systemd.
set -euo pipefail

HUB_API_DIR="${HUB_API_DIR:-${HOME}/hub-api}"
VENV_DIR="${HUB_API_DIR}/.venv"
CONFIG_DIR="${IOT_CONFIG_DIR:-${HOME}/.config/iot-hub}"
ENV_FILE="${IOT_HUB_ENV_FILE:-${CONFIG_DIR}/.env}"
SERVICE_NAME="${IOT_HUB_SERVICE:-iot-hub-api.service}"
SERVICE_SRC="${HUB_API_DIR}/iot-hub-api.service"
SERVICE_DST="/etc/systemd/system/${SERVICE_NAME}"

echo "==> Dizin: ${HUB_API_DIR}"
mkdir -p "${HUB_API_DIR}"
mkdir -p "${CONFIG_DIR}"

if [[ ! -f "${HUB_API_DIR}/main.py" ]]; then
  echo "HATA: ${HUB_API_DIR}/main.py yok. Önce deploy_to_pi.sh ile kodu kopyalayın." >&2
  exit 1
fi

echo "==> Python venv (idempotent)"
if [[ ! -d "${VENV_DIR}" ]]; then
  python3 -m venv "${VENV_DIR}"
fi
"${VENV_DIR}/bin/pip" install --upgrade pip
"${VENV_DIR}/bin/pip" install -r "${HUB_API_DIR}/requirements.txt"

echo "==> Ortam dosyası: ${ENV_FILE}"
if [[ ! -f "${ENV_FILE}" ]] && [[ -f "${HUB_API_DIR}/.env.example" ]]; then
  cp "${HUB_API_DIR}/.env.example" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
  echo "    .env.example kopyalandı; GEMINI_API_KEY ve INFLUX_TOKEN kontrol edin"
fi

TOKEN_FILE="${INFLUX_TOKEN_FILE:-${CONFIG_DIR}/influx-admin.token}"
if [[ -f "${TOKEN_FILE}" ]] && [[ -f "${ENV_FILE}" ]]; then
  token="$(tr -d '[:space:]' < "${TOKEN_FILE}")"
  if grep -q '^INFLUX_TOKEN=' "${ENV_FILE}"; then
    sed -i.bak "s|^INFLUX_TOKEN=.*|INFLUX_TOKEN=${token}|" "${ENV_FILE}"
    rm -f "${ENV_FILE}.bak"
  else
    echo "INFLUX_TOKEN=${token}" >> "${ENV_FILE}"
  fi
fi

echo "==> systemd unit"
if [[ ! -f "${SERVICE_SRC}" ]]; then
  echo "HATA: ${SERVICE_SRC} bulunamadı" >&2
  exit 1
fi
sudo cp "${SERVICE_SRC}" "${SERVICE_DST}"
sudo systemctl daemon-reload
sudo systemctl enable "${SERVICE_NAME}"
sudo systemctl restart "${SERVICE_NAME}"

echo "==> Servis durumu"
sudo systemctl --no-pager --full status "${SERVICE_NAME}" || true
echo "    API: http://$(hostname -I | awk '{print $1}'):5000/health"
