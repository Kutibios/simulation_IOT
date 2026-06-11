#!/usr/bin/env bash
# Mac'teki .env dosyasındaki GEMINI_API_KEY'i Pi'ye yazar.
set -euo pipefail
PI="${PI:-kutay@172.20.10.5}"
PW="${PI_SSH_PASSWORD:-kutay123}"
ENV_LOCAL="${1:-$(cd "$(dirname "$0")/../../.." && pwd)/.env}"

[[ -f "${ENV_LOCAL}" ]] || { echo "HATA: ${ENV_LOCAL} bulunamadı"; exit 1; }
KEY="$(grep -E '^GEMINI_API_KEY=' "${ENV_LOCAL}" | head -1 | cut -d= -f2- | tr -d '\r')"
[[ -n "${KEY}" ]] || { echo "HATA: GEMINI_API_KEY .env içinde yok"; exit 1; }

expect <<EOF
set timeout 60
spawn ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new ${PI} "mkdir -p ~/.config/iot-hub && touch ~/.config/iot-hub/.env && chmod 600 ~/.config/iot-hub/.env && if grep -q '^GEMINI_API_KEY=' ~/.config/iot-hub/.env; then sed -i.bak 's|^GEMINI_API_KEY=.*|GEMINI_API_KEY=${KEY}|' ~/.config/iot-hub/.env; else echo 'GEMINI_API_KEY=${KEY}' >> ~/.config/iot-hub/.env; fi && echo kutay123 | sudo -S systemctl restart iot-hub-api && sleep 2 && curl -sf http://127.0.0.1:5000/health"
expect { -gl "*password:*" { send "${PW}\r"; exp_continue } eof }
EOF
