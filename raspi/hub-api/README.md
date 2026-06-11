# IoT Hub REST API

Akıllı Sistemler Yönetim Birimi hub servisi: InfluxDB telemetrisini okur, Gemini ile analiz eder, MQTT komut yayınlar.

Desteklenen alt problemler: `tarim_sulama`, `tarim_havalandirma`.

## Kurulum (Raspberry Pi)

```bash
mkdir -p ~/.config/iot-hub
scp -r hub-api kutay@<PI_IP>:~/
ssh kutay@<PI_IP>
cd ~/hub-api
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cp .env.example ~/.config/iot-hub/.env
# ~/.config/iot-hub/.env içinde INFLUX_TOKEN ve isteğe bağlı GEMINI_API_KEY doldur
```

Çalıştır:

```bash
cd ~/hub-api
.venv/bin/uvicorn main:app --host 0.0.0.0 --port 5000
```

## systemd

```bash
sudo cp ~/hub-api/iot-hub-api.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now iot-hub-api
sudo systemctl status iot-hub-api
```

## Ortam değişkenleri

| Değişken | Varsayılan | Açıklama |
|----------|------------|----------|
| `GEMINI_API_KEY` | (boş) | Boşsa kural tabanlı analiz |
| `GEMINI_MODEL` | `gemini-2.0-flash` | Gemini model adı |
| `INFLUX_URL` | `http://localhost:8086` | InfluxDB 2.x URL |
| `INFLUX_TOKEN` | (boş) | Zorunlu (history/analyze için) |
| `INFLUX_ORG` | `iot-hub` | |
| `INFLUX_BUCKET` | `iot_telemetry` | |
| `INFLUX_MEASUREMENT` | `telemetry` | Line protocol measurement |
| `MQTT_BROKER` | `127.0.0.1` | Yerel Mosquitto |
| `MQTT_PORT` | `1883` | |
| `API_HOST` | `0.0.0.0` | |
| `API_PORT` | `5000` | |
| `IOT_HUB_ENV_FILE` | `~/.config/iot-hub/.env` | Env dosya yolu |

## API

### `GET /health`

Servis durumu ve yapılandırma özeti.

### `POST /analyze`

Son telemetri penceresini analiz eder.

```json
{
  "problem_id": "tarim_havalandirma",
  "takim_no": "8",
  "window_min": 15
}
```

Yanıt örneği:

```json
{
  "problem_id": "tarim_havalandirma",
  "takim_no": "8",
  "window_min": 15,
  "record_count": 42,
  "aksiyon": "fan_ac",
  "sure_sn": 120,
  "gerekce": "...",
  "source": "gemini"
}
```

`source`: `gemini` veya `fallback` (API anahtarı yok / Gemini hatası).

### `GET /history/{problem_id}/{takim_no}?minutes=15`

InfluxDB'den son kayıtlar. Tag'ler: `problem_id`, `takim_no`, `sensor`. Alanlar: `sicaklik`, `nem`, `hava_kalitesi`.

### `POST /command`

MQTT komut yayınlar (`{problem_id}/{takim_no}/command`).

```json
{
  "problem_id": "tarim_havalandirma",
  "takim_no": "8",
  "aksiyon": "fan_ac",
  "sure_sn": 120
}
```

## InfluxDB line protocol örneği

```
telemetry,problem_id=tarim_havalandirma,takim_no=8,sensor=dht11 sicaklik=26.4,nem=58.2,hava_kalitesi=72
```
