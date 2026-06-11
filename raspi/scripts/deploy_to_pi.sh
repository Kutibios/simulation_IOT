#!/usr/bin/env bash
# Mac (veya geliştirme makinesi): hub-api, Node-RED akışları ve fonksiyonları Pi'ye kopyalar.
set -euo pipefail

PI_HOST="${PI_HOST:-172.20.10.5}"
PI_USER="${PI_USER:-kutay}"
PI_SSH="${PI_USER}@${PI_HOST}"
PI_SSH_PASSWORD="${PI_SSH_PASSWORD:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RASPI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HUB_API_SRC="${RASPI_DIR}/hub-api"
NODE_RED_SRC="${RASPI_DIR}/node-red"
FLOWS_SRC="${FLOWS_SRC:-${NODE_RED_SRC}/flows_hub_complete.json}"
REMOTE_HUB_API="${REMOTE_HUB_API:-/home/${PI_USER}/hub-api}"
REMOTE_NODE_RED="${REMOTE_NODE_RED:-/home/${PI_USER}/.node-red}"

_ssh() {
  if [[ -n "${PI_SSH_PASSWORD}" ]] && command -v expect >/dev/null 2>&1; then
    expect <<EOF
set timeout 120
spawn ssh -o StrictHostKeyChecking=accept-new ${PI_SSH} $*
expect {
  -re "(password|Password):" { send "${PI_SSH_PASSWORD}\r"; exp_continue }
  eof
}
EOF
  else
    ssh -o StrictHostKeyChecking=accept-new "${PI_SSH}" "$@"
  fi
}

_scp() {
  if [[ -n "${PI_SSH_PASSWORD}" ]] && command -v expect >/dev/null 2>&1; then
    expect <<EOF
set timeout 300
spawn scp -o StrictHostKeyChecking=accept-new -r $*
expect {
  -re "(password|Password):" { send "${PI_SSH_PASSWORD}\r"; exp_continue }
  eof
}
EOF
  else
    scp -o StrictHostKeyChecking=accept-new -r "$@"
  fi
}

echo "==> Hedef: ${PI_SSH}"
echo "==> hub-api -> ${REMOTE_HUB_API}"
if [[ ! -d "${HUB_API_SRC}" ]]; then
  echo "HATA: ${HUB_API_SRC} bulunamadı" >&2
  exit 1
fi
_ssh "mkdir -p '${REMOTE_HUB_API}' '${REMOTE_NODE_RED}'"
_scp "${HUB_API_SRC}/." "${PI_SSH}:${REMOTE_HUB_API}/"

echo "==> Node-RED flows ve function dosyaları"
if [[ -f "${FLOWS_SRC}" ]]; then
  _scp "${FLOWS_SRC}" "${PI_SSH}:${REMOTE_NODE_RED}/flows.json"
else
  echo "UYARI: ${FLOWS_SRC} yok; flows.json kopyalanmadı"
  for fallback in "${NODE_RED_SRC}/flows_flow1_fixed.json" "${NODE_RED_SRC}/flows.json"; do
    if [[ -f "${fallback}" ]]; then
      echo "    Yedek kullanılıyor: ${fallback}"
      _scp "${fallback}" "${PI_SSH}:${REMOTE_NODE_RED}/flows.json"
      break
    fi
  done
fi

if compgen -G "${NODE_RED_SRC}/FUNCTION_*.js" >/dev/null; then
  _scp "${NODE_RED_SRC}"/FUNCTION_*.js "${PI_SSH}:${REMOTE_NODE_RED}/"
fi

echo "==> Uzak kurulum scriptleri (varsa)"
_scp "${SCRIPT_DIR}/install_hub_api.sh" "${SCRIPT_DIR}/install_nodered_influx.sh" \
  "${PI_SSH}:/home/${PI_USER}/" 2>/dev/null || true

echo "==> hub-api kurulum / yeniden başlatma"
REMOTE_SCRIPT="$(mktemp)"
trap 'rm -f "${REMOTE_SCRIPT}"' EXIT
cat > "${REMOTE_SCRIPT}" <<REMOTE
set -euo pipefail
if [[ -x "\${HOME}/install_hub_api.sh" ]]; then
  HUB_API_DIR="${REMOTE_HUB_API}" bash "\${HOME}/install_hub_api.sh"
else
  cd "${REMOTE_HUB_API}"
  python3 -m venv .venv 2>/dev/null || true
  ./.venv/bin/pip install -q -r requirements.txt
  sudo cp iot-hub-api.service /etc/systemd/system/iot-hub-api.service
  sudo systemctl daemon-reload
  sudo systemctl enable iot-hub-api.service
  sudo systemctl restart iot-hub-api.service
fi
if systemctl is-active --quiet nodered 2>/dev/null; then
  sudo systemctl restart nodered
elif systemctl is-active --quiet nodered.service 2>/dev/null; then
  sudo systemctl restart nodered.service
else
  echo "Node-RED servisi bulunamadı; elle yeniden başlatın"
fi
REMOTE
_scp "${REMOTE_SCRIPT}" "${PI_SSH}:/tmp/iot_hub_post_deploy.sh"
_ssh "bash /tmp/iot_hub_post_deploy.sh; rm -f /tmp/iot_hub_post_deploy.sh"

echo "==> Deploy tamam"
echo "    Health: http://${PI_HOST}:5000/health"
echo "    Node-RED: http://${PI_HOST}:1880"
