#!/usr/bin/env python3
"""Rapor için örnek sensör zaman serisi grafikleri."""

from __future__ import annotations

import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

HERE = Path(__file__).resolve().parent


def _time_axis(n: int = 60):
    return np.linspace(0, 30, n)


def grafik_sulama(path: Path) -> None:
    t = _time_axis()
    sicaklik = 24 + 2 * np.sin(t / 4) + np.random.normal(0, 0.15, len(t))
    nem = 55 + 8 * np.sin(t / 3 + 1) + np.random.normal(0, 1.2, len(t))

    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(8, 4.5), dpi=150, sharex=True)
    fig.patch.set_facecolor("#fafafa")
    ax1.plot(t, sicaklik, color="#e53935", linewidth=1.8, label="Sıcaklık (°C)")
    ax1.set_ylabel("°C")
    ax1.set_title("Takım 7 — Tarım Sulama (DS18B20 / DHT11)", fontsize=10, fontweight="bold")
    ax1.grid(True, alpha=0.35)
    ax1.legend(loc="upper right", fontsize=8)

    ax2.plot(t, nem, color="#1e88e5", linewidth=1.8, label="Nem (%)")
    ax2.axhline(70, color="#ff9800", linestyle="--", linewidth=1, label="Üst eşik (%70)")
    ax2.set_xlabel("Zaman (dk)")
    ax2.set_ylabel("%")
    ax2.grid(True, alpha=0.35)
    ax2.legend(loc="upper right", fontsize=8)

    fig.tight_layout()
    fig.savefig(path, bbox_inches="tight", facecolor=fig.patch.get_facecolor())
    plt.close(fig)


def grafik_havalandirma(path: Path) -> None:
    t = _time_axis()
    sicaklik = 26 + 3 * np.sin(t / 5) + np.random.normal(0, 0.2, len(t))
    nem = 48 + 6 * np.cos(t / 4) + np.random.normal(0, 1.0, len(t))
    aqi = 180 + 80 * (1 + np.sin(t / 2.5)) / 2 + np.random.normal(0, 8, len(t))
    aqi[45:52] += 280  # spike

    fig, axes = plt.subplots(3, 1, figsize=(8, 5.5), dpi=150, sharex=True)
    fig.patch.set_facecolor("#fafafa")
    fig.suptitle("Takım 8 — Tarım Havalandırma (DHT11 / MQ-135)", fontsize=10, fontweight="bold")

    axes[0].plot(t, sicaklik, color="#e53935", linewidth=1.6)
    axes[0].set_ylabel("°C")
    axes[0].grid(True, alpha=0.35)

    axes[1].plot(t, nem, color="#1e88e5", linewidth=1.6)
    axes[1].set_ylabel("Nem %")
    axes[1].grid(True, alpha=0.35)

    axes[2].plot(t, aqi, color="#43a047", linewidth=1.6)
    axes[2].axhline(400, color="#ff9800", linestyle="--", linewidth=1, label="AQI eşik (400)")
    axes[2].set_xlabel("Zaman (dk)")
    axes[2].set_ylabel("Hava kalitesi")
    axes[2].grid(True, alpha=0.35)
    axes[2].legend(loc="upper right", fontsize=8)

    fig.tight_layout()
    fig.savefig(path, bbox_inches="tight", facecolor=fig.patch.get_facecolor())
    plt.close(fig)


def grafik_mqtt_akisi(path: Path) -> None:
    fig, ax = plt.subplots(figsize=(8, 3.2), dpi=150)
    ax.axis("off")
    fig.patch.set_facecolor("#fafafa")

    steps = [
        ("1", "Sensör okuma", "DS18B20 / DHT11 / MQ-135"),
        ("2", "JSON telemetri", "MQTT publish"),
        ("3", "Hub işleme", "Kayıt + görselleştirme"),
        ("4", "YZ analizi", "Gemini karar"),
        ("5", "Komut", "sulama_ac / fan_ac"),
    ]
    xs = np.linspace(0.08, 0.92, len(steps))
    for i, (num, title, sub) in enumerate(steps):
        x = xs[i]
        ax.add_patch(plt.Circle((x, 0.55), 0.045, color="#1565c0", zorder=2))
        ax.text(x, 0.55, num, ha="center", va="center", color="white", fontweight="bold", fontsize=9)
        ax.text(x, 0.38, title, ha="center", va="top", fontsize=9, fontweight="bold")
        ax.text(x, 0.28, sub, ha="center", va="top", fontsize=7.5, color="#546e7a")
        if i < len(steps) - 1:
            ax.annotate("", xy=(xs[i + 1] - 0.06, 0.55), xytext=(x + 0.06, 0.55),
                        arrowprops=dict(arrowstyle="->", color="#78909c", lw=1.5))

    ax.set_xlim(0, 1)
    ax.set_ylim(0.1, 0.75)
    ax.set_title("Telemetri → Analiz → Komut Döngüsü", fontsize=10, fontweight="bold", pad=8)
    fig.savefig(path, bbox_inches="tight", facecolor=fig.patch.get_facecolor())
    plt.close(fig)


def main() -> None:
    np.random.seed(42)
    grafik_sulama(HERE / "grafik_sulama.png")
    grafik_havalandirma(HERE / "grafik_havalandirma.png")
    grafik_mqtt_akisi(HERE / "grafik_akis_dongusu.png")
    print("Grafikler yazıldı:", HERE)


if __name__ == "__main__":
    main()
