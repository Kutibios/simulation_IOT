from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

import config

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    psycopg2 = None  # type: ignore


def _dsn() -> str:
    return os.environ.get(
        "DATABASE_URL",
        "postgresql://iothub:iothub123@localhost:5432/iot_telemetry",
    )


def fetch_recent(
    problem_id: str,
    takim_no: str,
    minutes: int = 15,
) -> list[dict[str, Any]]:
    if psycopg2 is None:
        raise RuntimeError("psycopg2 yüklü değil")
    conn = psycopg2.connect(_dsn())
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(
                """
                SELECT time, sensor, sicaklik, nem, hava_kalitesi
                FROM telemetry
                WHERE problem_id = %s AND takim_no = %s
                  AND time >= NOW() - (%s || ' minutes')::interval
                ORDER BY time ASC
                """,
                (problem_id, takim_no, str(int(minutes))),
            )
            rows = cur.fetchall()
    finally:
        conn.close()

    records: list[dict[str, Any]] = []
    for row in rows:
        t = row["time"]
        if isinstance(t, datetime):
            if t.tzinfo is None:
                t = t.replace(tzinfo=timezone.utc)
            ts = t.isoformat().replace("+00:00", "Z")
        else:
            ts = str(t)
        records.append(
            {
                "time": ts,
                "sensor": row.get("sensor"),
                "sicaklik": row.get("sicaklik"),
                "nem": row.get("nem"),
                "hava_kalitesi": row.get("hava_kalitesi"),
            }
        )
    return records


def insert_telemetry(
    problem_id: str,
    takim_no: str,
    sensor: str | None,
    sicaklik: float | None,
    nem: float | None,
    hava_kalitesi: float | None,
) -> None:
    if psycopg2 is None:
        raise RuntimeError("psycopg2 yüklü değil")
    conn = psycopg2.connect(_dsn())
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO telemetry (problem_id, takim_no, sensor, sicaklik, nem, hava_kalitesi)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (problem_id, takim_no, sensor, sicaklik, nem, hava_kalitesi),
            )
        conn.commit()
    finally:
        conn.close()
