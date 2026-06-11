#!/usr/bin/env bash
set -uo pipefail
log() { echo "[$(date +%H:%M:%S)] $*"; }
log "=== STEP 1: SİSTEM BİLGİSİ ==="
echo "  hostname: $(hostname)"
echo "  mimari:   $(uname -m)"
echo "  uptime:   $(uptime | sed 's/.*up/up/')"
echo "  disk:     $(df -h / | tail -1 | awk '{print $4 " boş / " $2}')"
command -v influx >/dev/null && echo "  influx:   $(influx version 2>/dev/null | head -1)" || echo "  influx:   YOK"
dpkg -s influxdb2 >/dev/null 2>&1 && echo "  influxdb2 paketi: kurulu" || echo "  influxdb2 paketi: YOK"
log "=== STEP 1 BİTTİ ==="
