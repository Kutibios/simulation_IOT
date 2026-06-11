#!/usr/bin/env bash
# Hub uçtan uca smoke test (Mac'ten Pi'ye veya Pi üzerinde).
set -euo pipefail

PI_HOST="${PI_HOST:-172.20.10.5}"
PI_USER="${PI_USER:-kutay}"
HUB_URL="${HUB_URL:-http://${PI_HOST}:5000}"
MQTT_HOST="${MQTT_HOST:-${PI_HOST}}"
MQTT_PORT="${MQTT_PORT:-1883}"

PROBLEM_ID="${PROBLEM_ID:-tarim_sulama}"
TAKIM_NO="${TAKIM_NO:-7}"
TEST_SENSOR="${TEST_SENSOR:-test_hub_$(date +%s)}"

INFLUX_ORG="${INFLUX_ORG:-iot-hub}"
INFLUX_BUCKET="${INFLUX_BUCKET:-iot_telemetry}"
INFLUX_MEASUREMENT="${INFLUX_MEASUREMENT:-telemetry}"

pass=0
fail=0

ok() { echo "OK  $*"; pass=$((pass + 1)); }
bad() { echo "FAIL $*" >&2; fail=$((fail + 1)); }

echo "==> Hedef hub: ${HUB_URL}"
echo "==> MQTT: ${MQTT_HOST}:${MQTT_PORT}"

echo "==> 1) GET /health"
health_json="$(curl -fsS "${HUB_URL}/health" 2>/dev/null)" && ok "/health" || health_json=""
if [[ -n "${health_json}" ]]; then
  echo "    ${health_json}"
else
  bad "/health erişilemedi"
fi

echo "==> 2) POST /analyze (Gemini yoksa kural tabanlı fallback)"
analyze_json="$(curl -fsS -X POST "${HUB_URL}/analyze" \
  -H 'Content-Type: application/json' \
  -d "{\"problem_id\":\"${PROBLEM_ID}\",\"takim_no\":\"${TAKIM_NO}\",\"window_min\":15}" 2>/dev/null)" && ok "/analyze" || analyze_json=""
if [[ -n "${analyze_json}" ]]; then
  echo "    ${analyze_json}"
  if echo "${analyze_json}" | grep -q '"aksiyon"'; then
    ok "analyze aksiyon alanı"
  else
    bad "analyze yanıtında aksiyon yok"
  fi
else
  bad "/analyze başarısız"
fi

echo "==> 3) MQTT telemetry yayını"
payload=$(cat <<EOF
{"sensor":"${TEST_SENSOR}","sicaklik":26.5,"nem":42.0,"hava_kalitesi":180,"problem_id":"${PROBLEM_ID}","takim_no":"${TAKIM_NO}","timestamp":"$(date -u +%Y-%m-%dT%H:%M:%SZ)"}
EOF
)
topic="${PROBLEM_ID}/${TAKIM_NO}/telemetry"
if command -v mosquitto_pub >/dev/null 2>&1; then
  if mosquitto_pub -h "${MQTT_HOST}" -p "${MQTT_PORT}" -t "${topic}" -m "${payload}" -q 1; then
    ok "mosquitto_pub ${topic}"
  else
    bad "mosquitto_pub"
  fi
else
  bad "mosquitto_pub yüklü değil (brew install mosquitto)"
fi

echo "==> 4) InfluxDB / history doğrulama"
sleep "${INFLUX_WAIT_SEC:-5}"

history_json="$(curl -fsS "${HUB_URL}/history/${PROBLEM_ID}/${TAKIM_NO}?minutes=5" 2>/dev/null)" || history_json=""
if [[ -n "${history_json}" ]] && echo "${history_json}" | grep -q '"count"'; then
  count="$(echo "${history_json}" | sed -n 's/.*"count"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -1)"
  echo "    history count=${count:-?}"
  if [[ "${count:-0}" -gt 0 ]]; then
    ok "Influx üzerinden history kaydı"
  else
    echo "    Not: Node-RED Influx akışı yoksa count 0 olabilir; doğrudan sorgu deneniyor"
  fi
else
  echo "    history API yanıt alınamadı"
fi

influx_ok=false
if command -v influx >/dev/null 2>&1; then
  TOKEN="${INFLUX_TOKEN:-}"
  if [[ -z "${TOKEN}" && -f "${HOME}/.config/iot-hub/influx-admin.token" ]]; then
    TOKEN="$(tr -d '[:space:]' < "${HOME}/.config/iot-hub/influx-admin.token")"
  fi
  if [[ -n "${TOKEN}" ]]; then
    query="from(bucket: \"${INFLUX_BUCKET}\") |> range(start: -10m) |> filter(fn: (r) => r._measurement == \"${INFLUX_MEASUREMENT}\") |> filter(fn: (r) => r[\"problem_id\"] == \"${PROBLEM_ID}\") |> filter(fn: (r) => r[\"takim_no\"] == \"${TAKIM_NO}\") |> limit(n: 3)"
    if influx query --org "${INFLUX_ORG}" --token "${TOKEN}" "${query}" 2>/dev/null | grep -q .; then
      influx_ok=true
      ok "influx query telemetri buldu"
    fi
  fi
fi

if [[ "${influx_ok}" == false ]]; then
  if [[ -n "${history_json}" ]] && echo "${history_json}" | grep -q '"records"'; then
    if echo "${history_json}" | grep -q "${TEST_SENSOR}"; then
      ok "history API test sensörünü gördü"
      influx_ok=true
    fi
  fi
fi

if [[ "${influx_ok}" == false ]]; then
  bad "Influx/history doğrulaması (Node-RED -> Influx akışını kontrol edin)"
fi

echo "==> Özet: ${pass} OK, ${fail} FAIL"
if [[ "${fail}" -gt 0 ]]; then
  exit 1
fi
