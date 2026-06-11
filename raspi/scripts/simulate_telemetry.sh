#!/usr/bin/env bash
# Gerçekçi MQTT telemetri simülatörü (Mac'ten Pi'ye).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BROKER="${MQTT_BROKER:-172.20.10.5}"
INTERVAL="${SIM_INTERVAL:-5}"

if ! python3 -c "import paho.mqtt.client" 2>/dev/null; then
  echo "paho-mqtt kuruluyor…"
  pip3 install --user 'paho-mqtt>=2.0,<3'
fi

exec python3 "${ROOT}/simulate_telemetry.py" \
  --broker "${BROKER}" \
  --interval "${INTERVAL}" \
  "$@"
