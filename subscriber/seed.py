import sqlite3
import math
import random
from datetime import datetime, timezone, timedelta

DB_PATH = "/data/telemetry.db"
INTERVAL_MIN = 1  # her 1 dakikada bir veri noktası

conn = sqlite3.connect(DB_PATH)
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

# Zaten veri varsa seed etme
count = conn.execute("SELECT COUNT(*) FROM telemetry").fetchone()[0]
if count > 0:
    print(f"[SEED] Veritabanında zaten {count} kayıt var, atlanıyor.")
    conn.close()
    exit()

print("[SEED] 3 günlük geçmiş veri üretiliyor...")

now   = datetime.now(timezone.utc)
start = now - timedelta(days=3)
total_minutes = 3 * 24 * 60  # 4320 dakika

rows = []
for i in range(total_minutes):
    ts    = start + timedelta(minutes=i)
    hour  = ts.hour + ts.minute / 60.0  # 0-24 arası kesirli saat

    # — Sıcaklık: gece ~15°C, öğleden sonra 14:00'te ~30°C
    # Günlük sinüs dalgası: minimum 05:00'te, maksimum 14:00'te
    daily_phase = (hour - 5) / 24 * 2 * math.pi
    temp_base   = 22 + 8 * math.sin(daily_phase - math.pi / 2 + 0.5)
    # Günden güne hafif farklılık
    day_offset  = math.sin(i / 1440 * 2 * math.pi) * 1.5
    sicaklik    = round(temp_base + day_offset + random.uniform(-0.4, 0.4), 2)

    # — Nem: sıcaklıkla ters orantılı
    nem = round(85 - 1.4 * sicaklik + random.uniform(-1.5, 1.5), 2)
    nem = max(30, min(95, nem))  # gerçekçi aralık

    # — Işık: gündüz güneş eğrisi (06:00 - 20:00), gece 0
    if 6 <= hour <= 20:
        sun_phase = (hour - 6) / 14 * math.pi  # 0 → π
        cloud     = random.uniform(0.7, 1.0)    # bulut etkisi
        isik      = round(900 * math.sin(sun_phase) * cloud + random.uniform(-15, 15), 2)
        isik      = max(0, isik)
    else:
        isik = round(random.uniform(0, 5), 2)   # gece: neredeyse sıfır

    rows.append(("temp_01", sicaklik, nem, isik, ts.isoformat()))

conn.executemany(
    "INSERT INTO telemetry (sensor_id, sicaklik, nem, isik, timestamp) VALUES (?,?,?,?,?)",
    rows,
)
conn.commit()
conn.close()
print(f"[SEED] {len(rows)} veri noktası eklendi.")
