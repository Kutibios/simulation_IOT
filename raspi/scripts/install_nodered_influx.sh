#!/usr/bin/env bash
# Raspberry Pi: Node-RED InfluxDB 2 contrib modülü.
set -euo pipefail

NODE_RED_DIR="${NODE_RED_DIR:-${HOME}/.node-red}"

echo "==> Node-RED dizini: ${NODE_RED_DIR}"
mkdir -p "${NODE_RED_DIR}"
cd "${NODE_RED_DIR}"

if [[ ! -f package.json ]]; then
  echo "==> package.json yok; npm init -y"
  npm init -y >/dev/null
fi

echo "==> node-red-contrib-influxdb kurulumu (idempotent)"
npm install node-red-contrib-influxdb

echo "==> Node-RED yeniden başlatılıyor"
if systemctl is-active --quiet nodered 2>/dev/null; then
  sudo systemctl restart nodered
elif systemctl is-active --quiet nodered.service 2>/dev/null; then
  sudo systemctl restart nodered.service
else
  echo "    Servis bulunamadı. Elle: node-red-restart veya systemctl restart nodered"
fi

echo "==> Tamam"
