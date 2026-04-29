import json
import sqlite3
import threading
from datetime import datetime
import paho.mqtt.client as mqtt

BROKER = "mosquitto"
PORT = 1883
TOPIC = "7/telemetry"
DB_PATH = "/data/telemetry.db"

def get_conn():
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS telemetry (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            sensor_id TEXT,
            sicaklik  REAL,
            nem       REAL,
            isik      REAL,
            timestamp TEXT
        )
    """)
    conn.commit()
    return conn

_lock = threading.Lock()
_conn = get_conn()

def on_message(client, userdata, msg):
    try:
        data = json.loads(msg.payload)
        v = data["values"]
        with _lock:
            _conn.execute(
                "INSERT INTO telemetry (sensor_id, sicaklik, nem, isik, timestamp) VALUES (?,?,?,?,?)",
                (data["sensor_id"], v["sicaklik"], v["nem"], v["isik"], data["timestamp"]),
            )
            _conn.commit()
        print(f"[DB] {data['timestamp']} sicaklik={v['sicaklik']} nem={v['nem']} isik={v['isik']}")
    except Exception as e:
        print(f"[ERR] {e}")

client = mqtt.Client()
client.on_message = on_message
client.connect(BROKER, PORT, 60)
client.subscribe(TOPIC)
print(f"Subscriber listening on {TOPIC}")
client.loop_forever()
