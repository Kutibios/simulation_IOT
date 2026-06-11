from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from influxdb_client import InfluxDBClient

import config


def _client() -> InfluxDBClient:
    if not config.INFLUX_TOKEN:
        raise RuntimeError("INFLUX_TOKEN tanımlı değil")
    return InfluxDBClient(
        url=config.INFLUX_URL,
        token=config.INFLUX_TOKEN,
        org=config.INFLUX_ORG,
    )


def _escape_flux(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')


def _record_from_row(row: dict[str, Any]) -> dict[str, Any]:
    record: dict[str, Any] = {
        "time": row.get("_time"),
        "sensor": row.get("sensor"),
    }
    for field in ("sicaklik", "nem", "hava_kalitesi"):
        if field in row and row[field] is not None:
            record[field] = row[field]
    if isinstance(record["time"], datetime):
        if record["time"].tzinfo is None:
            record["time"] = record["time"].replace(tzinfo=timezone.utc)
        record["time"] = record["time"].isoformat().replace("+00:00", "Z")
    return record


def fetch_recent(
    problem_id: str,
    takim_no: str,
    minutes: int = 15,
) -> list[dict[str, Any]]:
    pid = _escape_flux(problem_id)
    team = _escape_flux(takim_no)
    measurement = _escape_flux(config.INFLUX_MEASUREMENT)
    bucket = _escape_flux(config.INFLUX_BUCKET)

    query = f'''
from(bucket: "{bucket}")
  |> range(start: -{int(minutes)}m)
  |> filter(fn: (r) => r._measurement == "{measurement}")
  |> filter(fn: (r) => r["problem_id"] == "{pid}")
  |> filter(fn: (r) => r["takim_no"] == "{team}")
  |> pivot(rowKey: ["_time", "sensor"], columnKey: ["_field"], valueColumn: "_value")
  |> sort(columns: ["_time"], desc: false)
'''

    with _client() as client:
        tables = client.query_api().query(query, org=config.INFLUX_ORG)

    records: list[dict[str, Any]] = []
    for table in tables:
        for record in table.records:
            row = record.values.copy()
            parsed = _record_from_row(row)
            if parsed.get("sensor"):
                records.append(parsed)
    return records
