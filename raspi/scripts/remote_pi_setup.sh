#!/usr/bin/env bash
# Pi kurulum — hata gösterir, adım adım ilerleme yazar.
set -euo pipefail

log() { echo "[$(date +%H:%M:%S)] $*" ; }

SUDO_PW="${SUDO_PW:-kutay123}"
sudo_cmd() {
  echo "${SUDO_PW}" | sudo -S "$@" 2>&1 | while IFS= read -r line; do echo "      | $line"; done
  return "${PIPESTATUS[1]}"
}

log "=========================================="
log "IoT Hub kurulumu BAŞLADI"
log "=========================================="

# Takılı kalmış pip süreçlerini durdur (kendimizi öldürme)
pkill -f "pip install.*hub-api" 2>/dev/null || true

log "[1/5] InfluxDB paketleri..."
if ! dpkg -s influxdb2 >/dev/null 2>&1; then
  log "      InfluxData repo ekleniyor..."
  rm -f /tmp/influx.key /tmp/influx.gpg
  curl -fsSL https://repos.influxdata.com/influxdata-archive.key -o /tmp/influx.key
  gpg --batch --yes --dearmor -o /tmp/influx.gpg /tmp/influx.key
  echo "${SUDO_PW}" | sudo -S cp /tmp/influx.gpg /usr/share/keyrings/influxdb-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/influxdb-archive-keyring.gpg] https://repos.influxdata.com/debian stable main" \
    | sudo -S tee /etc/apt/sources.list.d/influxdb.list >/dev/null
  log "      apt update..."
  echo "${SUDO_PW}" | sudo -S apt-get update
  log "      apt install influxdb2 influxdb2-cli (2-5 dk)..."
  echo "${SUDO_PW}" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y influxdb2 influxdb2-cli
else
  log "      influxdb2 zaten yüklü"
  if ! dpkg -s influxdb2-cli >/dev/null 2>&1; then
    log "      influxdb2-cli eksik — kuruluyor..."
    echo "${SUDO_PW}" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y influxdb2-cli
  fi
fi

if ! command -v influx >/dev/null; then
  log "HATA: influx CLI hâlâ yok. Paket kurulumu başarısız." >&2
  exit 1
fi
log "      influx CLI: $(command -v influx)"

log "[2/5] InfluxDB servisi + setup..."
echo "${SUDO_PW}" | sudo -S systemctl enable influxdb || true
if ! echo "${SUDO_PW}" | sudo -S systemctl start influxdb; then
  log "      UYARI: influxdb servisi başlamadı — log:"
  echo "${SUDO_PW}" | sudo -S journalctl -u influxdb -n 8 --no-pager 2>&1 | sed 's/^/      | /'
  log "      Devam ediliyor (hub-api fallback modunda çalışabilir)"
fi
INFLUX_OK=false
for i in $(seq 1 30); do
  if influx ping >/dev/null 2>&1; then
    log "      InfluxDB ping OK"
    INFLUX_OK=true
    break
  fi
  log "      Influx bekleniyor... ($i/30)"
  sleep 2
done
if [[ "${INFLUX_OK}" != true ]]; then
  log "      UYARI: InfluxDB ping yok — Pi'de elle: sudo journalctl -u influxdb -n 30"
fi

CONFIG_DIR="${HOME}/.config/iot-hub"
TOKEN_FILE="${CONFIG_DIR}/influx-admin.token"
ENV_FILE="${CONFIG_DIR}/.env"
mkdir -p "${CONFIG_DIR}"

