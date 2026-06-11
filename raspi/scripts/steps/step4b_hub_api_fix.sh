#!/usr/bin/env bash
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }
log "=== STEP 4b: hub-api onarım ==="
mkdir -p ~/hub-api
cat > ~/hub-api/postgres_client.py << 'PYEOF'
from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

import config

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    psycopg2 = None  # type: ignore


def _dsn() -> str:
    return os.environ.get(
        "DATABASE_URL",
        "postgresql://iothub:iothub123@localhost:5432/iot_telemetry",
    )


def fetch_recent(
    problem_id: str,
    takim_no: str,
    minutes: int = 15,
) -> list[dict[str, Any]]:
    if psycopg2 is None:
        raise RuntimeError("psycopg2 yüklü değil")
    conn = psycopg2.connect(_dsn())
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                SELECT time, sensor, sicaklik, nem, hava_kalitesi
                FROM telemetry
                WHERE problem_id = %s AND takim_no = %s
                  AND time >= NOW() - (%s || ' minutes')::interval
                ORDER BY time ASC
                """,
                (problem_id, takim_no, str(int(minutes))),
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    records: list[dict[str, Any]] = []
    for row in rows:
        t = row["time"]
        if isinstance(t, datetime):
            if t.tzinfo is None:
                t = t.replace(tzinfo=timezone.utc)
            ts = t.isoformat().replace("+00:00", "Z")
        else:
            ts = str(t)
        records.append(
            {
                "time": ts,
                "sensor": row.get("sensor"),
                "sicaklik": row.get("sicaklik"),
                "nem": row.get("nem"),
                "hava_kalitesi": row.get("hava_kalitesi"),
            }
        )
    return records
PYEOF
log "  postgres_client.py yazıldı ($(wc -c < ~/hub-api/postgres_client.py) byte)"
cd ~/hub-api
./.venv/bin/pip install -q --prefer-binary psycopg2-binary
echo "${PW}" | sudo -S systemctl restart iot-hub-api
sleep 3
if curl -sf http://127.0.0.1:5000/health; then
  log "  /health OK"
else
  log "  journal:"
  echo "${PW}" | sudo -S journalctl -u iot-hub-api -n 15 --no-pager | sed 's/^/    /'
  exit 1
fi
log "=== STEP 4b BİTTİ ==="
