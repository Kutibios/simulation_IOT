# BLM-0482 IoT simülasyonu (MQTT + SQLite + Dash)

Publisher periyodik telemetry üretir; Mosquitto üzerinden `{TEAM_NO}/telemetry` konusuna yayınlar. Subscriber mesajları dinler, SQLite’a yazar; Dash paneli grafik ve istatistikleri gösterir.

## Hızlı kurulum

```bash
docker compose up -d --build
```

- Panel: [http://localhost:8050](http://localhost:8050)
- MQTT: `localhost:1883`

Durdurmak:

```bash
docker compose down
```

Veritabanı volume’unu da silmek:

```bash
docker compose down -v
```

[Task](https://taskfile.dev/) kullanıyorsanız: `task up`, `task down`, `task logs`.

## Yapılandırma

`docker-compose.yml` içinde `TEAM_NO` ödevdeki `takim_no/telemetry` ile aynı olmalı (varsayılan `7`). Diğer ortam değişkenleri:

| Değişken | Açıklama | Varsayılan |
|----------|----------|------------|
| `TEAM_NO` | MQTT topic `TEAM_NO/telemetry` | `7` |
| `MQTT_BROKER` | Broker host adı | `mosquitto` |
| `MQTT_PORT` | Broker portu | `1883` |
| `PUBLISH_INTERVAL_SEC` | Yayın aralığı (saniye) | `5` |
| `SQLITE_PATH` | SQLite dosyası (subscriber) | `/data/telemetry.db` |

## Proje yapısı

- `publisher/` — simüle sensör verisi + MQTT publish
- `subscriber/` — MQTT subscribe, SQLite, `dashboard.py` + `assets/dashboard.css`
- `mosquitto/` — broker yapılandırması

Arayüz stilleri `subscriber/assets/dashboard.css` dosyasındadır; Python tarafında yalnızca Plotly grafik renkleri ve tema sınıfları kullanılır.

## Teslim raporu (e-kampus) — önerilen bölümler

Ödev PDF’i teknik tanımdır; değerlendirme raporu ayrı teslim edilir. Raporda şunları netleştirmeniz faydalıdır:

1. **Takım ve konu** — MQTT topic adı (`takim_no/telemetry`), kullanılan takım numarası  
2. **Mimari** — Publisher → Mosquitto → Subscriber → SQLite → Dash; Docker ile servisler  
3. **Veri formatı** — Örnek JSON (sıcaklık, nem, ışık, `timestamp`)  
4. **Veritabanı** — Tablo şeması, nereye yazıldığı  
5. **Panel** — Ekran görüntüleri (klasik + Grafana teması); min/max/ortalama/varyans  
6. **Çalıştırma** — `docker compose` adımları, erişim URL’leri  
7. **Sonuç** — Kısıtlar, olası geliştirmeler (ör. gerçek Grafana, ağ güvenliği)

## Proje anlatımı PDF’i

Kısa özet + mimari şema (**`docs/generate_mimari_diagram.py`** ile otomatik üretilen `mimari_akis.png`) + panel ekran görüntüleri: `docs/BLM0482_IoT_Simulasyon_Proje_Analatimi.pdf`

PDF üretirken diyagram yeniden çizilir; gerekirse: `.venv_pdf/bin/pip install matplotlib`

Önce stack’i çalıştır (`docker compose up -d`), sonra (Playwright kurulu olmalı):

```bash
python3 -m venv .venv_pdf
.venv_pdf/bin/pip install fpdf2 pypdf playwright matplotlib
.venv_pdf/bin/playwright install chromium
.venv_pdf/bin/python docs/capture_panel_screens.py
.venv_pdf/bin/python docs/build_rapor_pdf.py
```

## Lisans / kaynak

Orijinal depo: [Kutibios/simulation_IOT](https://github.com/Kutibios/simulation_IOT). Bu çatallama/klon iyileştirmeleri yerel geliştirme klasörüne göre uygulanmıştır.