if [[ ! -f "${TOKEN_FILE}" ]] && [[ "${INFLUX_OK}" == true ]]; then
  if influx org list 2>/dev/null | grep -q iot-hub; then
    log "      Org zaten var; token configs'ten alınacak"
    token="$(grep -E '^\s*token\s*=' "${HOME}/.influxdbv2/configs" 2>/dev/null | head -1 | sed 's/.*=\s*//' | tr -d '"')"
  else
    log "      influx setup çalıştırılıyor..."
    TOKEN="$(date +%s)-$(id -u)-iot-hub"
    influx setup \
      --username admin \
      --password iot-hub-admin \
      --org iot-hub \
      --bucket iot_telemetry \
      --retention 0 \
      --token "${TOKEN}" \
      --force
    token="${TOKEN}"
  fi
  if [[ -z "${token:-}" ]]; then
    log "HATA: Influx token alınamadı" >&2
    exit 1
  fi
  echo "${token}" > "${TOKEN_FILE}"
  chmod 600 "${TOKEN_FILE}"
  log "      Token kaydedildi: ${TOKEN_FILE}"
fi

if [[ -f "${HOME}/hub-api/.env.example" ]] && [[ ! -f "${ENV_FILE}" ]]; then
  cp "${HOME}/hub-api/.env.example" "${ENV_FILE}"
  chmod 600 "${ENV_FILE}"
fi
if [[ -f "${TOKEN_FILE}" ]] && [[ -f "${ENV_FILE}" ]]; then
  token="$(tr -d '[:space:]' < "${TOKEN_FILE}")"
  if grep -q '^INFLUX_TOKEN=' "${ENV_FILE}"; then
    sed -i.bak "s|^INFLUX_TOKEN=.*|INFLUX_TOKEN=${token}|" "${ENV_FILE}"
  else
    echo "INFLUX_TOKEN=${token}" >> "${ENV_FILE}"
  fi
  rm -f "${ENV_FILE}.bak"
fi
log "[2/5] InfluxDB tamam"

log "[3/5] hub-api pip (Pi için hafif paketler, tek tek)..."
cd "${HOME}/hub-api"
python3 -m venv .venv 2>/dev/null || true
REQ="requirements-pi.txt"
[[ -f "${REQ}" ]] || REQ="requirements.txt"
./.venv/bin/pip install --upgrade pip
while IFS= read -r pkg; do
  [[ -z "${pkg}" || "${pkg}" =~ ^# ]] && continue
  log "      pip → ${pkg}"
  ./.venv/bin/pip install --prefer-binary --no-cache-dir "${pkg}"
done < "${REQ}"
log "      pip tamam"

echo "${SUDO_PW}" | sudo -S cp iot-hub-api.service /etc/systemd/system/iot-hub-api.service
echo "${SUDO_PW}" | sudo -S systemctl daemon-reload
echo "${SUDO_PW}" | sudo -S systemctl enable iot-hub-api.service
echo "${SUDO_PW}" | sudo -S systemctl restart iot-hub-api.service
sleep 3
if curl -sf http://127.0.0.1:5000/health >/dev/null; then
  log "      hub-api OK: $(curl -s http://127.0.0.1:5000/health | head -c 120)"
else
  log "      UYARI: hub-api yanıt vermiyor — sudo journalctl -u iot-hub-api -n 20"
fi
log "[3/5] hub-api tamam"

log "[4/5] Node-RED influx node..."
cd "${HOME}/.node-red"
log "      npm install (1-3 dk)..."
npm install --no-fund --no-audit node-red-contrib-influxdb
echo "${SUDO_PW}" | sudo -S systemctl restart nodered
sleep 4
log "[4/5] Node-RED tamam"

log "[5/5] Son durum..."
echo "      influxdb:    $(echo ${SUDO_PW} | sudo -S systemctl is-active influxdb 2>/dev/null)"
echo "      iot-hub-api: $(echo ${SUDO_PW} | sudo -S systemctl is-active iot-hub-api 2>/dev/null)"
echo "      nodered:     $(echo ${SUDO_PW} | sudo -S systemctl is-active nodered 2>/dev/null)"
curl -s http://127.0.0.1:5000/health 2>/dev/null || true
echo ""

log "=========================================="
log "KURULUM BİTTİ"
log "  Dashboard: http://$(hostname -I | awk '{print $1}'):1880/ui"
log "  API:       http://$(hostname -I | awk '{print $1}'):5000/health"
log "=========================================="
