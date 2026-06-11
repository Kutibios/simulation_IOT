from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any

import paho.mqtt.client as mqtt

import config


def publish_command(
    problem_id: str,
    takim_no: str,
    aksiyon: str,
    sure_sn: int,
) -> dict[str, Any]:
    topic = f"{problem_id}/{takim_no}/command"
    payload = {
        "aksiyon": aksiyon,
        "sure_sn": sure_sn,
        "timestamp": datetime.now(timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z"),
    }

    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,  # type: ignore[attr-defined]
        client_id=f"hub_api_{problem_id}_{takim_no}",
    )
    client.connect(config.MQTT_BROKER, config.MQTT_PORT, keepalive=60)
    client.loop_start()
    try:
        info = client.publish(topic, json.dumps(payload), qos=0)
        info.wait_for_publish(timeout=5)
    finally:
        client.loop_stop()
        client.disconnect()

    return {"topic": topic, "payload": payload}
