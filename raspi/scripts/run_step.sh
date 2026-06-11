#!/usr/bin/env bash
# Mac'ten tek adım çalıştır: ./run_step.sh 0
set -euo pipefail
STEP="${1:?Kullanım: ./run_step.sh <0-6|4b>}"
PI="${PI:-kutay@172.20.10.5}"
PW="${PI_SSH_PASSWORD:-kutay123}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${ROOT}/scripts/pi_step.log"
STEP_FILE="${ROOT}/scripts/steps/step${STEP}_*.sh"
STEP_PATH="$(ls ${ROOT}/scripts/steps/step${STEP}_*.sh 2>/dev/null | head -1)"

[[ -f "${STEP_PATH}" ]] || { echo "Adım ${STEP} bulunamadı"; exit 1; }

echo "" | tee -a "${LOG}"
echo ">>> [$(date +%H:%M:%S)] ADIM ${STEP} başlıyor: $(basename "${STEP_PATH}")" | tee -a "${LOG}"

expect <<EOF 2>&1 | tee -a "${LOG}"
set timeout 600
log_user 1
spawn scp -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new "${STEP_PATH}" ${PI}:/tmp/iot_step.sh
expect {
  -gl "*password:*" { send "${PW}\r"; exp_continue }
  -gl "*Password:*" { send "${PW}\r"; exp_continue }
  eof
}
EOF

expect <<EOF 2>&1 | tee -a "${LOG}"
set timeout 600
log_user 1
spawn ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new -t ${PI} "chmod +x /tmp/iot_step.sh && stdbuf -oL bash /tmp/iot_step.sh"
expect {
  -gl "*password:*" { send "${PW}\r"; exp_continue }
  -gl "*Password:*" { send "${PW}\r"; exp_continue }
  eof
}
EOF

echo ">>> [$(date +%H:%M:%S)] ADIM ${STEP} bitti (log: pi_step.log)" | tee -a "${LOG}"
