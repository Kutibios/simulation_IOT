#!/usr/bin/env python3
"""
Raspberry Pi tarafında: yerel Mosquitto'ya bağlanır, standart topic'lere abone olur ve
gelen mesajları konsola (+ isteğe bağlı bir JSON Lines dosyasına) yazar.

Konu şeması: {problem_id}/{takim_no}/{mesaj_tipi}
Örnek: tarim_sulama/3/telemetry

Diğer ekipler doğrudan bu broker'a (aynı LAN'da Pi'nin IP'si, port 1883) bağlanarak
aynı kuralla publish edebilir; bu süreç Mosquitto'da yapılır. Dinleyici, hub
üzerinden verinin geldiğini doğrular ve günlükler.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone

import paho.mqtt.client as mqtt

BROKER = os.environ.get("MQTT_BROKER", "127.0.0.1")
PORT = int(os.environ.get("MQTT_PORT", "1883"))
# Aynı client_id ile iki süreç bağlanırsa broker biri keser → on_connect döngüsü görülebilir.
_default_cid = f"pi_hub_{os.getpid()}"
CLIENT_ID = (os.environ.get("MQTT_HUB_CLIENT_ID") or _default_cid).strip() or _default_cid

# Virgülle ayrılmış abonelikler; yaygın kullanım: tüm telemetry + tüm command
_raw_subs = os.environ.get(
    "MQTT_SUB_TOPICS",
    "+/+/telemetry,+/+/command",
).split(",")
SUB_TOPICS = [s.strip() for s in _raw_subs if s.strip()]

LOG_PATH = os.environ.get("MQTT_HUB_LOG", "").strip()


def split_topic(topic: str) -> dict[str, str] | None:
    parts = topic.split("/")
    if len(parts) != 3:
        return None
    return {
        "problem_id": parts[0],
        "takim_no": parts[1],
        "mesaj_tipi": parts[2],
    }


def on_connect(client, _userdata, flags, reason_code, properties):
    # Callback API VERSION2 (paho-mqtt 2.x önerilir; VERSION1 uyarısı vermez)
    if reason_code.is_failure:
        print(f"[hub] Bağlantı başarısız: {reason_code}", file=sys.stderr)
        return
    print(f"[hub] Bağlı: {BROKER}:{PORT} — topic'ler:")
    for t in SUB_TOPICS:
        client.subscribe(t, qos=0)
        print(f"      subscribe {t}")


def on_disconnect(_client, _userdata, disconnect_flags, reason_code, properties):
    # Bağlantı koptuğunda sebep stderr'de (yeniden bağlanma öncesi teşhis için)
    print(
        f"[hub] Bağlantı kesildi (flags={disconnect_flags}, reason={reason_code})",
        file=sys.stderr,
        flush=True,
    )


def on_message(_client, _userdata, msg):
    routing = split_topic(msg.topic)
    try:
        text = msg.payload.decode("utf-8") if isinstance(msg.payload, (bytes, bytearray)) else str(msg.payload)
    except UnicodeDecodeError:
        text = repr(msg.payload)

    payload_out: dict | list | str
    try:
        payload_out = json.loads(text)
    except json.JSONDecodeError:
        payload_out = text

    record = {
        "received_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "mqtt_topic": msg.topic,
        "routing": routing,
        "qos": getattr(msg, "qos", None),
        "payload": payload_out,
    }

    line = json.dumps(record, ensure_ascii=False)
    print(line, flush=True)

    if LOG_PATH:
        with open(LOG_PATH, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")


def main() -> None:
    if not SUB_TOPICS:
        print("[hub] MQTT_SUB_TOPICS boş.", file=sys.stderr)
        sys.exit(1)

    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,  # type: ignore[attr-defined]
        client_id=CLIENT_ID,
    )

    client.on_connect = on_connect
    client.on_disconnect = on_disconnect
    client.on_message = on_message

    print(f"[hub] Bağlanılıyor {BROKER}:{PORT} (client_id={CLIENT_ID}) ...")
    client.connect(BROKER, PORT, keepalive=60)
    client.loop_forever()


if __name__ == "__main__":
    main()
