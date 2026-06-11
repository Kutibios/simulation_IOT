#!/usr/bin/env bash
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }
log "=== STEP 6: MQTT ingest + flows + hub-api ==="
mkdir -p ~/hub-api
cat > ~/hub-api/main.py << 'MAINPYEOF'
from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

import config
from gemini_client import analyze_with_gemini
from postgres_client import fetch_recent
from mqtt_client import publish_command

app = FastAPI(title="IoT Hub API", version="1.0.0")


class AnalyzeRequest(BaseModel):
    problem_id: str
    takim_no: str
    window_min: int = Field(default=15, ge=1, le=1440)


class CommandRequest(BaseModel):
    problem_id: str
    takim_no: str
    aksiyon: str
    sure_sn: int = Field(ge=0)


def _validate_problem(problem_id: str) -> None:
    if problem_id not in config.VALID_PROBLEM_IDS:
        raise HTTPException(
            status_code=400,
            detail=f"Geçersiz problem_id: {problem_id}. İzin verilen: {sorted(config.VALID_PROBLEM_IDS)}",
        )


@app.get("/health")
def health() -> dict[str, Any]:
    db_url = getattr(config, "DATABASE_URL", "")
    return {
        "status": "ok",
        "database": "postgresql" if db_url else "none",
        "postgres_configured": bool(db_url),
        "gemini_configured": bool(config.GEMINI_API_KEY),
        "mqtt_broker": f"{config.MQTT_BROKER}:{config.MQTT_PORT}",
    }


@app.post("/analyze")
def analyze(body: AnalyzeRequest) -> dict[str, Any]:
    _validate_problem(body.problem_id)
    try:
        records = fetch_recent(body.problem_id, body.takim_no, body.window_min)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Veritabanı sorgu hatası: {exc}") from exc

    result = analyze_with_gemini(body.problem_id, body.takim_no, records)
    return {
        "problem_id": body.problem_id,
        "takim_no": body.takim_no,
        "window_min": body.window_min,
        "record_count": len(records),
        **result,
    }


@app.get("/history/{problem_id}/{takim_no}")
def history(
    problem_id: str,
    takim_no: str,
    minutes: int = Query(default=15, ge=1, le=1440),
) -> dict[str, Any]:
    _validate_problem(problem_id)
    try:
        records = fetch_recent(problem_id, takim_no, minutes)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Veritabanı sorgu hatası: {exc}") from exc

    return {
        "problem_id": problem_id,
        "takim_no": takim_no,
        "minutes": minutes,
        "count": len(records),
        "records": records,
    }


@app.post("/command")
def command(body: CommandRequest) -> dict[str, Any]:
    _validate_problem(body.problem_id)
    try:
        published = publish_command(
            body.problem_id,
            body.takim_no,
            body.aksiyon,
            body.sure_sn,
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"MQTT yayın hatası: {exc}") from exc

    return {
        "ok": True,
        **published,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host=config.API_HOST, port=config.API_PORT, reload=False)
MAINPYEOF
cat > ~/hub-api/config.py << 'CONFIGPYEOF'
from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv

DEFAULT_ENV_FILE = Path.home() / ".config" / "iot-hub" / ".env"


def _load_env() -> None:
    env_file = Path(os.environ.get("IOT_HUB_ENV_FILE", DEFAULT_ENV_FILE))
    if env_file.is_file():
        load_dotenv(env_file)
    load_dotenv()


_load_env()

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "").strip()
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.0-flash").strip()

INFLUX_URL = os.environ.get("INFLUX_URL", "http://localhost:8086").strip()
INFLUX_TOKEN = os.environ.get("INFLUX_TOKEN", "").strip()
INFLUX_ORG = os.environ.get("INFLUX_ORG", "iot-hub").strip()
INFLUX_BUCKET = os.environ.get("INFLUX_BUCKET", "iot_telemetry").strip()
INFLUX_MEASUREMENT = os.environ.get("INFLUX_MEASUREMENT", "telemetry").strip()
DATABASE_URL = os.environ.get("DATABASE_URL", "").strip()

MQTT_BROKER = os.environ.get("MQTT_BROKER", "127.0.0.1").strip()
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))

API_HOST = os.environ.get("API_HOST", "0.0.0.0").strip()
API_PORT = int(os.environ.get("API_PORT", "5000"))

VALID_PROBLEM_IDS = frozenset({"tarim_sulama", "tarim_havalandirma"})
CONFIGPYEOF
cat > ~/hub-api/postgres_client.py << 'POSTGRES_CLIENTPYEOF'
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


def insert_telemetry(
    problem_id: str,
    takim_no: str,
    sensor: str | None,
    sicaklik: float | None,
    nem: float | None,
    hava_kalitesi: float | None,
) -> None:
    if psycopg2 is None:
        raise RuntimeError("psycopg2 yüklü değil")
    conn = psycopg2.connect(_dsn())
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO telemetry (problem_id, takim_no, sensor, sicaklik, nem, hava_kalitesi)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (problem_id, takim_no, sensor, sicaklik, nem, hava_kalitesi),
            )
        conn.commit()
    finally:
        conn.close()
POSTGRES_CLIENTPYEOF
cat > ~/hub-api/iot-hub-api.service << 'IOT-HUB-APISERVICEEOF'
[Unit]
Description=IoT Hub REST API (FastAPI)
After=network.target mosquitto.service postgresql.service
Wants=mosquitto.service postgresql.service

[Service]
Type=simple
User=kutay
Group=kutay
WorkingDirectory=/home/kutay/hub-api
Environment=IOT_HUB_ENV_FILE=/home/kutay/.config/iot-hub/.env
ExecStart=/home/kutay/hub-api/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 5000
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
IOT-HUB-APISERVICEEOF
cat > ~/mqtt_ingest.py << 'INGESTEOF'
#!/usr/bin/env python3
"""MQTT telemetry → PostgreSQL (Pi hub ingest)."""

from __future__ import annotations

import json
import os
import sys
from typing import Any

import paho.mqtt.client as mqtt

# hub-api venv içinden çalıştırılır; config + postgres_client aynı dizinde
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "hub-api"))

import config  # noqa: E402
from postgres_client import insert_telemetry  # noqa: E402

BROKER = config.MQTT_BROKER
PORT = config.MQTT_PORT
CLIENT_ID = os.environ.get("MQTT_INGEST_CLIENT_ID", f"iot_ingest_{os.getpid()}")
SUB_TOPIC = os.environ.get("MQTT_TELEMETRY_TOPIC", "+/+/telemetry")


def _num(value: Any) -> float | None:
    if value is None:
        return None
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    if n != n:  # NaN
        return None
    return n


def parse_telemetry(topic: str, payload: dict[str, Any]) -> dict[str, Any] | None:
    parts = topic.split("/")
    if len(parts) != 3 or parts[2] != "telemetry":
        return None

    problem_id = parts[0] or str(payload.get("problem_id", ""))
    takim_no = parts[1] or str(payload.get("takim_no", ""))
    if not problem_id or not takim_no:
        return None

    sensor = str(
        payload.get("sensor") or payload.get("cihaz_id") or payload.get("device_id") or "unknown"
    ).lower()

    values = payload.get("values") if isinstance(payload.get("values"), dict) else {}
    sicaklik = _num(payload.get("sicaklik", values.get("sicaklik")))
    nem = _num(payload.get("nem", values.get("nem")))
    hava_kalitesi = _num(payload.get("hava_kalitesi", values.get("hava_kalitesi")))

    if sicaklik is None and nem is None and hava_kalitesi is None:
        return None

    return {
        "problem_id": problem_id,
        "takim_no": takim_no,
        "sensor": sensor,
        "sicaklik": sicaklik,
        "nem": nem,
        "hava_kalitesi": hava_kalitesi,
    }


def on_connect(client, _userdata, _flags, reason_code, _properties):
    if reason_code.is_failure:
        print(f"[ingest] bağlantı hatası: {reason_code}", file=sys.stderr, flush=True)
        return
    client.subscribe(SUB_TOPIC, qos=0)
    print(f"[ingest] abone: {SUB_TOPIC} @ {BROKER}:{PORT}", flush=True)


def on_message(_client, _userdata, msg):
    try:
        text = msg.payload.decode("utf-8")
        payload = json.loads(text)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        print(f"[ingest] geçersiz mesaj {msg.topic}: {exc}", file=sys.stderr, flush=True)
        return

    if not isinstance(payload, dict):
        return

    row = parse_telemetry(msg.topic, payload)
    if row is None:
        return

    try:
        insert_telemetry(**row)
        print(
            f"[ingest] {row['problem_id']}/{row['takim_no']} "
            f"s={row['sicaklik']} n={row['nem']} h={row['hava_kalitesi']}",
            flush=True,
        )
    except Exception as exc:
        print(f"[ingest] DB hatası: {exc}", file=sys.stderr, flush=True)


def main() -> None:
    if not config.DATABASE_URL:
        print("[ingest] DATABASE_URL tanımlı değil", file=sys.stderr)
        sys.exit(1)

    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,  # type: ignore[attr-defined]
        client_id=CLIENT_ID,
    )
    client.on_connect = on_connect
    client.on_message = on_message
    client.connect(BROKER, PORT, keepalive=60)
    client.loop_forever()


if __name__ == "__main__":
    main()
