# IoT Hub — Node-RED Kurulum (Raspberry Pi)

Bu rehber `flows_hub_complete.json` akışını Pi üzerinde çalıştırmak içindir.

## Mimari özet

| Bileşen | Değer |
|---------|-------|
| MQTT topic | `{problem_id}/{takim_no}/telemetry` ve `/command` |
| Alt problemler | `tarim_sulama` (takım 7), `tarim_havalandirma` (takım 8) |
| InfluxDB | bucket `iot_telemetry`, measurement `telemetry` |
| FastAPI | `http://127.0.0.1:5000/analyze` |
| Dashboard | Node-RED UI (`/ui`) — Grafana yok |

## 1. Ön koşullar

Pi'de çalışan servisler:

```bash
sudo systemctl status mosquitto nodered influxdb
```

FastAPI hub servisi (ayrı kurulum):

```bash
# Örnek: ~/.config/iot-hub/.env içinde INFLUX_TOKEN, GEMINI_API_KEY
curl -s http://127.0.0.1:5000/health || echo "hub-api henüz ayakta değil"
```

## 2. node-red-contrib-influxdb kurulumu

Node-RED kullanıcı dizininde:

```bash
cd ~/.node-red
npm install node-red-contrib-influxdb
```

Kurulumdan sonra Node-RED'i yeniden başlatın:

```bash
sudo systemctl restart nodered
```

## 3. InfluxDB 2.x hazırlığı

InfluxDB'de org ve bucket oluşturun (henüz yoksa):

```bash
influx org create -n iot-hub
influx bucket create -n iot_telemetry -o iot-hub -r 30d
influx auth create --org iot-hub --read-buckets --write-buckets iot_telemetry
```

Oluşan **API token**'ı not edin.

## 4. Akış dosyalarını Pi'ye kopyala

Mac'ten (IP ve kullanıcıyı kendinize göre değiştirin):

```bash
scp -r ~/Desktop/iot/simulation_IOT/raspi/node-red/*.js kutay@172.20.10.5:~/iot-hub/node-red/
scp ~/Desktop/iot/simulation_IOT/raspi/node-red/flows_hub_complete.json kutay@172.20.10.5:~/.node-red/flows_hub_import.json
```

## 5. Mevcut flows yedekle

```bash
ssh kutay@172.20.10.5 'cp ~/.node-red/flows.json ~/.node-red/flows_backup_$(date +%Y%m%d).json'
```

## 6. Node-RED'e import

1. Tarayıcıda `http://<pi-ip>:1880` açın.
2. Menü (≡) → **Import** → **select a file to import**.
3. `flows_hub_complete.json` dosyasını seçin.
4. **Import to** → **new flow** (mevcut akışları silmeden eklemek için) veya tüm akışı değiştirmek istiyorsanız doğrudan `flows.json` yerine kopyalayın.

Alternatif — doğrudan `flows.json` olarak değiştir:

```bash
ssh kutay@172.20.10.5 'cp ~/.node-red/flows_hub_import.json ~/.node-red/flows.json && sudo systemctl restart nodered'
```

## 7. Import sonrası yapılandırma

### 7.1 InfluxDB config düğümü

Editor'de **InfluxDB 2.x (iot_telemetry)** config düğümünü açın:

| Alan | Değer |
|------|-------|
| URL | `http://127.0.0.1:8086` |
| Version | `2.0` |
| Organisation | `iot-hub` |
| Bucket | `iot_telemetry` |
| Token | InfluxDB API token |

### 7.2 MQTT broker (`broker1`)

| Alan | Değer |
|------|-------|
| Server | `localhost` veya `127.0.0.1` |
| Port | `1883` |
| Client ID | `nodered_hub` |

### 7.3 Function kodlarını güncelleme (isteğe bağlı)

Import sonrası function düğümlerinde kod gömülüdür. Harici `.js` dosyalarından güncellemek için ilgili düğümü açıp dosya içeriğini yapıştırın:

- `FUNCTION_VERIYI_AYIR_HUB.js`
- `FUNCTION_INFLUX_PREP.js`
- `FUNCTION_ANALYZE_TRIGGER.js`
- `FUNCTION_COMMAND_FROM_API.js`

## 8. Deploy

Sağ üst **Deploy** → tüm sekmeler yeşil olmalı.

Sekmeler:

1. **Telemetry** — MQTT telemetry → dashboard + InfluxDB
2. **YZ Analiz** — 60 sn periyot + eşik tetik → FastAPI → MQTT command
3. **Command Log** — gelen command mesajlarını debug

## 9. Dashboard

```
http://<pi-ip>:1880/ui
```

Sekme **Akıllı Sistemler** altında:

- **Sulama** — DS18B20, DHT11, nem gauge/chart (`tarim_sulama` mesajları)
- **Havalandırma** — aynı sensörler + hava kalitesi gauge (`tarim_havalandirma`)

## 10. Test

```bash
# Sulama — nem yüksek (eşik tetik: nem>70)
mosquitto_pub -h 127.0.0.1 -t 'tarim_sulama/7/telemetry' \
  -m '{"sensor":"dht11","sicaklik":26.0,"nem":75.0}'

# Havalandırma — hava kalitesi yüksek (eşik: >400)
mosquitto_pub -h 127.0.0.1 -t 'tarim_havalandirma/8/telemetry' \
  -m '{"sensor":"mq135","hava_kalitesi":450,"sicaklik":24.0,"nem":55.0}'

# DS18B20
mosquitto_pub -h 127.0.0.1 -t 'tarim_sulama/7/telemetry' \
  -m '{"sensor":"ds18b20","sicaklik":22.5}'
```

Debug panelinde:

- Telemetry sekmesi → ham JSON
- YZ Analiz → `/analyze` yanıtı ve oluşan command
- Command Log → `+/+/command` aboneliği

## 11. Akış yeniden üretme (geliştirme)

JS dosyalarını değiştirdikten sonra Mac'te:

```bash
cd ~/Desktop/iot/simulation_IOT/raspi/node-red
python3 _build_flows_hub.py
```

Ardından yeni `flows_hub_complete.json` dosyasını Pi'ye kopyalayıp tekrar import edin.

## Sorun giderme

| Belirti | Çözüm |
|---------|-------|
| InfluxDB düğümü kırmızı | `npm install node-red-contrib-influxdb` + token/org/bucket kontrol |
| Dashboard boş | `problem_id` switch'leri — topic `tarim_sulama/7/telemetry` formatında mı? |
| YZ command yok | FastAPI ayakta mı? `aksiyon: bekle` ise MQTT publish edilmez |
| Grafik legend uyumsuz | Chart serileri: `ds18b20`, `dht11`, `dht11_nem` |
