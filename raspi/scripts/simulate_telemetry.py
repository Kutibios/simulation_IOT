#!/usr/bin/env python3
"""
Mac/local → Pi MQTT broker: gerçekçi telemetri (Pi'ye dosya yüklenmez).

Mesajlar Mac'ten 172.20.10.5:1883 Mosquitto'ya gider.

Topic: {problem_id}/{takim_no}/telemetry
  tarim_sulama/7       — ds18b20 + dht11 (sıcaklık, nem)
  tarim_havalandirma/8 — dht11 + mq135 (sıcaklık, nem, hava_kalitesi)

Kullanım:
  python3 simulate_telemetry.py
  python3 simulate_telemetry.py --broker 172.20.10.5 --interval 5
  MQTT_BROKER=172.20.10.5 ./simulate_telemetry.py --minutes 30
"""

from __future__ import annotations

import argparse
import json
import math
import random
import signal
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone

try:
    import paho.mqtt.client as mqtt
except ImportError:
    print("paho-mqtt gerekli: pip install paho-mqtt", file=sys.stderr)
    sys.exit(1)


def _clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def _round1(value: float) -> float:
    return round(value, 1)


@dataclass
class SensorState:
    """Yavaş trend + gürültü ile sensör değerleri."""

    base_temp: float
    base_humidity: float
    base_aqi: float
    temp_phase: float = field(default_factory=lambda: random.uniform(0, math.pi * 2))
    hum_phase: float = field(default_factory=lambda: random.uniform(0, math.pi * 2))
    aqi_phase: float = field(default_factory=lambda: random.uniform(0, math.pi * 2))
    drift: float = 0.0

    def tick(self, elapsed_min: float) -> None:
        # Uzun vadeli yavaş kayma (sulama kurur / hava kirlenir)
        self.drift += random.uniform(-0.02, 0.02)
        self.drift = _clamp(self.drift, -3.0, 3.0)

    def ds18_temp(self, elapsed_min: float) -> float:
        daily = 2.2 * math.sin((elapsed_min / 90.0) * math.pi + self.temp_phase)
        noise = random.gauss(0, 0.15)
        t = self.base_temp + daily + self.drift * 0.3 + noise
        return _round1(_clamp(t, 18.0, 38.0))

    def dht_temp(self, elapsed_min: float, ds18: float) -> float:
        # DHT11 genelde DS18'den biraz yüksek okur
        offset = random.uniform(0.4, 1.1)
        noise = random.gauss(0, 0.2)
        t = ds18 + offset + noise
        return _round1(_clamp(t, 18.0, 40.0))

    def humidity(self, elapsed_min: float, temp: float) -> float:
        # Sıcaklık artınca nem düşer; gece/gündüz salınımı
        wave = 12 * math.sin((elapsed_min / 120.0) * math.pi + self.hum_phase)
        temp_effect = (26.0 - temp) * 1.8
        noise = random.gauss(0, 1.2)
        h = self.base_humidity + wave + temp_effect + self.drift * 2.5 + noise
        return _round1(_clamp(h, 25.0, 92.0))

    def air_quality(self, elapsed_min: float) -> float:
        # Normal 80–320; ara sıra pik (fan tetiklemek için)
        wave = 80 * math.sin((elapsed_min / 45.0) * math.pi + self.aqi_phase)
        spike = 0.0
        if random.random() < 0.08:
            spike = random.uniform(180, 320)
        noise = random.gauss(0, 8)
        aqi = self.base_aqi + wave + self.drift * 15 + spike + noise
        return _round1(_clamp(aqi, 40.0, 650.0))


SULAMA = SensorState(base_temp=24.5, base_humidity=58.0, base_aqi=0)
HAVA = SensorState(base_temp=27.0, base_humidity=52.0, base_aqi=180.0)

_running = True


def _stop(_signum, _frame) -> None:
    global _running
    _running = False


