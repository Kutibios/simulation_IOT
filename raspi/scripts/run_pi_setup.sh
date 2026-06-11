#!/usr/bin/env bash
# Mac'ten çalıştır: ./run_pi_setup.sh
# Terminalde anlık ilerleme görürsün.
set -euo pipefail

PI="kutay@172.20.10.5"
PW="kutay123"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="${ROOT}/scripts/pi_setup.log"

ssh_pi() {
  expect <<EOF
set timeout -1
spawn ssh -o StrictHostKeyChecking=accept-new -t ${PI} "$*"
expect {
  -re "(password|Password):" { send "${PW}\r"; exp_continue }
  eof
}
EOF
}

scp_pi() {
  expect <<EOF
set timeout 120
spawn scp -o StrictHostKeyChecking=accept-new "$1" ${PI}:$2
expect {
  -re "(password|Password):" { send "${PW}\r"; exp_continue }
  eof
}
EOF
}

echo ">>> [$(date +%H:%M:%S)] Dosyalar yükleniyor..." | tee "$LOG"
scp_pi "${ROOT}/scripts/remote_pi_setup.sh" /home/kutay/remote_pi_setup.sh
scp_pi "${ROOT}/hub-api/requirements-pi.txt" /home/kutay/hub-api/requirements-pi.txt

echo ">>> [$(date +%H:%M:%S)] Eski pip süreçleri durduruluyor..." | tee -a "$LOG"
ssh_pi "pkill -f 'pip install' 2>/dev/null || true"

echo ">>> [$(date +%H:%M:%S)] Kurulum başlıyor (5 adım)..." | tee -a "$LOG"
ssh_pi "chmod +x ~/remote_pi_setup.sh && stdbuf -oL bash ~/remote_pi_setup.sh" 2>&1 | tee -a "$LOG"

echo ">>> [$(date +%H:%M:%S)] Bitti. Log: $LOG" | tee -a "$LOG"
