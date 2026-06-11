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
