#!/usr/bin/env python3
"""
BLM-0482 mimari akış diyagramı — matplotlib ile üretilir (yapıştırma görseli gerekmez).
Çıktı: docs/mimari_akis.png
"""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

HERE = Path(__file__).resolve().parent
OUT = HERE / "mimari_akis.png"

# Renkler (referans diyagrama yakın)
COL_PUB = "#66bb6a"
COL_BRK = "#ffa726"
COL_SUB = "#42a5f5"
COL_DB = "#ab47bc"
COL_DASH = "#ef9a9a"
EDGE = "#263238"


def _box(
    ax,
    x: float,
    y: float,
    w: float,
    h: float,
    face: str,
    title: str,
    lines: list[str],
) -> tuple[float, float]:
    """Sol-alt (x,y), genişlik w yükseklik h. Merkez (cx, cy) döner."""
    r = FancyBboxPatch(
        (x, y),
        w,
        h,
        boxstyle="round,pad=0.04,rounding_size=0.14",
        facecolor=face,
        edgecolor=EDGE,
        linewidth=1.5,
    )
    ax.add_patch(r)
    cx, cy = x + w / 2, y + h / 2
    ax.text(
        cx,
        y + h - 0.14,
        title,
        ha="center",
        va="top",
        fontsize=10,
        fontweight="bold",
        color=EDGE,
    )
    yy = y + h - 0.36
    for line in lines:
        ax.text(cx, yy, line, ha="center", va="top", fontsize=8, color="#37474f")
        yy -= 0.24
    return cx, cy


def _arrow(ax, x1, y1, x2, y2, label: str | None = None, rad: float = 0):
    a = FancyArrowPatch(
        (x1, y1),
        (x2, y2),
        arrowstyle="-|>",
        mutation_scale=16,
        linewidth=1.35,
        color="#546e7a",
        connectionstyle=f"arc3,rad={rad}",
    )
    ax.add_patch(a)
    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2
        ax.text(mx, my + 0.12, label, ha="center", va="bottom", fontsize=7.5, color="#455a64")


def write_mimari_png(path: Path | None = None) -> Path:
    path = path or OUT
    plt.rcParams["font.family"] = "DejaVu Sans"

    # Geniş tuval — kutular sıkışmasın
    X0, Y0 = 13.2, 5.4
    fig, ax = plt.subplots(figsize=(12.8, 5.0), dpi=150)
    ax.set_xlim(0, X0)
    ax.set_ylim(0, Y0)
    ax.axis("off")
    fig.patch.set_facecolor("#fafafa")
    ax.set_facecolor("#fafafa")

    # Üst sıra: Publisher → Broker → Subscriber (geniş aralıklar)
    w1, w2, w3 = 2.15, 2.0, 2.45
    h_top = 1.55
    h_gap = 0.55
    y_top = 3.05
    x1 = 0.55
    x2 = x1 + w1 + h_gap
    x3 = x2 + w2 + h_gap

    _box(
        ax,
        x1,
        y_top,
        w1,
        h_top,
        COL_PUB,
        "publisher.py",
        [
            "Simülasyon verisi (sin / cos)",
            "JSON · her ~5 sn",
            "MQTT publish → 7/telemetry",
        ],
    )
    _box(
        ax,
        x2,
        y_top,
        w2,
        h_top,
        COL_BRK,
        "eclipse-mosquitto",
        [
            "MQTT broker",
            "Port 1883",
        ],
    )
    _box(
        ax,
        x3,
        y_top,
        w3,
        h_top,
        COL_SUB,
        "subscriber.py",
        [
            "MQTT subscribe",
            "JSON parse",
            "dashboard.py aynı konteyner",
            "Servis portu 8050",
        ],
    )

    cy = y_top + h_top / 2
    mid_gap = 0.08
    _arrow(ax, x1 + w1 + mid_gap, cy, x2 - mid_gap, cy, "publish")
    _arrow(ax, x2 + w2 + mid_gap, cy, x3 - mid_gap, cy, "iletim")

    # SQLite — abonenin altında, üst bloktan ayrık
    w_db, h_db = 2.35, 1.15
    mid_sub_x = x3 + w3 / 2
    x_db = mid_sub_x - w_db / 2
    y_db = 1.65
    _box(
        ax,
        x_db,
        y_db,
        w_db,
        h_db,
        COL_DB,
        "SQLite · telemetry.db",
        ["INSERT (abone)", "Docker volume: /data"],
    )

    _arrow(
        ax,
        mid_sub_x,
        y_top - 0.06,
        mid_sub_x,
        y_db + h_db + 0.06,
        "kayıt",
    )

    # Dashboard — altta ferah
    w_d, h_d = 2.35, 1.05
    x_d = mid_sub_x - w_d / 2
    y_d = 0.32
    _box(
        ax,
        x_d,
        y_d,
        w_d,
        h_d,
        COL_DASH,
        "dashboard.py",
        [
            "SELECT (~5 sn)",
            "Grafik · Min · Max · Ort · Var",
        ],
    )

    _arrow(
        ax,
        x_db + w_db / 2,
        y_db - 0.06,
        x_d + w_d / 2,
        y_d + h_d + 0.06,
        "okuma",
    )

    # Kullanıcı — sağda bol boşluk
    ux, uy = 10.85, 2.05
    ax.text(
        ux,
        uy,
        "Kullanıcı\nlocalhost:8050",
        ha="center",
        va="center",
        fontsize=9,
        color=EDGE,
        bbox=dict(boxstyle="round,pad=0.45", facecolor="#eceff1", edgecolor=EDGE, linewidth=1.2),
    )
    _arrow(ax, x_d + w_d + 0.35, y_d + h_d / 2, ux - 1.05, uy, None, rad=0.15)

    ax.text(
        X0 / 2,
        Y0 - 0.2,
        "IoT simülasyonu — MQTT veri hattı (Docker)",
        ha="center",
        va="top",
        fontsize=11,
        fontweight="bold",
        color="#37474f",
    )

    fig.tight_layout(pad=0.35)
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(
        path,
        bbox_inches="tight",
        pad_inches=0.15,
        facecolor=fig.patch.get_facecolor(),
    )
    plt.close(fig)
    return path


def main() -> None:
    p = write_mimari_png()
    print("Yazıldı:", p)


if __name__ == "__main__":
    main()
