#!/usr/bin/env bash
# Raspberry Pi: InfluxDB 2 kurulumu ve iot-hub org/bucket yapılandırması.
set -euo pipefail

INFLUX_ORG="${INFLUX_ORG:-iot-hub}"
INFLUX_BUCKET="${INFLUX_BUCKET:-iot_telemetry}"
INFLUX_USER="${INFLUX_USER:-admin}"
INFLUX_ADMIN_PASSWORD="${INFLUX_ADMIN_PASSWORD:-iot-hub-admin}"
INFLUX_RETENTION="${INFLUX_RETENTION:-0}"
CONFIG_DIR="${IOT_CONFIG_DIR:-${HOME}/.config/iot-hub}"
TOKEN_FILE="${INFLUX_TOKEN_FILE:-${CONFIG_DIR}/influx-admin.token}"
ENV_FILE="${IOT_HUB_ENV_FILE:-${CONFIG_DIR}/.env}"

echo "==> InfluxDB 2 paketleri (idempotent)"
if ! dpkg -s influxdb2 >/dev/null 2>&1; then
  sudo apt-get update -qq
  sudo apt-get install -y influxdb2
else
  echo "    influxdb2 zaten yüklü"
fi

echo "==> InfluxDB servisi"
sudo systemctl enable influxdb
sudo systemctl start influxdb

echo "==> Influx hazır olana kadar bekleniyor"
for i in $(seq 1 30); do
  if influx ping >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if ! influx ping >/dev/null 2>&1; then
  echo "HATA: influx ping başarısız" >&2
  exit 1
fi

mkdir -p "${CONFIG_DIR}"

setup_needed=true
if [[ -f "${TOKEN_FILE}" ]] && influx org list --token "$(tr -d '[:space:]' < "${TOKEN_FILE}")" --org "${INFLUX_ORG}" >/dev/null 2>&1; then
  setup_needed=false
  echo "==> InfluxDB zaten yapılandırılmış (${INFLUX_ORG})"
fi

if [[ "${setup_needed}" == true ]]; then
  if influx org list 2>/dev/null | grep -q "${INFLUX_ORG}"; then
    echo "==> Org mevcut; token dosyası yoksa ~/.influxdbv2/configs'ten alın"
    if [[ -f "${HOME}/.influxdbv2/configs" ]]; then
      token=$(grep -E '^\s*token\s*=' "${HOME}/.influxdbv2/configs" | head -1 | sed 's/.*=\s*//' | tr -d '"')
      if [[ -n "${token}" ]]; then
        printf '%s\n' "${token}" > "${TOKEN_FILE}"
        chmod 600 "${TOKEN_FILE}"
      fi
    fi
  else
    echo "==> influx setup (org=${INFLUX_ORG}, bucket=${INFLUX_BUCKET}, user=${INFLUX_USER})"
    if [[ -z "${INFLUX_TOKEN:-}" ]]; then
      if command -v openssl >/dev/null 2>&1; then
        INFLUX_TOKEN="$(openssl rand -hex 32)"
      else
        INFLUX_TOKEN="$(date +%s)-iot-hub-$(id -u)"
      fi
    fi
    influx setup \
      --username "${INFLUX_USER}" \
      --password "${INFLUX_ADMIN_PASSWORD}" \
      --org "${INFLUX_ORG}" \
      --bucket "${INFLUX_BUCKET}" \
      --retention "${INFLUX_RETENTION}" \
      --token "${INFLUX_TOKEN}" \
      --force
    token="${INFLUX_TOKEN}"
    printf '%s\n' "${token}" > "${TOKEN_FILE}"
    chmod 600 "${TOKEN_FILE}"
    echo "    Token kaydedildi: ${TOKEN_FILE}"
  fi
fi

if [[ ! -f "${TOKEN_FILE}" ]]; then
  echo "HATA: Token dosyası yok: ${TOKEN_FILE}. influx setup çalıştırın veya INFLUX_TOKEN_FILE belirtin." >&2
  exit 1
fi

TOKEN="$(tr -d '[:space:]' < "${TOKEN_FILE}")"

echo "==> Bucket kontrolü: ${INFLUX_BUCKET}"
if ! influx bucket list --org "${INFLUX_ORG}" --token "${TOKEN}" 2>/dev/null | grep -qw "${INFLUX_BUCKET}"; then
  influx bucket create --name "${INFLUX_BUCKET}" --org "${INFLUX_ORG}" --token "${TOKEN}" --retention "${INFLUX_RETENTION}"
  echo "    Bucket oluşturuldu"
else
  echo "    Bucket zaten var"
fi

echo "==> hub-api .env güncelleme (${ENV_FILE})"
if [[ ! -f "${ENV_FILE}" ]]; then
  if [[ -f "${HOME}/hub-api/.env.example" ]]; then
    cp "${HOME}/hub-api/.env.example" "${ENV_FILE}"
  else
    touch "${ENV_FILE}"
    cat >> "${ENV_FILE}" << EOF
INFLUX_URL=http://localhost:8086
INFLUX_ORG=${INFLUX_ORG}
INFLUX_BUCKET=${INFLUX_BUCKET}
INFLUX_MEASUREMENT=telemetry
MQTT_BROKER=127.0.0.1
MQTT_PORT=1883
EOF
  fi
  chmod 600 "${ENV_FILE}"
fi

if grep -q '^INFLUX_TOKEN=' "${ENV_FILE}" 2>/dev/null; then
  sed -i.bak "s|^INFLUX_TOKEN=.*|INFLUX_TOKEN=${TOKEN}|" "${ENV_FILE}"
  rm -f "${ENV_FILE}.bak"
else
  echo "INFLUX_TOKEN=${TOKEN}" >> "${ENV_FILE}"
fi

echo "==> Tamam. UI: http://$(hostname -I | awk '{print $1}'):8086"
echo "    Token: ${TOKEN_FILE}"
