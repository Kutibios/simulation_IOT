#!/usr/bin/env python3
"""BLM-0482 — kısa proje özeti PDF (Türkçe, ekran görüntülü + akış şeması)."""

from __future__ import annotations

from pathlib import Path

from fpdf import FPDF

HERE = Path(__file__).resolve().parent
FONT_REG = HERE / "fonts" / "DejaVuSans.ttf"
FONT_BOLD = HERE / "fonts" / "DejaVuSans-Bold.ttf"
IMG_KLASIK = HERE / "screenshots" / "panel_klasik.png"
IMG_GRAFANA = HERE / "screenshots" / "panel_grafana.png"
IMG_MIMARI = HERE / "mimari_akis.png"
OUT = HERE / "BLM0482_IoT_Simulasyon_Proje_Analatimi.pdf"


def uret_mimari_grafik() -> None:
    """matplotlib ile mimari_akis.png üretir (yapıştırma görseli gerekmez)."""
    gen = HERE / "generate_mimari_diagram.py"
    if not gen.is_file():
        return
    import subprocess
    import sys

    subprocess.run(
        [sys.executable, str(gen)],
        cwd=str(HERE),
        check=False,
    )


class RaporPDF(FPDF):
    def footer(self) -> None:
        self.set_y(-12)
        self.set_font("DejaVu", "", 9)
        self.set_text_color(60, 60, 60)
        self.cell(0, 8, f"Sayfa {self.page_no()}", align="C")


def baslik(pdf: FPDF, metin: str, boyut: int = 13) -> None:
    pdf.ln(3)
    pdf.set_font("DejaVu", "B", boyut)
    pdf.set_text_color(25, 25, 25)
    pdf.multi_cell(0, 7, metin)
    pdf.ln(1)


def paragraf(pdf: FPDF, metin: str) -> None:
    pdf.set_font("DejaVu", "", 10.5)
    pdf.set_text_color(30, 30, 30)
    pdf.multi_cell(0, 5.8, metin)
    pdf.ln(2)


def resim(pdf: FPDF, yol: Path, alt_yazi: str) -> None:
    if not yol.is_file():
        paragraf(pdf, f"[Ekran görüntüsü eksik: {yol.name} — önce docs/capture_panel_screens.py çalıştırın.]")
        return
    pdf.set_font("DejaVu", "", 9)
    pdf.set_text_color(55, 55, 55)
    pdf.multi_cell(0, 5, alt_yazi)
    pdf.ln(1)
    pdf.image(str(yol), x=18, w=175)
    pdf.ln(4)


def mimari_sema_kompakt(pdf: FPDF) -> None:
    """Referans mimari görseli — sayfada küçük ayak izi (mm genişlik sınırlı)."""
    baslik(pdf, "Şekil 3 — Mimari akış (özet)")
    if not IMG_MIMARI.is_file():
        paragraf(
            pdf,
            "Şema görseli oluşturulamadı. `pip install matplotlib` sonrası "
            "`python docs/generate_mimari_diagram.py` çalıştırın.",
        )
        return
    # Diyagram genişledi; PDF’te biraz daha yer açıyoruz
    w_mm = 122
    x0 = 18 + (175 - w_mm) / 2
    pdf.image(str(IMG_MIMARI), x=x0, w=w_mm)
    pdf.ln(2)
    pdf.set_font("DejaVu", "", 8)
    pdf.set_text_color(65, 65, 75)
    pdf.multi_cell(
        175,
        3.8,
        "Yayıncı JSON ile MQTT yayımlar (ör. 7/telemetry); Mosquitto iletir; abone parse edip "
        "telemetry.db dosyasına yazar (/data volume); dashboard aynı veritabanından okuyup "
        "localhost:8050 adresinde gösterir.",
    )
    pdf.ln(2)