def build_payloads(elapsed_min: float) -> list[tuple[str, dict]]:
    SULAMA.tick(elapsed_min)
    HAVA.tick(elapsed_min)

    ds18 = SULAMA.ds18_temp(elapsed_min)
    dht_sul_t = SULAMA.dht_temp(elapsed_min, ds18)
    nem_sul = SULAMA.humidity(elapsed_min, dht_sul_t)

    dht_h_t = HAVA.dht_temp(elapsed_min, HAVA.ds18_temp(elapsed_min))
    nem_h = HAVA.humidity(elapsed_min, dht_h_t)
    aqi = HAVA.air_quality(elapsed_min)

    ts = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

    return [
        (
            "tarim_sulama/7/telemetry",
            {
                "sensor": "ds18b20",
                "sicaklik": ds18,
                "timestamp": ts,
            },
        ),
        (
            "tarim_sulama/7/telemetry",
            {
                "sensor": "dht11",
                "sicaklik": dht_sul_t,
                "nem": nem_sul,
                "timestamp": ts,
            },
        ),
        (
            "tarim_havalandirma/8/telemetry",
            {
                "sensor": "dht11",
                "sicaklik": dht_h_t,
                "nem": nem_h,
                "timestamp": ts,
            },
        ),
        (
            "tarim_havalandirma/8/telemetry",
            {
                "sensor": "mq135",
                "sicaklik": dht_h_t,
                "hava_kalitesi": aqi,
                "timestamp": ts,
            },
        ),
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="IoT hub gerçekçi MQTT telemetri simülatörü")
    parser.add_argument("--broker", default=None, help="MQTT broker IP (varsayılan: MQTT_BROKER veya 172.20.10.5)")
    parser.add_argument("--port", type=int, default=int(__import__("os").environ.get("MQTT_PORT", "1883")))
    parser.add_argument("--interval", type=float, default=5.0, help="Mesajlar arası saniye (varsayılan: 5)")
    parser.add_argument("--minutes", type=float, default=0, help="0 = sonsuz; aksi halde N dk sonra dur")
    parser.add_argument("--jitter", type=float, default=0.8, help="± saniye rastgele gecikme")
    args = parser.parse_args()

    broker = args.broker or __import__("os").environ.get("MQTT_BROKER", "172.20.10.5")

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    client = mqtt.Client(
        callback_api_version=mqtt.CallbackAPIVersion.VERSION2,  # type: ignore[attr-defined]
        client_id=f"sim_{int(time.time())}",
    )
    print(f"[sim] Bağlanılıyor {broker}:{args.port} …")
    client.connect(broker, args.port, keepalive=60)
    client.loop_start()

    start = time.monotonic()
    cycle = 0
    elapsed_min = 0.0
    print(f"[sim] Her ~{args.interval}s → sulama/7 + havalandirma/8 (Ctrl+C durdur)")
    print("[sim] Trend: sıcaklık/nem dalgalanır; nem>70 veya AQI>400 → YZ tetiklenir\n")

    try:
        while _running:
            elapsed_min = (time.monotonic() - start) / 60.0
            if args.minutes > 0 and elapsed_min >= args.minutes:
                break

            cycle += 1
            for topic, payload in build_payloads(elapsed_min):
                body = json.dumps(payload, ensure_ascii=False)
                client.publish(topic, body, qos=0)
                print(
                    f"[{cycle:04d}] {topic}  "
                    f"{payload.get('sensor')}: "
                    f"T={payload.get('sicaklik', '-')} "
                    f"N={payload.get('nem', '-')} "
                    f"AQI={payload.get('hava_kalitesi', '-')}"
                )

            delay = args.interval + random.uniform(-args.jitter, args.jitter)
            delay = max(1.0, delay)
            time.sleep(delay)
    finally:
        client.loop_stop()
        client.disconnect()
        print(f"\n[sim] Bitti ({cycle} döngü, {elapsed_min:.1f} dk)")


if __name__ == "__main__":
    main()
