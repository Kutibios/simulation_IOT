from __future__ import annotations

import json
import re
from typing import Any

import config

try:
    import google.generativeai as genai
except ImportError:  # pragma: no cover
    genai = None  # type: ignore[assignment]


ACTIONS = {
    "tarim_sulama": ("sulama_ac", "sulama_kapat"),
    "tarim_havalandirma": ("fan_ac", "fan_kapat"),
}


def _latest_averages(records: list[dict[str, Any]]) -> dict[str, float | None]:
    sums: dict[str, list[float]] = {
        "sicaklik": [],
        "nem": [],
        "hava_kalitesi": [],
    }
    for row in records:
        for key in sums:
            value = row.get(key)
            if value is not None:
                try:
                    sums[key].append(float(value))
                except (TypeError, ValueError):
                    pass

    return {
        key: (sum(values) / len(values) if values else None)
        for key, values in sums.items()
    }


def rule_based_analysis(
    problem_id: str,
    records: list[dict[str, Any]],
) -> dict[str, Any]:
    avg = _latest_averages(records)
    on_action, off_action = ACTIONS.get(problem_id, ("bekle", "bekle"))

    if not records:
        return {
            "aksiyon": "bekle",
            "sure_sn": 0,
            "gerekce": "Son dönemde telemetri kaydı yok; kural tabanlı varsayılan.",
            "source": "fallback",
        }

    if problem_id == "tarim_sulama":
        nem = avg.get("nem")
        if nem is not None and nem < 45:
            return {
                "aksiyon": on_action,
                "sure_sn": 120,
                "gerekce": f"Ortalama nem düşük ({nem:.1f}%); sulama önerildi.",
                "source": "fallback",
            }
        if nem is not None and nem > 70:
            return {
                "aksiyon": off_action,
                "sure_sn": 0,
                "gerekce": f"Ortalama nem yeterli ({nem:.1f}%); sulama gerekmiyor.",
                "source": "fallback",
            }

    if problem_id == "tarim_havalandirma":
        sicaklik = avg.get("sicaklik")
        hava = avg.get("hava_kalitesi")
        if sicaklik is not None and sicaklik > 28:
            return {
                "aksiyon": on_action,
                "sure_sn": 180,
                "gerekce": f"Sıcaklık yüksek ({sicaklik:.1f}°C); fan açılmalı.",
                "source": "fallback",
            }
        if hava is not None and hava < 40:
            return {
                "aksiyon": on_action,
                "sure_sn": 150,
                "gerekce": f"Hava kalitesi düşük ({hava:.1f}); havalandırma önerildi.",
                "source": "fallback",
            }
        if sicaklik is not None and sicaklik < 22 and (hava is None or hava >= 50):
            return {
                "aksiyon": off_action,
                "sure_sn": 0,
                "gerekce": "Koşullar normal; fan kapalı kalabilir.",
                "source": "fallback",
            }

    return {
        "aksiyon": "bekle",
        "sure_sn": 60,
        "gerekce": "Eşikler normal aralıkta; izlemeye devam.",
        "source": "fallback",
    }


def _extract_json(text: str) -> dict[str, Any]:
    text = text.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    parsed = json.loads(text)
    if not isinstance(parsed, dict):
        raise ValueError("Gemini yanıtı JSON nesnesi değil")
    return parsed


def _build_prompt(problem_id: str, takim_no: str, records: list[dict[str, Any]]) -> str:
    problem_label = {
        "tarim_sulama": "tarım sulama",
        "tarim_havalandirma": "tarım havalandırma",
    }.get(problem_id, problem_id)

    allowed = ACTIONS.get(problem_id, ("bekle",))
    return f"""Sen bir IoT karar motorusun. Görev: {problem_label} alt problemi, takım {takim_no}.

Aşağıdaki son telemetri kayıtlarına göre TEK bir aksiyon öner.
Yalnızca geçerli JSON döndür; markdown veya açıklama ekleme.

İzin verilen aksiyonlar: {", ".join(allowed)}, bekle

JSON şeması:
{{
  "aksiyon": "string",
  "sure_sn": 0,
  "gerekce": "Türkçe kısa gerekçe"
}}

Telemetri:
{json.dumps(records, ensure_ascii=False)}
"""


def analyze_with_gemini(
    problem_id: str,
    takim_no: str,
    records: list[dict[str, Any]],
) -> dict[str, Any]:
    if not config.GEMINI_API_KEY or genai is None:
        return rule_based_analysis(problem_id, records)

    genai.configure(api_key=config.GEMINI_API_KEY)
    model = genai.GenerativeModel(config.GEMINI_MODEL)
    prompt = _build_prompt(problem_id, takim_no, records)

    try:
        response = model.generate_content(
            prompt,
            generation_config={
                "temperature": 0.2,
                "response_mime_type": "application/json",
            },
        )
        text = (response.text or "").strip()
        result = _extract_json(text)
        return {
            "aksiyon": str(result.get("aksiyon", "bekle")),
            "sure_sn": int(result.get("sure_sn", 0)),
            "gerekce": str(result.get("gerekce", "Gemini analizi")),
            "source": "gemini",
        }
    except Exception as exc:
        fallback = rule_based_analysis(problem_id, records)
        fallback["gerekce"] = f"Gemini hatası ({exc}); kural tabanlı yanıt kullanıldı."
        return fallback
