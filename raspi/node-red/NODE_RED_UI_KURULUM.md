# Node-RED UI — DS18B20 + DHT11

## Import neden çalışmıyor?

Node-RED **Import** yalnızca **`.json`** akış dosyalarını açar.

- `FUNCTION_VERIYI_AYIR.js` → **Import ile değil**, function düğümüne **yapıştır** veya `flow_import_veriyi_ayir.json` kullan.
- Klasör seçince **Aç** gri kalır; **dosya** seçmelisin.

Göstergeler çalışıp grafikler boşsa, genelde **chart seri adları** ile **function `msg.topic`** uyuşmuyordur.

## 1. `flows.json` yedek (Mac’ten)

```bash
mkdir -p ~/Desktop/iot/simulation_IOT/raspi
scp kutay@172.20.10.5:~/.node-red/flows.json ~/Desktop/iot/simulation_IOT/raspi/flows_backup.json
```

## 2. MQTT `mqtt in` ayarı

- **Topic:** `+/+/telemetry` (veya `tarim_sulama/+/telemetry`)
- **Broker:** `127.0.0.1:1883`

## 3. Mevcut flow’unda düzeltme (senin yapın)

Sorunlar:

1. **İki function var:** `Veriyi Ayır` (bağlı) + `Veriyi Ayır (DS18B20 + DHT11)` (bağsız, sil).
2. Eski kod `cihaz_id` ile chart topic atıyor → legend’da `sensor_1/2/3`, grafikler boş kalabiliyor.
3. Yeni kod **2 çıkış** kullanmalı (sıcaklık / nem hatları ayrı).

### Adımlar

1. **`Veriyi Ayır (DS18B20 + DHT11)`** düğümünü seç → **Delete** (bağlı değil).
2. **`Veriyi Ayır`** (`func1`) çift tık → kodu sil → `FUNCTION_VERIYI_AYIR.js` yapıştır.
3. **Outputs: 2** kalsın (değiştirme).
4. **Deploy**.
5. Dashboard’u yenile; eski chart legend temizlenmezse chart düğümünde **çöp kutusu / Clear chart data** (varsa) veya birkaç yeni test mesajı gönder.

### Tüm flow’u dosyadan değiştirmek (isteğe bağlı)

Mac’te yedek al, sonra Pi’ye kopyala:

```bash
scp kutay@172.20.10.5:~/.node-red/flows.json ~/Desktop/iot/simulation_IOT/raspi/flows_backup.json
scp ~/Desktop/iot/simulation_IOT/raspi/node-red/flows_flow1_fixed.json kutay@172.20.10.5:~/.node-red/flows.json
ssh kutay@172.20.10.5 'sudo systemctl restart nodered'
```

Önce mutlaka `flows_backup.json` al.

## 4. Chart (grafik) düğümlerini düzelt

Arkadaşın akışında legend’da `sensor_1`, `sensor_2`, `sensor_3` vardı — yeni sensör adlarıyla **değiştir**.

### Sıcaklık grafiği ("Sıcaklık Grafiği" / chart)

- **Lines / Series** listesine **sadece** şunları ekle (eski sensor_1/2/3 sil):
  - `ds18b20`
  - `dht11`
- X ekseni: zaman (varsayılan).

### Nem grafiği ("Nem Grafiği")

- **Series:** tek seri: `dht11`  
  (DHT11 nem verir; DS18B20 nem göndermez.)

### Gauge düğümleri

- **Sıcaklık gauge:** `msg.payload` sayı, topic şart değil (function `sicaklik_gauge` da gönderir; gauge genelde son payload’ı alır).
- **Nem gauge:** DHT11 mesajları geldikçe güncellenir.

İstersen gauge’leri function’dan **ayrı çıkışlara** bağla (2. çıkış sadece gauge) — şu an tek çıkış + `node.send` ile de çalışır.

## 5. Bağlantı şeması

```
mqtt in → json → debug
              → function (Veriyi Ayır) → sıcaklık gauge
                                    → nem gauge
                                    → sıcaklık chart
                                    → nem chart
```

Function **tek çıkış**; dört UI düğümü **aynı çıkışa** bağlı olabilir (Node-RED her mesajı kopyalar).

## 6. Test (Mac veya Pi)

```bash
# DS18B20 — sadece sıcaklık
mosquitto_pub -h 172.20.10.5 -p 1883 -t 'tarim_sulama/7/telemetry' \
  -m '{"sensor":"ds18b20","sicaklik":24.1}'

# DHT11 — sıcaklık + nem
mosquitto_pub -h 172.20.10.5 -p 1883 -t 'tarim_sulama/7/telemetry' \
  -m '{"sensor":"dht11","sicaklik":25.5,"nem":60.2}'
```

Dashboard: `http://172.20.10.5:1880/ui`

Birkaç saniye arayla 5–10 mesaj gönder; grafikler zaman ekseninde dolmaya başlar.

## 7. Gerçek sensörler (ESP / Pi publisher)

Publish ederken aynı topic + yukarıdaki JSON alanlarını kullanın:

| Sensör   | `sensor` alanı | Alanlar        |
|----------|----------------|----------------|
| DS18B20  | `ds18b20`      | `sicaklik`     |
| DHT11    | `dht11`        | `sicaklik`, `nem` |

Topic: `tarim_sulama/<takim_no>/telemetry`
