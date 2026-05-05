import json
import time
import random
import math
from datetime import datetime, timezone
import paho.mqtt.client as mqtt

BROKER = "mosquitto"
PORT = 1883
TOPIC = "7/telemetry"
INTERVAL = 5

client = mqtt.Client()
client.connect(BROKER, PORT, 60)
client.loop_start()

print(f"Publisher started → topic: {TOPIC}, interval: {INTERVAL}s")

t = 0
while True:
    sicaklik = round(22 + 5 * math.sin(t * 0.1) + random.gauss(0, 0.4), 2)
    nem = round(75 - 0.8 * sicaklik + random.gauss(0, 1), 2)
    isik = round(400 + 150 * math.sin(t * 0.05 + 1) + random.gauss(0, 10), 2)

    payload = {
        "sensor_id": "temp_01",
        "values": {
            "sicaklik": sicaklik,
            "nem": nem,
            "isik": isik,
        },
        "unit": "metric",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

    client.publish(TOPIC, json.dumps(payload))
    print(f"[{payload['timestamp']}] sicaklik={sicaklik} nem={nem} isik={isik}")

    t += 1
    time.sleep(INTERVAL)
