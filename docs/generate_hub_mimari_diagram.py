#!/usr/bin/env python3
"""Raspberry Pi IoT Hub mimari diyagramı → docs/hub_mimari.png"""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

HERE = Path(__file__).resolve().parent
OUT = HERE / "hub_mimari.png"

COL_TEAM = "#66bb6a"
COL_MQTT = "#ffa726"
COL_NR = "#42a5f5"
COL_PG = "#ab47bc"
COL_API = "#7e57c2"
COL_AI = "#26c6da"
EDGE = "#263238"


def _box(ax, x, y, w, h, face, title, lines):
    r = FancyBboxPatch(
        (x, y), w, h,
        boxstyle="round,pad=0.04,rounding_size=0.12",
        facecolor=face, edgecolor=EDGE, linewidth=1.4,
    )
    ax.add_patch(r)
    cx = x + w / 2
    ax.text(cx, y + h - 0.12, title, ha="center", va="top",
            fontsize=9.5, fontweight="bold", color=EDGE)
    yy = y + h - 0.32
    for line in lines:
        ax.text(cx, yy, line, ha="center", va="top", fontsize=7.5, color="#37474f")
        yy -= 0.22
    return cx, y + h / 2


def _arrow(ax, x1, y1, x2, y2, label=None, rad=0.0):
    a = FancyArrowPatch(
        (x1, y1), (x2, y2), arrowstyle="-|>", mutation_scale=14,
        linewidth=1.2, color="#546e7a",
        connectionstyle=f"arc3,rad={rad}",
    )
    ax.add_patch(a)
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        ax.text(mx, my + 0.1, label, ha="center", va="bottom",
                fontsize=7, color="#455a64")


def write_hub_mimari(path: Path | None = None) -> Path:
    path = path or OUT
    plt.rcParams["font.family"] = "DejaVu Sans"
    fig, ax = plt.subplots(figsize=(12.5, 6.2), dpi=150)
    ax.set_xlim(0, 13)
    ax.set_ylim(0, 6.5)
    ax.axis("off")
    fig.patch.set_facecolor("#fafafa")

    # Pi container
    pi = FancyBboxPatch(
        (0.35, 0.35), 12.3, 5.75,
        boxstyle="round,pad=0.06,rounding_size=0.2",
        facecolor="#eceff1", edgecolor="#78909c", linewidth=2, linestyle="--",
    )
    ax.add_patch(pi)
    ax.text(6.5, 5.85, "Raspberry Pi — Akıllı Sistemler Yönetim Birimi (IoT Hub)",
            ha="center", fontsize=11, fontweight="bold", color="#37474f")

    # Teams left
    _, cy7 = _box(ax, 0.55, 3.8, 2.0, 1.35, COL_TEAM, "Takım 7 — Sulama",
                  ["DS18B20, DHT11", "tarim_sulama/7/telemetry"])
    _, cy8 = _box(ax, 0.55, 1.9, 2.0, 1.35, COL_TEAM, "Takım 8 — Havalandırma",
                  ["DHT11, MQ-135", "tarim_havalandirma/8/telemetry"])

    # Mosquitto
    mx, mcy = _box(ax, 3.0, 2.85, 1.85, 1.5, COL_MQTT, "Mosquitto",
                   ["MQTT Broker", "Port 1883", "Anonim erişim"])

    # Node-RED
    nx, ncy = _box(ax, 5.35, 4.0, 2.1, 1.35, COL_NR, "Node-RED :1880",
                   ["Dashboard /ui", "Veri ayırma", "YZ tetikleme"])

    # Ingest
    ix, icy = _box(ax, 5.35, 2.2, 2.1, 1.35, COL_NR, "mqtt_ingest.py",
                   ["+/+/telemetry abone", "JSON → PostgreSQL"])

    # PostgreSQL
    px, pcy = _box(ax, 8.0, 2.2, 2.0, 1.35, COL_PG, "PostgreSQL 17",
                   ["iot_telemetry DB", "telemetry tablosu"])

    # FastAPI
    ax2, acy = _box(ax, 8.0, 4.0, 2.0, 1.35, COL_API, "FastAPI hub-api",
                    ["Port 5000", "/analyze, /history"])

    # Gemini
    gx, gcy = _box(ax, 10.5, 4.0, 1.85, 1.35, COL_AI, "Google Gemini",
                   ["gemini-2.5-flash", "Karar motoru"])

    # User
    ax.text(10.9, 1.15, "Kullanıcı\n:1880/ui", ha="center", va="center",
            fontsize=8.5, color=EDGE,
            bbox=dict(boxstyle="round,pad=0.35", facecolor="#fff9c4", edgecolor=EDGE))

    _arrow(ax, 2.55, cy7, mx - 0.95, mcy + 0.3, "telemetry")
    _arrow(ax, 2.55, cy8, mx - 0.95, mcy - 0.3, "telemetry")
    _arrow(ax, mx + 0.95, mcy + 0.35, nx - 1.05, ncy - 0.2, "subscribe")
    _arrow(ax, mx + 0.95, mcy - 0.35, ix - 1.05, icy + 0.2, "subscribe")
    _arrow(ax, ix + 1.05, icy, px - 1.0, pcy, "INSERT")
    _arrow(ax, ax2 - 1.0, acy - 0.3, px + 1.0, pcy + 0.3, "SELECT", rad=-0.15)
    _arrow(ax, ax2 + 1.0, acy, gx - 0.95, gcy, "API")
    _arrow(ax, gx - 0.95, gcy - 0.5, mx + 0.95, mcy + 0.5, "command", rad=0.25)
    _arrow(ax, nx + 1.05, ncy - 0.5, 10.9, 1.55, None, rad=0.2)

    fig.tight_layout(pad=0.2)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, bbox_inches="tight", pad_inches=0.12, facecolor=fig.patch.get_facecolor())
    plt.close(fig)
    return path


if __name__ == "__main__":
    p = write_hub_mimari()
    print("Yazıldı:", p)
