from __future__ import annotations

from typing import Any

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

import config
from gemini_client import analyze_with_gemini
from postgres_client import fetch_recent
from mqtt_client import publish_command

app = FastAPI(title="IoT Hub API", version="1.0.0")


class AnalyzeRequest(BaseModel):
    problem_id: str
    takim_no: str
    window_min: int = Field(default=15, ge=1, le=1440)


class CommandRequest(BaseModel):
    problem_id: str
    takim_no: str
    aksiyon: str
    sure_sn: int = Field(ge=0)


def _validate_problem(problem_id: str) -> None:
    if problem_id not in config.VALID_PROBLEM_IDS:
        raise HTTPException(
            status_code=400,
            detail=f"Geçersiz problem_id: {problem_id}. İzin verilen: {sorted(config.VALID_PROBLEM_IDS)}",
        )


@app.get("/health")
def health() -> dict[str, Any]:
    db_url = getattr(config, "DATABASE_URL", "")
    return {
        "status": "ok",
        "database": "postgresql" if db_url else "none",
        "postgres_configured": bool(db_url),
        "gemini_configured": bool(config.GEMINI_API_KEY),
        "mqtt_broker": f"{config.MQTT_BROKER}:{config.MQTT_PORT}",
    }


@app.post("/analyze")
def analyze(body: AnalyzeRequest) -> dict[str, Any]:
    _validate_problem(body.problem_id)
    try:
        records = fetch_recent(body.problem_id, body.takim_no, body.window_min)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Veritabanı sorgu hatası: {exc}") from exc

    result = analyze_with_gemini(body.problem_id, body.takim_no, records)
    return {
        "problem_id": body.problem_id,
        "takim_no": body.takim_no,
        "window_min": body.window_min,
        "record_count": len(records),
        **result,
    }


@app.get("/history/{problem_id}/{takim_no}")
def history(
    problem_id: str,
    takim_no: str,
    minutes: int = Query(default=15, ge=1, le=1440),
) -> dict[str, Any]:
    _validate_problem(problem_id)
    try:
        records = fetch_recent(problem_id, takim_no, minutes)
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Veritabanı sorgu hatası: {exc}") from exc

    return {
        "problem_id": problem_id,
        "takim_no": takim_no,
        "minutes": minutes,
        "count": len(records),
        "records": records,
    }


@app.post("/command")
def command(body: CommandRequest) -> dict[str, Any]:
    _validate_problem(body.problem_id)
    try:
        published = publish_command(
            body.problem_id,
            body.takim_no,
            body.aksiyon,
            body.sure_sn,
        )
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"MQTT yayın hatası: {exc}") from exc

    return {
        "ok": True,
        **published,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host=config.API_HOST, port=config.API_PORT, reload=False)