def main() -> None:
    if not FONT_REG.exists() or not FONT_BOLD.exists():
        raise SystemExit(f"Font yok: {FONT_REG}")

    uret_mimari_grafik()

    pdf = RaporPDF()
    pdf.set_auto_page_break(auto=True, margin=18)
    pdf.set_margins(18, 16, 18)
    pdf.add_font("DejaVu", "", str(FONT_REG))
    pdf.add_font("DejaVu", "B", str(FONT_BOLD))
    pdf.add_page()

    pdf.set_font("DejaVu", "B", 17)
    pdf.set_text_color(20, 20, 20)
    pdf.multi_cell(0, 8, "BLM-0482 IoT Simülasyonu\nKısa Proje Özeti")
    pdf.ln(4)

    baslik(pdf, "Nasıl yaptık?")
    paragraf(
        pdf,
        "Ödevde istenen akışı kurduk: sahte sensör verisi üreten bir program bunu MQTT ile "
        "yayımlıyor; başka bir program aynı kanaldan dinleyip veritabanına yazıyor. "
        "Üste ek olarak bu verileri tarayıcıda grafik ve sayılar halinde gösteren küçük bir panel var. "
        "Hepsini bilgisayarda Docker ile toplu çalıştırdık, böylece kurulum tek tip oldu.",
    )
    paragraf(
        pdf,
        "Panelde iki görünüm var: biri daha sade (Klasik), diğeri izleme arayüzlerine benzeyen koyu tema "
        "(Grafana tarzı; ayrı sunucu değil, sadece benzer görünüm). Aşağıda hem çalışma mantığı şeması "
        "hem de bu iki ekranın görüntüsü yer alıyor.",
    )

    baslik(pdf, "Üç sensör: neler ölçülüyor?")
    paragraf(
        pdf,
        "Ödev PDF’inde telemetry içinde üç nicelik isteniyor; bizim simülasyonda bunlar tek bir "
        "JSON mesajında birlikte gidiyor ve panelde her biri için ayrı grafik çiziliyor. Gerçek "
        "kart veya sensör yok; değerler programla üretiliyor, ama akış gerçek MQTT ile aynı mantıkta.",
    )
    paragraf(
        pdf,
        "Sıcaklık (°C): ortamın ne kadar sıcak olduğuna karşılık gelir; konfor, iklim veya basit "
        "alarm senaryolarında kullanılır. Nem (%): havadaki nem oranı; depolama, tarım veya iç ortam "
        "izlemede anlamlıdır. Işık (lüks veya kısaca lx): ortamdaki ışık düzeyi; günışığı, lamba "
        "ayarı veya otomasyon tetikleri için örneklenir. Üçü de zamanla değiştiği için grafikler "
        "“canlı eğri” gibi görünür; panelde her birinin yanında en düşük, en yüksek, ortalama ve "
        "varyans da gösterilir.",
    )

    baslik(pdf, "Nasıl çalıştırdık?")
    paragraf(
        pdf,
        "Proje klasöründe Docker açıkken: docker compose up -d --build. "
        "Tarayıcıdan localhost:8050 adresine giriyorsun. Durdurmak için docker compose down.",
    )

    baslik(pdf, "Docker’ı nasıl yapılandırdık?")
    paragraf(
        pdf,
        "Tek bir docker-compose dosyasında üç hizmet tanımlı. Birinci hizmet Mosquitto: MQTT "
        "aracıyı (broker) çalıştırır ve bilgisayarda 1883 portunu dışarı açar. Yapılandırma dosyası "
        "mosquitto klasöründen konteynıra bağlanır; böylece broker davranışını oradan yönetiyoruz.",
    )
    paragraf(
        pdf,
        "İkinci hizmet yayıncı (publisher): kendi Dockerfile’ı ile oluşturulan küçük bir Python "
        "ortamı. Mosquitto ayağa kalktıktan sonra başlar; takım numarası ve broker adresi ortam "
        "değişkeniyle verilir (örnek takım 7 ise kanal 7/telemetry olur). Yayın sıklığı da saniye "
        "cinsinden ayarlanabilir.",
    )
    paragraf(
        pdf,
        "Üçüncü hizmet abone ve panel (subscriber): yine özel imaj; içinde hem MQTT dinleyicisi "
        "hem web sunucusu çalışır. Dışarıya 8050 portu açılır; tarayıcı bu porta bağlanır. "
        "Veritabanı dosyası konteynır içinde /data altında tutulur ve Docker volume ile kalıcı "
        "yapılır: konteynırlar silinse bile volume’u silmediğin sürece kayıtlar kalır. "
        "Üç konteynır da aynı Docker ağında; birbirlerine servis adıyla erişirler, bu yüzden "
        "adres olarak “mosquitto” yazmak yeterli olur.",
    )

    pdf.add_page()
    baslik(pdf, "Çalışma mantığı")
    paragraf(
        pdf,
        "Sistem döngüyle işler. Yayıncı belirlediğimiz süre aralığında (örneğin birkaç saniyede bir) "
        "sıcaklık, nem ve ışık değerlerini tek bir JSON paketinde toplayıp MQTT kanalına gönderir. "
        "Kanal adı takım numarasına göre ayarlanır (ör. 7/telemetry); yayın ve dinleme aynı ismi kullanmalı.",
    )
    paragraf(
        pdf,
        "Mosquitto aracı rolünde: gelen mesajı ilgili konuya abone olan herkese iletir. "
        "Abone program mesajı alır, içindeki sayıları çözüp SQLite dosyasındaki tabloya ekler. "
        "Böylece geçmiş ölçümler diskte birikir.",
    )
    paragraf(
        pdf,
        "Web paneli başka bir süreç olarak çalışır ama aynı SQLite dosyasını okur. "
        "Zaman serisi grafikleri bu tablodaki satırlardan çizilir; min, max, ortalama ve varyans da "
        "aynı sütunlardan hesaplanır. Panel periyodik yenilenir; yeni satır geldikçe eğriler uzar.",
    )

    mimari_sema_kompakt(pdf)

    pdf.add_page()
    baslik(pdf, "Klasik panel")
    resim(
        pdf,
        IMG_KLASIK,
        "Şekil 1. Klasik görünüm: üç sensör grafiği ve yanında özet istatistikler.",
    )

    pdf.add_page()
    baslik(pdf, "Grafana tarzı panel")
    resim(
        pdf,
        IMG_GRAFANA,
        "Şekil 2. Grafana tarzı görünüm: aynı veri, koyu arayüz.",
    )

    pdf.output(OUT)
    print(f"Yazıldı: {OUT}")


if __name__ == "__main__":
    main()
