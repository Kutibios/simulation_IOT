#!/usr/bin/env bash
# armv7l Pi: hatalı arm64 InfluxDB kaldır, PostgreSQL kur.
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 3: PostgreSQL (InfluxDB arm64 → kaldır) ==="
log "  Mimari: $(uname -m) — InfluxDB2 arm64 bu Pi'de çalışmaz (exit 126)"

if dpkg -s influxdb2 >/dev/null 2>&1; then
  log "  influxdb2 kaldırılıyor..."
  echo "${PW}" | sudo -S systemctl stop influxdb 2>/dev/null || true
  echo "${PW}" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get remove -y influxdb2 influxdb2-cli 2>/dev/null || true
fi

if ! dpkg -s postgresql >/dev/null 2>&1; then
  log "  postgresql kuruluyor (1-3 dk)..."
  echo "${PW}" | sudo -S apt-get update -qq
  echo "${PW}" | sudo -S DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql postgresql-client
else
  log "  postgresql zaten kurulu"
fi

echo "${PW}" | sudo -S systemctl enable postgresql
echo "${PW}" | sudo -S systemctl start postgresql

log "  veritabanı oluşturuluyor..."
echo "${PW}" | sudo -S -u postgres psql -tc "SELECT 1 FROM pg_roles WHERE rolname='iothub'" | grep -q 1 || \
  echo "${PW}" | sudo -S -u postgres psql -c "CREATE USER iothub WITH PASSWORD 'iothub123';"
echo "${PW}" | sudo -S -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname='iot_telemetry'" | grep -q 1 || \
  echo "${PW}" | sudo -S -u postgres psql -c "CREATE DATABASE iot_telemetry OWNER iothub;"

echo "${PW}" | sudo -S -u postgres psql -d iot_telemetry <<'SQL'
CREATE TABLE IF NOT EXISTS telemetry (
  id SERIAL PRIMARY KEY,
  time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  problem_id TEXT NOT NULL,
  takim_no TEXT NOT NULL,
  sensor TEXT,
  sicaklik DOUBLE PRECISION,
  nem DOUBLE PRECISION,
  hava_kalitesi DOUBLE PRECISION
);
CREATE INDEX IF NOT EXISTS idx_telemetry_lookup ON telemetry (problem_id, takim_no, time DESC);
GRANT ALL PRIVILEGES ON TABLE telemetry TO iothub;
GRANT USAGE, SELECT ON SEQUENCE telemetry_id_seq TO iothub;
SQL

CONFIG="${HOME}/.config/iot-hub"
mkdir -p "${CONFIG}"
ENV="${CONFIG}/.env"
touch "${ENV}"
grep -q '^DATABASE_URL=' "${ENV}" 2>/dev/null || \
  echo "DATABASE_URL=postgresql://iothub:iothub123@localhost:5432/iot_telemetry" >> "${ENV}"
chmod 600 "${ENV}"

log "  PostgreSQL: $(echo ${PW} | sudo -S systemctl is-active postgresql)"
log "=== STEP 3 BİTTİ ==="
