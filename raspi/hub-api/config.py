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
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-2.5-flash").strip()

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