INGESTEOF
cat > /tmp/iot-mqtt-ingest.service << 'SVCEOF'
[Unit]
Description=IoT Hub MQTT telemetry ingest (PostgreSQL)
After=network.target mosquitto.service postgresql.service
Wants=mosquitto.service postgresql.service

[Service]
Type=simple
User=kutay
Group=kutay
WorkingDirectory=/home/kutay
Environment=IOT_HUB_ENV_FILE=/home/kutay/.config/iot-hub/.env
ExecStart=/home/kutay/hub-api/.venv/bin/python /home/kutay/mqtt_ingest.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF
echo "${PW}" | sudo -S cp /tmp/iot-mqtt-ingest.service /etc/systemd/system/
echo "${PW}" | sudo -S cp ~/hub-api/iot-hub-api.service /etc/systemd/system/
echo "${PW}" | sudo -S systemctl daemon-reload
mkdir -p ~/.node-red
cp ~/.node-red/flows.json ~/.node-red/flows.json.bak.$(date +%s) 2>/dev/null || true
python3 << 'PYEOF'
import base64, pathlib
pathlib.Path.home().joinpath(".node-red/flows.json").write_bytes(base64.b64decode("""WwogICAgewogICAgICAgICJpZCI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgInR5cGUiOiAidGFiIiwKICAgICAgICAibGFiZWwiOiAiVGVsZW1ldHJ5IiwKICAgICAgICAiZGlzYWJsZWQiOiBmYWxzZSwKICAgICAgICAiaW5mbyI6ICIiLAogICAgICAgICJlbnYiOiBbXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiaHViX3RhYl95eiIsCiAgICAgICAgInR5cGUiOiAidGFiIiwKICAgICAgICAibGFiZWwiOiAiWVogQW5hbGl6IiwKICAgICAgICAiZGlzYWJsZWQiOiBmYWxzZSwKICAgICAgICAiaW5mbyI6ICIiLAogICAgICAgICJlbnYiOiBbXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiaHViX3RhYl9jb21tYW5kIiwKICAgICAgICAidHlwZSI6ICJ0YWIiLAogICAgICAgICJsYWJlbCI6ICJDb21tYW5kIExvZyIsCiAgICAgICAgImRpc2FibGVkIjogZmFsc2UsCiAgICAgICAgImluZm8iOiAiIiwKICAgICAgICAiZW52IjogW10KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImJyb2tlcjEiLAogICAgICAgICJ0eXBlIjogIm1xdHQtYnJva2VyIiwKICAgICAgICAibmFtZSI6ICJMb2NhbCBNb3NxdWl0dG8iLAogICAgICAgICJicm9rZXIiOiAibG9jYWxob3N0IiwKICAgICAgICAicG9ydCI6ICIxODgzIiwKICAgICAgICAiY2xpZW50aWQiOiAibm9kZXJlZF9odWIiLAogICAgICAgICJ1c2V0bHMiOiBmYWxzZSwKICAgICAgICAia2VlcGFsaXZlIjogIjYwIiwKICAgICAgICAiY2xlYW5zZXNzaW9uIjogdHJ1ZQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAidWlfYmFzZV9odWIiLAogICAgICAgICJ0eXBlIjogInVpX2Jhc2UiLAogICAgICAgICJ0aGVtZSI6IHsKICAgICAgICAgICAgIm5hbWUiOiAidGhlbWUtbGlnaHQiCiAgICAgICAgfSwKICAgICAgICAic2l0ZSI6IHsKICAgICAgICAgICAgIm5hbWUiOiAiSW9UIEh1YiBEYXNoYm9hcmQiCiAgICAgICAgfQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAidGFiMSIsCiAgICAgICAgInR5cGUiOiAidWlfdGFiIiwKICAgICAgICAibmFtZSI6ICJBa8SxbGzEsSBTaXN0ZW1sZXIiLAogICAgICAgICJpY29uIjogImRhc2hib2FyZCIsCiAgICAgICAgIm9yZGVyIjogMSwKICAgICAgICAiZGlzYWJsZWQiOiBmYWxzZQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiZ3JvdXBfc3VsYW1hIiwKICAgICAgICAidHlwZSI6ICJ1aV9ncm91cCIsCiAgICAgICAgIm5hbWUiOiAiU3VsYW1hIiwKICAgICAgICAidGFiIjogInRhYjEiLAogICAgICAgICJvcmRlciI6IDEsCiAgICAgICAgImRpc3AiOiB0cnVlLAogICAgICAgICJ3aWR0aCI6ICIxMiIsCiAgICAgICAgImNvbGxhcHNlIjogZmFsc2UKICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImdyb3VwX2hhdmEiLAogICAgICAgICJ0eXBlIjogInVpX2dyb3VwIiwKICAgICAgICAibmFtZSI6ICJIYXZhbGFuZMSxcm1hIiwKICAgICAgICAidGFiIjogInRhYjEiLAogICAgICAgICJvcmRlciI6IDIsCiAgICAgICAgImRpc3AiOiB0cnVlLAogICAgICAgICJ3aWR0aCI6ICIxMiIsCiAgICAgICAgImNvbGxhcHNlIjogZmFsc2UKICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImh1Yl9nbG9iYWxfY2ZnIiwKICAgICAgICAidHlwZSI6ICJnbG9iYWwtY29uZmlnIiwKICAgICAgICAiZW52IjogW10sCiAgICAgICAgIm1vZHVsZXMiOiB7CiAgICAgICAgICAgICJub2RlLXJlZC1kYXNoYm9hcmQiOiAiMy42LjYiCiAgICAgICAgfQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAibXF0dF90ZWxlbWV0cnlfaW4iLAogICAgICAgICJ0eXBlIjogIm1xdHQgaW4iLAogICAgICAgICJ6IjogImh1Yl90YWJfdGVsZW1ldHJ5IiwKICAgICAgICAibmFtZSI6ICJUw7xtIFRlbGVtZXRyeSIsCiAgICAgICAgInRvcGljIjogIisvKy90ZWxlbWV0cnkiLAogICAgICAgICJxb3MiOiAiMSIsCiAgICAgICAgImJyb2tlciI6ICJicm9rZXIxIiwKICAgICAgICAiaW5wdXRzIjogMCwKICAgICAgICAieCI6IDE0MCwKICAgICAgICAieSI6IDIwMCwKICAgICAgICAid2lyZXMiOiBbCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJqc29uX3RlbGVtZXRyeSIKICAgICAgICAgICAgXQogICAgICAgIF0KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImpzb25fdGVsZW1ldHJ5IiwKICAgICAgICAidHlwZSI6ICJqc29uIiwKICAgICAgICAieiI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgIm5hbWUiOiAiSlNPTiBQYXJzZSIsCiAgICAgICAgInByb3BlcnR5IjogInBheWxvYWQiLAogICAgICAgICJhY3Rpb24iOiAiIiwKICAgICAgICAicHJldHR5IjogZmFsc2UsCiAgICAgICAgIngiOiAzMzAsCiAgICAgICAgInkiOiAyMDAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAiZnVuY192ZXJpeWlfYXlpciIsCiAgICAgICAgICAgICAgICAiZnVuY190aHJlc2hvbGQiLAogICAgICAgICAgICAgICAgImRlYnVnX3RlbGVtZXRyeSIKICAgICAgICAgICAgXQogICAgICAgIF0KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImRlYnVnX3RlbGVtZXRyeSIsCiAgICAgICAgInR5cGUiOiAiZGVidWciLAogICAgICAgICJ6IjogImh1Yl90YWJfdGVsZW1ldHJ5IiwKICAgICAgICAibmFtZSI6ICJUZWxlbWV0cnkgRGVidWciLAogICAgICAgICJhY3RpdmUiOiB0cnVlLAogICAgICAgICJ0b3NpZGViYXIiOiB0cnVlLAogICAgICAgICJjb25zb2xlIjogZmFsc2UsCiAgICAgICAgImNvbXBsZXRlIjogInBheWxvYWQiLAogICAgICAgICJ0YXJnZXRUeXBlIjogIm1zZyIsCiAgICAgICAgIngiOiAzMzAsCiAgICAgICAgInkiOiAzMDAsCiAgICAgICAgIndpcmVzIjogW10KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImZ1bmNfdmVyaXlpX2F5aXIiLAogICAgICAgICJ0eXBlIjogImZ1bmN0aW9uIiwKICAgICAgICAieiI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgIm5hbWUiOiAiVmVyaXlpIEF5xLFyIChIdWIpIiwKICAgICAgICAiZnVuYyI6ICIvLyA2IMOnxLFrxLHFnzpcbi8vIDEg4oaSIERTMThCMjAgc8SxY2FrbMSxayBnYXVnZVxuLy8gMiDihpIgREhUMTEgc8SxY2FrbMSxayBnYXVnZVxuLy8gMyDihpIgTmVtIGdhdWdlXG4vLyA0IOKGkiBTxLFjYWtsxLFrIGNoYXJ0ICh0b3BpYzogZHMxOGIyMCwgZGh0MTEpXG4vLyA1IOKGkiBOZW0gY2hhcnQgKHRvcGljOiBkaHQxMV9uZW0pXG4vLyA2IOKGkiBIYXZhIGthbGl0ZXNpIGdhdWdlICh0YXJpbV9oYXZhbGFuZGlybWEgLyBNUSBzZW5zw7ZybGVyaSlcblxuY29uc3QgcCA9IG1zZy5wYXlsb2FkO1xuaWYgKCFwIHx8IHR5cGVvZiBwICE9PSBcIm9iamVjdFwiKSB7XG4gICAgcmV0dXJuIG51bGw7XG59XG5cbmNvbnN0IHRvcGljUGFydHMgPSBTdHJpbmcobXNnLnRvcGljIHx8IFwiXCIpLnNwbGl0KFwiL1wiKTtcbmNvbnN0IHByb2JsZW1faWQgPSB0b3BpY1BhcnRzWzBdIHx8IHAucHJvYmxlbV9pZCB8fCBcInVua25vd25cIjtcbmNvbnN0IHRha2ltX25vID0gdG9waWNQYXJ0c1sxXSB8fCBwLnRha2ltX25vIHx8IFwidW5rbm93blwiO1xuXG5jb25zdCBzZW5zb3IgPSBTdHJpbmcocC5zZW5zb3IgfHwgcC5jaWhhel9pZCB8fCBwLmRldmljZV9pZCB8fCBcInVua25vd25cIikudG9Mb3dlckNhc2UoKTtcblxubGV0IHNpY2FrbGlrID0gcC5zaWNha2xpaztcbmxldCBuZW0gPSBwLm5lbTtcbmxldCBoYXZhX2thbGl0ZXNpID0gcC5oYXZhX2thbGl0ZXNpO1xuXG5pZiAocC52YWx1ZXMgJiYgdHlwZW9mIHAudmFsdWVzID09PSBcIm9iamVjdFwiKSB7XG4gICAgaWYgKHNpY2FrbGlrID09PSB1bmRlZmluZWQpIHNpY2FrbGlrID0gcC52YWx1ZXMuc2ljYWtsaWs7XG4gICAgaWYgKG5lbSA9PT0gdW5kZWZpbmVkKSBuZW0gPSBwLnZhbHVlcy5uZW07XG4gICAgaWYgKGhhdmFfa2FsaXRlc2kgPT09IHVuZGVmaW5lZCkgaGF2YV9rYWxpdGVzaSA9IHAudmFsdWVzLmhhdmFfa2FsaXRlc2k7XG59XG5cbmNvbnN0IGlzRHMxOCA9IHNlbnNvci5pbmNsdWRlcyhcImRzMThcIik7XG5jb25zdCBpc0RodCA9IHNlbnNvci5pbmNsdWRlcyhcImRodFwiKTtcblxuY29uc3Qgb3V0RHMxOEdhdWdlID0gW107XG5jb25zdCBvdXREaHRUZW1wR2F1Z2UgPSBbXTtcbmNvbnN0IG91dE5lbUdhdWdlID0gW107XG5jb25zdCBvdXRUZW1wQ2hhcnQgPSBbXTtcbmNvbnN0IG91dE5lbUNoYXJ0ID0gW107XG5jb25zdCBvdXRIYXZhR2F1Z2UgPSBbXTtcblxuaWYgKHNpY2FrbGlrICE9PSB1bmRlZmluZWQgJiYgc2ljYWtsaWsgIT09IG51bGwgJiYgIU51bWJlci5pc05hTihOdW1iZXIoc2ljYWtsaWspKSkge1xuICAgIGNvbnN0IHQgPSBOdW1iZXIoc2ljYWtsaWspO1xuXG4gICAgaWYgKGlzRHMxOCkge1xuICAgICAgICBvdXREczE4R2F1Z2UucHVzaCh7IHBheWxvYWQ6IHQsIHByb2JsZW1faWQsIHRha2ltX25vIH0pO1xuICAgICAgICBvdXRUZW1wQ2hhcnQucHVzaCh7IHBheWxvYWQ6IHQsIHRvcGljOiBcImRzMThiMjBcIiwgcHJvYmxlbV9pZCwgdGFraW1fbm8gfSk7XG4gICAgfSBlbHNlIGlmIChpc0RodCB8fCAobmVtICE9PSB1bmRlZmluZWQgJiYgbmVtICE9PSBudWxsKSkge1xuICAgICAgICBvdXREaHRUZW1wR2F1Z2UucHVzaCh7IHBheWxvYWQ6IHQsIHByb2JsZW1faWQsIHRha2ltX25vIH0pO1xuICAgICAgICBvdXRUZW1wQ2hhcnQucHVzaCh7IHBheWxvYWQ6IHQsIHRvcGljOiBcImRodDExXCIsIHByb2JsZW1faWQsIHRha2ltX25vIH0pO1xuICAgIH0gZWxzZSB7XG4gICAgICAgIG91dERzMThHYXVnZS5wdXNoKHsgcGF5bG9hZDogdCwgcHJvYmxlbV9pZCwgdGFraW1fbm8gfSk7XG4gICAgICAgIG91dFRlbXBDaGFydC5wdXNoKHsgcGF5bG9hZDogdCwgdG9waWM6IFwiZHMxOGIyMFwiLCBwcm9ibGVtX2lkLCB0YWtpbV9ubyB9KTtcbiAgICB9XG59XG5cbmlmIChuZW0gIT09IHVuZGVmaW5lZCAmJiBuZW0gIT09IG51bGwgJiYgIU51bWJlci5pc05hTihOdW1iZXIobmVtKSkpIHtcbiAgICBjb25zdCBuID0gTnVtYmVyKG5lbSk7XG4gICAgb3V0TmVtR2F1Z2UucHVzaCh7IHBheWxvYWQ6IG4sIHByb2JsZW1faWQsIHRha2ltX25vIH0pO1xuICAgIG91dE5lbUNoYXJ0LnB1c2goeyBwYXlsb2FkOiBuLCB0b3BpYzogXCJkaHQxMV9uZW1cIiwgcHJvYmxlbV9pZCwgdGFraW1fbm8gfSk7XG59XG5cbmlmIChoYXZhX2thbGl0ZXNpICE9PSB1bmRlZmluZWQgJiYgaGF2YV9rYWxpdGVzaSAhPT0gbnVsbCAmJiAhTnVtYmVyLmlzTmFOKE51bWJlcihoYXZhX2thbGl0ZXNpKSkpIHtcbiAgICBjb25zdCBoID0gTnVtYmVyKGhhdmFfa2FsaXRlc2kpO1xuICAgIG91dEhhdmFHYXVnZS5wdXNoKHsgcGF5bG9hZDogaCwgcHJvYmxlbV9pZCwgdGFraW1fbm8gfSk7XG59XG5cbmlmIChcbiAgICBvdXREczE4R2F1Z2UubGVuZ3RoID09PSAwICYmXG4gICAgb3V0RGh0VGVtcEdhdWdlLmxlbmd0aCA9PT0gMCAmJlxuICAgIG91dE5lbUdhdWdlLmxlbmd0aCA9PT0gMCAmJlxuICAgIG91dFRlbXBDaGFydC5sZW5ndGggPT09IDAgJiZcbiAgICBvdXROZW1DaGFydC5sZW5ndGggPT09IDAgJiZcbiAgICBvdXRIYXZhR2F1Z2UubGVuZ3RoID09PSAwXG4pIHtcbiAgICByZXR1cm4gbnVsbDtcbn1cblxucmV0dXJuIFtvdXREczE4R2F1Z2UsIG91dERodFRlbXBHYXVnZSwgb3V0TmVtR2F1Z2UsIG91dFRlbXBDaGFydCwgb3V0TmVtQ2hhcnQsIG91dEhhdmFHYXVnZV07XG4iLAogICAgICAgICJvdXRwdXRzIjogNiwKICAgICAgICAidGltZW91dCI6IDAsCiAgICAgICAgIm5vZXJyIjogMCwKICAgICAgICAiaW5pdGlhbGl6ZSI6ICIiLAogICAgICAgICJmaW5hbGl6ZSI6ICIiLAogICAgICAgICJsaWJzIjogW10sCiAgICAgICAgIngiOiA1NjAsCiAgICAgICAgInkiOiAxNjAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAic3dfZHMxOCIKICAgICAgICAgICAgXSwKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgInN3X2RodCIKICAgICAgICAgICAgXSwKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgInN3X25lbSIKICAgICAgICAgICAgXSwKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgInN3X3RlbXBfY2hhcnQiCiAgICAgICAgICAgIF0sCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJzd19uZW1fY2hhcnQiCiAgICAgICAgICAgIF0sCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJzd19oYXZhIgogICAgICAgICAgICBdCiAgICAgICAgXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAic3dfZHMxOCIsCiAgICAgICAgInR5cGUiOiAic3dpdGNoIiwKICAgICAgICAieiI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgIm5hbWUiOiAiRFMxOCDihpIgcHJvYmxlbSIsCiAgICAgICAgInByb3BlcnR5IjogInByb2JsZW1faWQiLAogICAgICAgICJwcm9wZXJ0eVR5cGUiOiAibXNnIiwKICAgICAgICAicnVsZXMiOiBbCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICJ0IjogImVxIiwKICAgICAgICAgICAgICAgICJ2IjogInRhcmltX3N1bGFtYSIsCiAgICAgICAgICAgICAgICAidnQiOiAic3RyIgogICAgICAgICAgICB9LAogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAidCI6ICJlcSIsCiAgICAgICAgICAgICAgICAidiI6ICJ0YXJpbV9oYXZhbGFuZGlybWEiLAogICAgICAgICAgICAgICAgInZ0IjogInN0ciIKICAgICAgICAgICAgfQogICAgICAgIF0sCiAgICAgICAgImNoZWNrYWxsIjogImZhbHNlIiwKICAgICAgICAicmVwYWlyIjogZmFsc2UsCiAgICAgICAgIm91dHB1dHMiOiAyLAogICAgICAgICJ4IjogNzYwLAogICAgICAgICJ5IjogNjAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAiZ2F1Z2VfZHMxOF9zdWwiCiAgICAgICAgICAgIF0sCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJnYXVnZV9kczE4X2hhdmEiCiAgICAgICAgICAgIF0KICAgICAgICBdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJzd19kaHQiLAogICAgICAgICJ0eXBlIjogInN3aXRjaCIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIkRIVCDihpIgcHJvYmxlbSIsCiAgICAgICAgInByb3BlcnR5IjogInByb2JsZW1faWQiLAogICAgICAgICJwcm9wZXJ0eVR5cGUiOiAibXNnIiwKICAgICAgICAicnVsZXMiOiBbCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICJ0IjogImVxIiwKICAgICAgICAgICAgICAgICJ2IjogInRhcmltX3N1bGFtYSIsCiAgICAgICAgICAgICAgICAidnQiOiAic3RyIgogICAgICAgICAgICB9LAogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAidCI6ICJlcSIsCiAgICAgICAgICAgICAgICAidiI6ICJ0YXJpbV9oYXZhbGFuZGlybWEiLAogICAgICAgICAgICAgICAgInZ0IjogInN0ciIKICAgICAgICAgICAgfQogICAgICAgIF0sCiAgICAgICAgImNoZWNrYWxsIjogImZhbHNlIiwKICAgICAgICAicmVwYWlyIjogZmFsc2UsCiAgICAgICAgIm91dHB1dHMiOiAyLAogICAgICAgICJ4IjogNzYwLAogICAgICAgICJ5IjogMTIwLAogICAgICAgICJ3aXJlcyI6IFsKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgImdhdWdlX2RodF9zdWwiCiAgICAgICAgICAgIF0sCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJnYXVnZV9kaHRfaGF2YSIKICAgICAgICAgICAgXQogICAgICAgIF0KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogInN3X25lbSIsCiAgICAgICAgInR5cGUiOiAic3dpdGNoIiwKICAgICAgICAieiI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgIm5hbWUiOiAiTmVtIOKGkiBwcm9ibGVtIiwKICAgICAgICAicHJvcGVydHkiOiAicHJvYmxlbV9pZCIsCiAgICAgICAgInByb3BlcnR5VHlwZSI6ICJtc2ciLAogICAgICAgICJydWxlcyI6IFsKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgInQiOiAiZXEiLAogICAgICAgICAgICAgICAgInYiOiAidGFyaW1fc3VsYW1hIiwKICAgICAgICAgICAgICAgICJ2dCI6ICJzdHIiCiAgICAgICAgICAgIH0sCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICJ0IjogImVxIiwKICAgICAgICAgICAgICAgICJ2IjogInRhcmltX2hhdmFsYW5kaXJtYSIsCiAgICAgICAgICAgICAgICAidnQiOiAic3RyIgogICAgICAgICAgICB9CiAgICAgICAgXSwKICAgICAgICAiY2hlY2thbGwiOiAiZmFsc2UiLAogICAgICAgICJyZXBhaXIiOiBmYWxzZSwKICAgICAgICAib3V0cHV0cyI6IDIsCiAgICAgICAgIngiOiA3NjAsCiAgICAgICAgInkiOiAxODAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAiZ2F1Z2VfbmVtX3N1bCIKICAgICAgICAgICAgXSwKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgImdhdWdlX25lbV9oYXZhIgogICAgICAgICAgICBdCiAgICAgICAgXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAic3dfdGVtcF9jaGFydCIsCiAgICAgICAgInR5cGUiOiAic3dpdGNoIiwKICAgICAgICAieiI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgIm5hbWUiOiAiU8SxY2FrbMSxayBjaGFydCDihpIgcHJvYmxlbSIsCiAgICAgICAgInByb3BlcnR5IjogInByb2JsZW1faWQiLAogICAgICAgICJwcm9wZXJ0eVR5cGUiOiAibXNnIiwKICAgICAgICAicnVsZXMiOiBbCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICJ0IjogImVxIiwKICAgICAgICAgICAgICAgICJ2IjogInRhcmltX3N1bGFtYSIsCiAgICAgICAgICAgICAgICAidnQiOiAic3RyIgogICAgICAgICAgICB9LAogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAidCI6ICJlcSIsCiAgICAgICAgICAgICAgICAidiI6ICJ0YXJpbV9oYXZhbGFuZGlybWEiLAogICAgICAgICAgICAgICAgInZ0IjogInN0ciIKICAgICAgICAgICAgfQogICAgICAgIF0sCiAgICAgICAgImNoZWNrYWxsIjogImZhbHNlIiwKICAgICAgICAicmVwYWlyIjogZmFsc2UsCiAgICAgICAgIm91dHB1dHMiOiAyLAogICAgICAgICJ4IjogNzYwLAogICAgICAgICJ5IjogMjQwLAogICAgICAgICJ3aXJlcyI6IFsKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgImNoYXJ0X3RlbXBfc3VsIgogICAgICAgICAgICBdLAogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAiY2hhcnRfdGVtcF9oYXZhIgogICAgICAgICAgICBdCiAgICAgICAgXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAic3dfbmVtX2NoYXJ0IiwKICAgICAgICAidHlwZSI6ICJzd2l0Y2giLAogICAgICAgICJ6IjogImh1Yl90YWJfdGVsZW1ldHJ5IiwKICAgICAgICAibmFtZSI6ICJOZW0gY2hhcnQg4oaSIHByb2JsZW0iLAogICAgICAgICJwcm9wZXJ0eSI6ICJwcm9ibGVtX2lkIiwKICAgICAgICAicHJvcGVydHlUeXBlIjogIm1zZyIsCiAgICAgICAgInJ1bGVzIjogWwogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAidCI6ICJlcSIsCiAgICAgICAgICAgICAgICAidiI6ICJ0YXJpbV9zdWxhbWEiLAogICAgICAgICAgICAgICAgInZ0IjogInN0ciIKICAgICAgICAgICAgfSwKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgInQiOiAiZXEiLAogICAgICAgICAgICAgICAgInYiOiAidGFyaW1faGF2YWxhbmRpcm1hIiwKICAgICAgICAgICAgICAgICJ2dCI6ICJzdHIiCiAgICAgICAgICAgIH0KICAgICAgICBdLAogICAgICAgICJjaGVja2FsbCI6ICJmYWxzZSIsCiAgICAgICAgInJlcGFpciI6IGZhbHNlLAogICAgICAgICJvdXRwdXRzIjogMiwKICAgICAgICAieCI6IDc2MCwKICAgICAgICAieSI6IDMwMCwKICAgICAgICAid2lyZXMiOiBbCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJjaGFydF9uZW1fc3VsIgogICAgICAgICAgICBdLAogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAiY2hhcnRfbmVtX2hhdmEiCiAgICAgICAgICAgIF0KICAgICAgICBdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJzd19oYXZhIiwKICAgICAgICAidHlwZSI6ICJzd2l0Y2giLAogICAgICAgICJ6IjogImh1Yl90YWJfdGVsZW1ldHJ5IiwKICAgICAgICAibmFtZSI6ICJIYXZhIOKGkiBwcm9ibGVtIiwKICAgICAgICAicHJvcGVydHkiOiAicHJvYmxlbV9pZCIsCiAgICAgICAgInByb3BlcnR5VHlwZSI6ICJtc2ciLAogICAgICAgICJydWxlcyI6IFsKICAgICAgICAgICAgewogICAgICAgICAgICAgICAgInQiOiAiZXEiLAogICAgICAgICAgICAgICAgInYiOiAidGFyaW1fc3VsYW1hIiwKICAgICAgICAgICAgICAgICJ2dCI6ICJzdHIiCiAgICAgICAgICAgIH0sCiAgICAgICAgICAgIHsKICAgICAgICAgICAgICAgICJ0IjogImVxIiwKICAgICAgICAgICAgICAgICJ2IjogInRhcmltX2hhdmFsYW5kaXJtYSIsCiAgICAgICAgICAgICAgICAidnQiOiAic3RyIgogICAgICAgICAgICB9CiAgICAgICAgXSwKICAgICAgICAiY2hlY2thbGwiOiAiZmFsc2UiLAogICAgICAgICJyZXBhaXIiOiBmYWxzZSwKICAgICAgICAib3V0cHV0cyI6IDIsCiAgICAgICAgIngiOiA3NjAsCiAgICAgICAgInkiOiAzNjAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbXSwKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgImdhdWdlX2hhdmFfaGF2YSIKICAgICAgICAgICAgXQogICAgICAgIF0KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImdhdWdlX2RzMThfc3VsIiwKICAgICAgICAidHlwZSI6ICJ1aV9nYXVnZSIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIkRTMTggU3VsYW1hIiwKICAgICAgICAiZ3JvdXAiOiAiZ3JvdXBfc3VsYW1hIiwKICAgICAgICAib3JkZXIiOiAxLAogICAgICAgICJ3aWR0aCI6IDQsCiAgICAgICAgImhlaWdodCI6IDQsCiAgICAgICAgImd0eXBlIjogImdhZ2UiLAogICAgICAgICJ0aXRsZSI6ICJEUzE4QjIwICjCsEMpIiwKICAgICAgICAibGFiZWwiOiAiwrBDIiwKICAgICAgICAiZm9ybWF0IjogInt7dmFsdWV9fSIsCiAgICAgICAgIm1pbiI6IDAsCiAgICAgICAgIm1heCI6IDUwLAogICAgICAgICJjb2xvcnMiOiBbCiAgICAgICAgICAgICIjMDBiNTAwIiwKICAgICAgICAgICAgIiNlNmU2MDAiLAogICAgICAgICAgICAiI2NhMzgzOCIKICAgICAgICBdLAogICAgICAgICJzZWcxIjogMjUsCiAgICAgICAgInNlZzIiOiAzNSwKICAgICAgICAieCI6IDk4MCwKICAgICAgICAieSI6IDQwLAogICAgICAgICJ3aXJlcyI6IFtdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJnYXVnZV9kaHRfc3VsIiwKICAgICAgICAidHlwZSI6ICJ1aV9nYXVnZSIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIkRIVCBTdWxhbWEiLAogICAgICAgICJncm91cCI6ICJncm91cF9zdWxhbWEiLAogICAgICAgICJvcmRlciI6IDIsCiAgICAgICAgIndpZHRoIjogNCwKICAgICAgICAiaGVpZ2h0IjogNCwKICAgICAgICAiZ3R5cGUiOiAiZ2FnZSIsCiAgICAgICAgInRpdGxlIjogIkRIVDExIFPEsWNha2zEsWsgKMKwQykiLAogICAgICAgICJsYWJlbCI6ICLCsEMiLAogICAgICAgICJmb3JtYXQiOiAie3t2YWx1ZX19IiwKICAgICAgICAibWluIjogMCwKICAgICAgICAibWF4IjogNTAsCiAgICAgICAgImNvbG9ycyI6IFsKICAgICAgICAgICAgIiMwMGI1MDAiLAogICAgICAgICAgICAiI2U2ZTYwMCIsCiAgICAgICAgICAgICIjY2EzODM4IgogICAgICAgIF0sCiAgICAgICAgInNlZzEiOiAyNSwKICAgICAgICAic2VnMiI6IDM1LAogICAgICAgICJ4IjogOTgwLAogICAgICAgICJ5IjogMTAwLAogICAgICAgICJ3aXJlcyI6IFtdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJnYXVnZV9uZW1fc3VsIiwKICAgICAgICAidHlwZSI6ICJ1aV9nYXVnZSIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIk5lbSBTdWxhbWEiLAogICAgICAgICJncm91cCI6ICJncm91cF9zdWxhbWEiLAogICAgICAgICJvcmRlciI6IDMsCiAgICAgICAgIndpZHRoIjogNCwKICAgICAgICAiaGVpZ2h0IjogNCwKICAgICAgICAiZ3R5cGUiOiAiZ2FnZSIsCiAgICAgICAgInRpdGxlIjogIk5lbSAoJSkiLAogICAgICAgICJsYWJlbCI6ICIlIiwKICAgICAgICAiZm9ybWF0IjogInt7dmFsdWV9fSIsCiAgICAgICAgIm1pbiI6IDAsCiAgICAgICAgIm1heCI6IDEwMCwKICAgICAgICAiY29sb3JzIjogWwogICAgICAgICAgICAiI2NhMzgzOCIsCiAgICAgICAgICAgICIjZTZlNjAwIiwKICAgICAgICAgICAgIiMwMGI1MDAiCiAgICAgICAgXSwKICAgICAgICAic2VnMSI6IDMwLAogICAgICAgICJzZWcyIjogNjAsCiAgICAgICAgIngiOiA5ODAsCiAgICAgICAgInkiOiAxNjAsCiAgICAgICAgIndpcmVzIjogW10KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImNoYXJ0X3RlbXBfc3VsIiwKICAgICAgICAidHlwZSI6ICJ1aV9jaGFydCIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIlPEsWNha2zEsWsgU3VsYW1hIiwKICAgICAgICAiZ3JvdXAiOiAiZ3JvdXBfc3VsYW1hIiwKICAgICAgICAib3JkZXIiOiA0LAogICAgICAgICJ3aWR0aCI6IDEyLAogICAgICAgICJoZWlnaHQiOiA2LAogICAgICAgICJsYWJlbCI6ICJTxLFjYWtsxLFrIChkczE4YjIwLCBkaHQxMSkiLAogICAgICAgICJjaGFydFR5cGUiOiAibGluZSIsCiAgICAgICAgImxlZ2VuZCI6ICJ0cnVlIiwKICAgICAgICAieGZvcm1hdCI6ICJISDptbTpzcyIsCiAgICAgICAgImludGVycG9sYXRlIjogImxpbmVhciIsCiAgICAgICAgIm5vZGF0YSI6ICJWZXJpIGJla2xlbml5b3IiLAogICAgICAgICJyZW1vdmVPbGRlciI6IDEsCiAgICAgICAgInJlbW92ZU9sZGVyVW5pdCI6ICIzNjAwIiwKICAgICAgICAib3V0cHV0cyI6IDEsCiAgICAgICAgIngiOiA5ODAsCiAgICAgICAgInkiOiAyMjAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbXQogICAgICAgIF0KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImNoYXJ0X25lbV9zdWwiLAogICAgICAgICJ0eXBlIjogInVpX2NoYXJ0IiwKICAgICAgICAieiI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgIm5hbWUiOiAiTmVtIFN1bGFtYSIsCiAgICAgICAgImdyb3VwIjogImdyb3VwX3N1bGFtYSIsCiAgICAgICAgIm9yZGVyIjogNSwKICAgICAgICAid2lkdGgiOiAxMiwKICAgICAgICAiaGVpZ2h0IjogNiwKICAgICAgICAibGFiZWwiOiAiTmVtIChkaHQxMV9uZW0pIiwKICAgICAgICAiY2hhcnRUeXBlIjogImxpbmUiLAogICAgICAgICJsZWdlbmQiOiAidHJ1ZSIsCiAgICAgICAgInhmb3JtYXQiOiAiSEg6bW06c3MiLAogICAgICAgICJpbnRlcnBvbGF0ZSI6ICJsaW5lYXIiLAogICAgICAgICJub2RhdGEiOiAiVmVyaSBiZWtsZW5peW9yIiwKICAgICAgICAicmVtb3ZlT2xkZXIiOiAxLAogICAgICAgICJyZW1vdmVPbGRlclVuaXQiOiAiMzYwMCIsCiAgICAgICAgIm91dHB1dHMiOiAxLAogICAgICAgICJ4IjogOTgwLAogICAgICAgICJ5IjogMzAwLAogICAgICAgICJ3aXJlcyI6IFsKICAgICAgICAgICAgW10KICAgICAgICBdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJnYXVnZV9kczE4X2hhdmEiLAogICAgICAgICJ0eXBlIjogInVpX2dhdWdlIiwKICAgICAgICAieiI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgIm5hbWUiOiAiRFMxOCBIYXZhIiwKICAgICAgICAiZ3JvdXAiOiAiZ3JvdXBfaGF2YSIsCiAgICAgICAgIm9yZGVyIjogMSwKICAgICAgICAid2lkdGgiOiA0LAogICAgICAgICJoZWlnaHQiOiA0LAogICAgICAgICJndHlwZSI6ICJnYWdlIiwKICAgICAgICAidGl0bGUiOiAiRFMxOEIyMCAowrBDKSIsCiAgICAgICAgImxhYmVsIjogIsKwQyIsCiAgICAgICAgImZvcm1hdCI6ICJ7e3ZhbHVlfX0iLAogICAgICAgICJtaW4iOiAwLAogICAgICAgICJtYXgiOiA1MCwKICAgICAgICAiY29sb3JzIjogWwogICAgICAgICAgICAiIzAwYjUwMCIsCiAgICAgICAgICAgICIjZTZlNjAwIiwKICAgICAgICAgICAgIiNjYTM4MzgiCiAgICAgICAgXSwKICAgICAgICAic2VnMSI6IDI1LAogICAgICAgICJzZWcyIjogMzUsCiAgICAgICAgIngiOiA5ODAsCiAgICAgICAgInkiOiA0MDAsCiAgICAgICAgIndpcmVzIjogW10KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImdhdWdlX2RodF9oYXZhIiwKICAgICAgICAidHlwZSI6ICJ1aV9nYXVnZSIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIkRIVCBIYXZhIiwKICAgICAgICAiZ3JvdXAiOiAiZ3JvdXBfaGF2YSIsCiAgICAgICAgIm9yZGVyIjogMiwKICAgICAgICAid2lkdGgiOiA0LAogICAgICAgICJoZWlnaHQiOiA0LAogICAgICAgICJndHlwZSI6ICJnYWdlIiwKICAgICAgICAidGl0bGUiOiAiREhUMTEgU8SxY2FrbMSxayAowrBDKSIsCiAgICAgICAgImxhYmVsIjogIsKwQyIsCiAgICAgICAgImZvcm1hdCI6ICJ7e3ZhbHVlfX0iLAogICAgICAgICJtaW4iOiAwLAogICAgICAgICJtYXgiOiA1MCwKICAgICAgICAiY29sb3JzIjogWwogICAgICAgICAgICAiIzAwYjUwMCIsCiAgICAgICAgICAgICIjZTZlNjAwIiwKICAgICAgICAgICAgIiNjYTM4MzgiCiAgICAgICAgXSwKICAgICAgICAic2VnMSI6IDI1LAogICAgICAgICJzZWcyIjogMzUsCiAgICAgICAgIngiOiA5ODAsCiAgICAgICAgInkiOiA0NjAsCiAgICAgICAgIndpcmVzIjogW10KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImdhdWdlX25lbV9oYXZhIiwKICAgICAgICAidHlwZSI6ICJ1aV9nYXVnZSIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIk5lbSBIYXZhIiwKICAgICAgICAiZ3JvdXAiOiAiZ3JvdXBfaGF2YSIsCiAgICAgICAgIm9yZGVyIjogMywKICAgICAgICAid2lkdGgiOiA0LAogICAgICAgICJoZWlnaHQiOiA0LAogICAgICAgICJndHlwZSI6ICJnYWdlIiwKICAgICAgICAidGl0bGUiOiAiTmVtICglKSIsCiAgICAgICAgImxhYmVsIjogIiUiLAogICAgICAgICJmb3JtYXQiOiAie3t2YWx1ZX19IiwKICAgICAgICAibWluIjogMCwKICAgICAgICAibWF4IjogMTAwLAogICAgICAgICJjb2xvcnMiOiBbCiAgICAgICAgICAgICIjY2EzODM4IiwKICAgICAgICAgICAgIiNlNmU2MDAiLAogICAgICAgICAgICAiIzAwYjUwMCIKICAgICAgICBdLAogICAgICAgICJzZWcxIjogMzAsCiAgICAgICAgInNlZzIiOiA2MCwKICAgICAgICAieCI6IDk4MCwKICAgICAgICAieSI6IDUyMCwKICAgICAgICAid2lyZXMiOiBbXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiZ2F1Z2VfaGF2YV9oYXZhIiwKICAgICAgICAidHlwZSI6ICJ1aV9nYXVnZSIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIkhhdmEgS2FsaXRlc2kiLAogICAgICAgICJncm91cCI6ICJncm91cF9oYXZhIiwKICAgICAgICAib3JkZXIiOiA0LAogICAgICAgICJ3aWR0aCI6IDQsCiAgICAgICAgImhlaWdodCI6IDQsCiAgICAgICAgImd0eXBlIjogImdhZ2UiLAogICAgICAgICJ0aXRsZSI6ICJIYXZhIEthbGl0ZXNpIiwKICAgICAgICAibGFiZWwiOiAiQVFJIiwKICAgICAgICAiZm9ybWF0IjogInt7dmFsdWV9fSIsCiAgICAgICAgIm1pbiI6IDAsCiAgICAgICAgIm1heCI6IDYwMCwKICAgICAgICAiY29sb3JzIjogWwogICAgICAgICAgICAiIzAwYjUwMCIsCiAgICAgICAgICAgICIjZTZlNjAwIiwKICAgICAgICAgICAgIiNjYTM4MzgiCiAgICAgICAgXSwKICAgICAgICAic2VnMSI6IDIwMCwKICAgICAgICAic2VnMiI6IDQwMCwKICAgICAgICAieCI6IDk4MCwKICAgICAgICAieSI6IDU4MCwKICAgICAgICAid2lyZXMiOiBbXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiY2hhcnRfdGVtcF9oYXZhIiwKICAgICAgICAidHlwZSI6ICJ1aV9jaGFydCIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIlPEsWNha2zEsWsgSGF2YSIsCiAgICAgICAgImdyb3VwIjogImdyb3VwX2hhdmEiLAogICAgICAgICJvcmRlciI6IDUsCiAgICAgICAgIndpZHRoIjogMTIsCiAgICAgICAgImhlaWdodCI6IDYsCiAgICAgICAgImxhYmVsIjogIlPEsWNha2zEsWsgKGRzMThiMjAsIGRodDExKSIsCiAgICAgICAgImNoYXJ0VHlwZSI6ICJsaW5lIiwKICAgICAgICAibGVnZW5kIjogInRydWUiLAogICAgICAgICJ4Zm9ybWF0IjogIkhIOm1tOnNzIiwKICAgICAgICAiaW50ZXJwb2xhdGUiOiAibGluZWFyIiwKICAgICAgICAibm9kYXRhIjogIlZlcmkgYmVrbGVuaXlvciIsCiAgICAgICAgInJlbW92ZU9sZGVyIjogMSwKICAgICAgICAicmVtb3ZlT2xkZXJVbml0IjogIjM2MDAiLAogICAgICAgICJvdXRwdXRzIjogMSwKICAgICAgICAieCI6IDk4MCwKICAgICAgICAieSI6IDY0MCwKICAgICAgICAid2lyZXMiOiBbCiAgICAgICAgICAgIFtdCiAgICAgICAgXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiY2hhcnRfbmVtX2hhdmEiLAogICAgICAgICJ0eXBlIjogInVpX2NoYXJ0IiwKICAgICAgICAieiI6ICJodWJfdGFiX3RlbGVtZXRyeSIsCiAgICAgICAgIm5hbWUiOiAiTmVtIEhhdmEiLAogICAgICAgICJncm91cCI6ICJncm91cF9oYXZhIiwKICAgICAgICAib3JkZXIiOiA2LAogICAgICAgICJ3aWR0aCI6IDEyLAogICAgICAgICJoZWlnaHQiOiA2LAogICAgICAgICJsYWJlbCI6ICJOZW0gKGRodDExX25lbSkiLAogICAgICAgICJjaGFydFR5cGUiOiAibGluZSIsCiAgICAgICAgImxlZ2VuZCI6ICJ0cnVlIiwKICAgICAgICAieGZvcm1hdCI6ICJISDptbTpzcyIsCiAgICAgICAgImludGVycG9sYXRlIjogImxpbmVhciIsCiAgICAgICAgIm5vZGF0YSI6ICJWZXJpIGJla2xlbml5b3IiLAogICAgICAgICJyZW1vdmVPbGRlciI6IDEsCiAgICAgICAgInJlbW92ZU9sZGVyVW5pdCI6ICIzNjAwIiwKICAgICAgICAib3V0cHV0cyI6IDEsCiAgICAgICAgIngiOiA5ODAsCiAgICAgICAgInkiOiA3MjAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbXQogICAgICAgIF0KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImZ1bmNfdGhyZXNob2xkIiwKICAgICAgICAidHlwZSI6ICJmdW5jdGlvbiIsCiAgICAgICAgInoiOiAiaHViX3RhYl90ZWxlbWV0cnkiLAogICAgICAgICJuYW1lIjogIkXFn2lrIOKGkiBZWiBUZXRpayIsCiAgICAgICAgImZ1bmMiOiAiY29uc3QgcCA9IG1zZy5wYXlsb2FkO1xuaWYgKCFwIHx8IHR5cGVvZiBwICE9PSBcIm9iamVjdFwiKSB7XG4gICAgcmV0dXJuIG51bGw7XG59XG5cbmNvbnN0IHRvcGljUGFydHMgPSBTdHJpbmcobXNnLnRvcGljIHx8IFwiXCIpLnNwbGl0KFwiL1wiKTtcbmNvbnN0IHByb2JsZW1faWQgPSB0b3BpY1BhcnRzWzBdIHx8IHAucHJvYmxlbV9pZDtcbmNvbnN0IHRha2ltX25vID0gdG9waWNQYXJ0c1sxXSB8fCBwLnRha2ltX25vO1xuXG5pZiAoIXByb2JsZW1faWQgfHwgIXRha2ltX25vKSB7XG4gICAgcmV0dXJuIG51bGw7XG59XG5cbmxldCBuZW0gPSBwLm5lbTtcbmxldCBoYXZhX2thbGl0ZXNpID0gcC5oYXZhX2thbGl0ZXNpO1xuXG5pZiAocC52YWx1ZXMgJiYgdHlwZW9mIHAudmFsdWVzID09PSBcIm9iamVjdFwiKSB7XG4gICAgaWYgKG5lbSA9PT0gdW5kZWZpbmVkKSBuZW0gPSBwLnZhbHVlcy5uZW07XG4gICAgaWYgKGhhdmFfa2FsaXRlc2kgPT09IHVuZGVmaW5lZCkgaGF2YV9rYWxpdGVzaSA9IHAudmFsdWVzLmhhdmFfa2FsaXRlc2k7XG59XG5cbmxldCB0cmlnZ2VyID0gZmFsc2U7XG5sZXQgdHJpZ2dlcl9yZWFzb24gPSBcIlwiO1xuXG5pZiAobmVtICE9PSB1bmRlZmluZWQgJiYgbmVtICE9PSBudWxsICYmIE51bWJlcihuZW0pID4gNzApIHtcbiAgICB0cmlnZ2VyID0gdHJ1ZTtcbiAgICB0cmlnZ2VyX3JlYXNvbiA9IGBuZW0+JHs3MH0gKCR7TnVtYmVyKG5lbSl9KWA7XG59XG5cbmlmIChoYXZhX2thbGl0ZXNpICE9PSB1bmRlZmluZWQgJiYgaGF2YV9rYWxpdGVzaSAhPT0gbnVsbCAmJiBOdW1iZXIoaGF2YV9rYWxpdGVzaSkgPiA0MDApIHtcbiAgICB0cmlnZ2VyID0gdHJ1ZTtcbiAgICB0cmlnZ2VyX3JlYXNvbiA9IHRyaWdnZXJfcmVhc29uXG4gICAgICAgID8gYCR7dHJpZ2dlcl9yZWFzb259OyBoYXZhX2thbGl0ZXNpPjQwMCAoJHtOdW1iZXIoaGF2YV9rYWxpdGVzaSl9KWBcbiAgICAgICAgOiBgaGF2YV9rYWxpdGVzaT40MDAgKCR7TnVtYmVyKGhhdmFfa2FsaXRlc2kpfSlgO1xufVxuXG5pZiAoIXRyaWdnZXIpIHtcbiAgICByZXR1cm4gbnVsbDtcbn1cblxubXNnLnBheWxvYWQgPSB7XG4gICAgcHJvYmxlbV9pZCxcbiAgICB0YWtpbV9ubyxcbiAgICBtaW51dGVzOiAxNSxcbiAgICB0cmlnZ2VyX3JlYXNvblxufTtcbm1zZy5wcm9ibGVtX2lkID0gcHJvYmxlbV9pZDtcbm1zZy50YWtpbV9ubyA9IHRha2ltX25vO1xubXNnLnVybCA9IFwiaHR0cDovLzEyNy4wLjAuMTo1MDAwL2FuYWx5emVcIjtcbm1zZy5tZXRob2QgPSBcIlBPU1RcIjtcbm1zZy5oZWFkZXJzID0geyBcImNvbnRlbnQtdHlwZVwiOiBcImFwcGxpY2F0aW9uL2pzb25cIiB9O1xucmV0dXJuIG1zZzsiLAogICAgICAgICJvdXRwdXRzIjogMSwKICAgICAgICAidGltZW91dCI6IDAsCiAgICAgICAgIm5vZXJyIjogMCwKICAgICAgICAiaW5pdGlhbGl6ZSI6ICIiLAogICAgICAgICJmaW5hbGl6ZSI6ICIiLAogICAgICAgICJsaWJzIjogW10sCiAgICAgICAgIngiOiA1NjAsCiAgICAgICAgInkiOiA1MjAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAiaHR0cF9hbmFseXplIgogICAgICAgICAgICBdCiAgICAgICAgXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiaW5qZWN0X2FuYWx5emVfNjBzIiwKICAgICAgICAidHlwZSI6ICJpbmplY3QiLAogICAgICAgICJ6IjogImh1Yl90YWJfeXoiLAogICAgICAgICJuYW1lIjogIkhlciA2MCBzbiIsCiAgICAgICAgInByb3BzIjogWwogICAgICAgICAgICB7CiAgICAgICAgICAgICAgICAicCI6ICJwYXlsb2FkIgogICAgICAgICAgICB9CiAgICAgICAgXSwKICAgICAgICAicmVwZWF0IjogIjYwIiwKICAgICAgICAiY3JvbnRhYiI6ICIiLAogICAgICAgICJvbmNlIjogZmFsc2UsCiAgICAgICAgIm9uY2VEZWxheSI6IDAuMSwKICAgICAgICAidG9waWMiOiAiIiwKICAgICAgICAicGF5bG9hZCI6ICIiLAogICAgICAgICJwYXlsb2FkVHlwZSI6ICJkYXRlIiwKICAgICAgICAieCI6IDE1MCwKICAgICAgICAieSI6IDEyMCwKICAgICAgICAid2lyZXMiOiBbCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJmdW5jX2FuYWx5emVfdHJpZ2dlciIKICAgICAgICAgICAgXQogICAgICAgIF0KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImZ1bmNfYW5hbHl6ZV90cmlnZ2VyIiwKICAgICAgICAidHlwZSI6ICJmdW5jdGlvbiIsCiAgICAgICAgInoiOiAiaHViX3RhYl95eiIsCiAgICAgICAgIm5hbWUiOiAiWVogxLBzdGVrIE9sdcWfdHVyIiwKICAgICAgICAiZnVuYyI6ICIvLyBQZXJpeW9kaWsgWVogYW5hbGl6IHRldGlrbGV5aWNpIOKAlCAyIMOnxLFrxLHFnzpcbi8vIDEg4oaSIHRhcmltX3N1bGFtYSAvIHRha2ltIDdcbi8vIDIg4oaSIHRhcmltX2hhdmFsYW5kaXJtYSAvIHRha2ltIDhcblxuY29uc3QgdGFyZ2V0cyA9IFtcbiAgICB7IHByb2JsZW1faWQ6IFwidGFyaW1fc3VsYW1hXCIsIHRha2ltX25vOiBcIjdcIiB9LFxuICAgIHsgcHJvYmxlbV9pZDogXCJ0YXJpbV9oYXZhbGFuZGlybWFcIiwgdGFraW1fbm86IFwiOFwiIH1cbl07XG5cbmZ1bmN0aW9uIGJ1aWxkUmVxdWVzdChwcm9ibGVtX2lkLCB0YWtpbV9ubykge1xuICAgIHJldHVybiB7XG4gICAgICAgIHBheWxvYWQ6IHtcbiAgICAgICAgICAgIHByb2JsZW1faWQsXG4gICAgICAgICAgICB0YWtpbV9ubyxcbiAgICAgICAgICAgIG1pbnV0ZXM6IDE1XG4gICAgICAgIH0sXG4gICAgICAgIHByb2JsZW1faWQsXG4gICAgICAgIHRha2ltX25vLFxuICAgICAgICB1cmw6IFwiaHR0cDovLzEyNy4wLjAuMTo1MDAwL2FuYWx5emVcIixcbiAgICAgICAgbWV0aG9kOiBcIlBPU1RcIixcbiAgICAgICAgaGVhZGVyczoge1xuICAgICAgICAgICAgXCJjb250ZW50LXR5cGVcIjogXCJhcHBsaWNhdGlvbi9qc29uXCJcbiAgICAgICAgfVxuICAgIH07XG59XG5cbnJldHVybiB0YXJnZXRzLm1hcCgodCkgPT4gYnVpbGRSZXF1ZXN0KHQucHJvYmxlbV9pZCwgdC50YWtpbV9ubykpO1xuIiwKICAgICAgICAib3V0cHV0cyI6IDIsCiAgICAgICAgInRpbWVvdXQiOiAwLAogICAgICAgICJub2VyciI6IDAsCiAgICAgICAgImluaXRpYWxpemUiOiAiIiwKICAgICAgICAiZmluYWxpemUiOiAiIiwKICAgICAgICAibGlicyI6IFtdLAogICAgICAgICJ4IjogMzYwLAogICAgICAgICJ5IjogMTIwLAogICAgICAgICJ3aXJlcyI6IFsKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgImh0dHBfYW5hbHl6ZSIKICAgICAgICAgICAgXSwKICAgICAgICAgICAgWwogICAgICAgICAgICAgICAgImh0dHBfYW5hbHl6ZSIKICAgICAgICAgICAgXQogICAgICAgIF0KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogImh0dHBfYW5hbHl6ZSIsCiAgICAgICAgInR5cGUiOiAiaHR0cCByZXF1ZXN0IiwKICAgICAgICAieiI6ICJodWJfdGFiX3l6IiwKICAgICAgICAibmFtZSI6ICJQT1NUIC9hbmFseXplIiwKICAgICAgICAibWV0aG9kIjogInVzZSIsCiAgICAgICAgInJldCI6ICJvYmoiLAogICAgICAgICJwYXl0b3FzIjogImlnbm9yZSIsCiAgICAgICAgInVybCI6ICIiLAogICAgICAgICJ0bHMiOiAiIiwKICAgICAgICAicGVyc2lzdCI6IGZhbHNlLAogICAgICAgICJwcm94eSI6ICIiLAogICAgICAgICJpbnNlY3VyZUhUVFBQYXJzZXIiOiBmYWxzZSwKICAgICAgICAiYXV0aFR5cGUiOiAiIiwKICAgICAgICAic2VuZGVyciI6IGZhbHNlLAogICAgICAgICJoZWFkZXJzIjogW10sCiAgICAgICAgIngiOiA1ODAsCiAgICAgICAgInkiOiAyMDAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAiZnVuY19jb21tYW5kX2Zyb21fYXBpIiwKICAgICAgICAgICAgICAgICJkZWJ1Z19hbmFseXplIgogICAgICAgICAgICBdCiAgICAgICAgXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiZGVidWdfYW5hbHl6ZSIsCiAgICAgICAgInR5cGUiOiAiZGVidWciLAogICAgICAgICJ6IjogImh1Yl90YWJfeXoiLAogICAgICAgICJuYW1lIjogIkFuYWx5emUgWWFuxLF0IiwKICAgICAgICAiYWN0aXZlIjogdHJ1ZSwKICAgICAgICAidG9zaWRlYmFyIjogdHJ1ZSwKICAgICAgICAiY29tcGxldGUiOiAicGF5bG9hZCIsCiAgICAgICAgInRhcmdldFR5cGUiOiAibXNnIiwKICAgICAgICAieCI6IDc4MCwKICAgICAgICAieSI6IDI4MCwKICAgICAgICAid2lyZXMiOiBbXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiZnVuY19jb21tYW5kX2Zyb21fYXBpIiwKICAgICAgICAidHlwZSI6ICJmdW5jdGlvbiIsCiAgICAgICAgInoiOiAiaHViX3RhYl95eiIsCiAgICAgICAgIm5hbWUiOiAiQ29tbWFuZCBPbHXFn3R1ciIsCiAgICAgICAgImZ1bmMiOiAiLy8gRmFzdEFQSSAvYW5hbHl6ZSB5YW7EsXTEsW7EsSBNUVRUIGNvbW1hbmQgbWVzYWrEsW5hIGTDtm7DvMWfdMO8csO8ci5cbi8vIHRvcGljOiB7cHJvYmxlbV9pZH0ve3Rha2ltX25vfS9jb21tYW5kXG5cbmNvbnN0IHJlcyA9IG1zZy5wYXlsb2FkO1xuaWYgKCFyZXMgfHwgdHlwZW9mIHJlcyAhPT0gXCJvYmplY3RcIikge1xuICAgIHJldHVybiBudWxsO1xufVxuXG5jb25zdCBwcm9ibGVtX2lkID0gcmVzLnByb2JsZW1faWQgfHwgbXNnLnByb2JsZW1faWQ7XG5jb25zdCB0YWtpbV9ubyA9IHJlcy50YWtpbV9ubyB8fCBtc2cudGFraW1fbm87XG5jb25zdCBha3NpeW9uID0gcmVzLmFrc2l5b247XG5cbmlmICghcHJvYmxlbV9pZCB8fCAhdGFraW1fbm8pIHtcbiAgICBub2RlLndhcm4oXCJjb21tYW5kOiBwcm9ibGVtX2lkIHZleWEgdGFraW1fbm8gZWtzaWtcIik7XG4gICAgcmV0dXJuIG51bGw7XG59XG5cbmlmICghYWtzaXlvbiB8fCBha3NpeW9uID09PSBcImJla2xlXCIpIHtcbiAgICByZXR1cm4gbnVsbDtcbn1cblxubXNnLnRvcGljID0gYCR7cHJvYmxlbV9pZH0vJHt0YWtpbV9ub30vY29tbWFuZGA7XG5tc2cucGF5bG9hZCA9IHtcbiAgICBha3NpeW9uLFxuICAgIHN1cmVfc246IE51bWJlcihyZXMuc3VyZV9zbikgfHwgMCxcbiAgICBnZXJla2NlOiByZXMuZ2VyZWtjZSB8fCBcIlwiLFxuICAgIHNvdXJjZTogcmVzLnNvdXJjZSB8fCBcImFwaVwiLFxuICAgIHRpbWVzdGFtcDogbmV3IERhdGUoKS50b0lTT1N0cmluZygpXG59O1xucmV0dXJuIG1zZztcbiIsCiAgICAgICAgIm91dHB1dHMiOiAxLAogICAgICAgICJ0aW1lb3V0IjogMCwKICAgICAgICAibm9lcnIiOiAwLAogICAgICAgICJpbml0aWFsaXplIjogIiIsCiAgICAgICAgImZpbmFsaXplIjogIiIsCiAgICAgICAgImxpYnMiOiBbXSwKICAgICAgICAieCI6IDc4MCwKICAgICAgICAieSI6IDIwMCwKICAgICAgICAid2lyZXMiOiBbCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJtcXR0X2NvbW1hbmRfb3V0IiwKICAgICAgICAgICAgICAgICJkZWJ1Z19jb21tYW5kX2J1aWxkIgogICAgICAgICAgICBdCiAgICAgICAgXQogICAgfSwKICAgIHsKICAgICAgICAiaWQiOiAiZGVidWdfY29tbWFuZF9idWlsZCIsCiAgICAgICAgInR5cGUiOiAiZGVidWciLAogICAgICAgICJ6IjogImh1Yl90YWJfeXoiLAogICAgICAgICJuYW1lIjogIkNvbW1hbmQgRGVidWciLAogICAgICAgICJhY3RpdmUiOiB0cnVlLAogICAgICAgICJ0b3NpZGViYXIiOiB0cnVlLAogICAgICAgICJjb21wbGV0ZSI6ICJ0cnVlIiwKICAgICAgICAidGFyZ2V0VHlwZSI6ICJmdWxsIiwKICAgICAgICAieCI6IDEwMDAsCiAgICAgICAgInkiOiAyODAsCiAgICAgICAgIndpcmVzIjogW10KICAgIH0sCiAgICB7CiAgICAgICAgImlkIjogIm1xdHRfY29tbWFuZF9vdXQiLAogICAgICAgICJ0eXBlIjogIm1xdHQgb3V0IiwKICAgICAgICAieiI6ICJodWJfdGFiX3l6IiwKICAgICAgICAibmFtZSI6ICJNUVRUIENvbW1hbmQiLAogICAgICAgICJ0b3BpYyI6ICIiLAogICAgICAgICJxb3MiOiAiMSIsCiAgICAgICAgInJldGFpbiI6ICJmYWxzZSIsCiAgICAgICAgInJlc3BUb3BpYyI6ICIiLAogICAgICAgICJjb250ZW50VHlwZSI6ICIiLAogICAgICAgICJ1c2VyUHJvcHMiOiAiIiwKICAgICAgICAiY29ycmVsIjogIiIsCiAgICAgICAgImV4cGlyeSI6ICIiLAogICAgICAgICJicm9rZXIiOiAiYnJva2VyMSIsCiAgICAgICAgIngiOiAxMDAwLAogICAgICAgICJ5IjogMjAwLAogICAgICAgICJ3aXJlcyI6IFtdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJtcXR0X2NvbW1hbmRfaW4iLAogICAgICAgICJ0eXBlIjogIm1xdHQgaW4iLAogICAgICAgICJ6IjogImh1Yl90YWJfY29tbWFuZCIsCiAgICAgICAgIm5hbWUiOiAiVMO8bSBDb21tYW5kIiwKICAgICAgICAidG9waWMiOiAiKy8rL2NvbW1hbmQiLAogICAgICAgICJxb3MiOiAiMSIsCiAgICAgICAgImJyb2tlciI6ICJicm9rZXIxIiwKICAgICAgICAiaW5wdXRzIjogMCwKICAgICAgICAieCI6IDE1MCwKICAgICAgICAieSI6IDEyMCwKICAgICAgICAid2lyZXMiOiBbCiAgICAgICAgICAgIFsKICAgICAgICAgICAgICAgICJqc29uX2NvbW1hbmQiLAogICAgICAgICAgICAgICAgImRlYnVnX2NvbW1hbmRfaW4iCiAgICAgICAgICAgIF0KICAgICAgICBdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJqc29uX2NvbW1hbmQiLAogICAgICAgICJ0eXBlIjogImpzb24iLAogICAgICAgICJ6IjogImh1Yl90YWJfY29tbWFuZCIsCiAgICAgICAgIm5hbWUiOiAiSlNPTiBQYXJzZSIsCiAgICAgICAgInByb3BlcnR5IjogInBheWxvYWQiLAogICAgICAgICJhY3Rpb24iOiAiIiwKICAgICAgICAicHJldHR5IjogZmFsc2UsCiAgICAgICAgIngiOiAzNjAsCiAgICAgICAgInkiOiAxMjAsCiAgICAgICAgIndpcmVzIjogWwogICAgICAgICAgICBbCiAgICAgICAgICAgICAgICAiZGVidWdfY29tbWFuZF9wYXJzZWQiCiAgICAgICAgICAgIF0KICAgICAgICBdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJkZWJ1Z19jb21tYW5kX2luIiwKICAgICAgICAidHlwZSI6ICJkZWJ1ZyIsCiAgICAgICAgInoiOiAiaHViX3RhYl9jb21tYW5kIiwKICAgICAgICAibmFtZSI6ICJDb21tYW5kIFJhdyIsCiAgICAgICAgImFjdGl2ZSI6IHRydWUsCiAgICAgICAgInRvc2lkZWJhciI6IHRydWUsCiAgICAgICAgImNvbXBsZXRlIjogInRydWUiLAogICAgICAgICJ0YXJnZXRUeXBlIjogImZ1bGwiLAogICAgICAgICJ4IjogMzYwLAogICAgICAgICJ5IjogMjAwLAogICAgICAgICJ3aXJlcyI6IFtdCiAgICB9LAogICAgewogICAgICAgICJpZCI6ICJkZWJ1Z19jb21tYW5kX3BhcnNlZCIsCiAgICAgICAgInR5cGUiOiAiZGVidWciLAogICAgICAgICJ6IjogImh1Yl90YWJfY29tbWFuZCIsCiAgICAgICAgIm5hbWUiOiAiQ29tbWFuZCBQYXJzZWQiLAogICAgICAgICJhY3RpdmUiOiB0cnVlLAogICAgICAgICJ0b3NpZGViYXIiOiB0cnVlLAogICAgICAgICJjb21wbGV0ZSI6ICJwYXlsb2FkIiwKICAgICAgICAidGFyZ2V0VHlwZSI6ICJtc2ciLAogICAgICAgICJ4IjogNTYwLAogICAgICAgICJ5IjogMTIwLAogICAgICAgICJ3aXJlcyI6IFtdCiAgICB9Cl0K"""))
PYEOF
echo "${PW}" | sudo -S systemctl enable iot-mqtt-ingest iot-hub-api
echo "${PW}" | sudo -S systemctl restart iot-mqtt-ingest iot-hub-api nodered
sleep 5
curl -sf http://127.0.0.1:5000/health && log "  /health OK" || {
  log "  journal:"
  echo "${PW}" | sudo -S journalctl -u iot-hub-api -n 8 --no-pager | sed 's/^/    /'
}
log "  ingest: $(echo ${PW} | sudo -S systemctl is-active iot-mqtt-ingest)"
log "=== STEP 6 BİTTİ ==="
