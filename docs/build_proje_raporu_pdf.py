#!/usr/bin/env python3
"""
BLM-0482 — Raspberry Pi IoT Hub Akademik Proje Raporu (PDF).

  python docs/build_proje_raporu_pdf.py
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from fpdf import FPDF

try:
    from PIL import Image
except ImportError:
    Image = None  # type: ignore[misc, assignment]

HERE = Path(__file__).resolve().parent
FONT_REG = HERE / "fonts" / "DejaVuSans.ttf"
FONT_BOLD = HERE / "fonts" / "DejaVuSans-Bold.ttf"
OUT = HERE / "BLM0482_IoT_Hub_Proje_Raporu.pdf"

IMG_MIMARI = HERE / "hub_mimari.png"
IMG_SULAMA = HERE / "grafik_sulama.png"
IMG_HAVA = HERE / "grafik_havalandirma.png"
IMG_AKIS = HERE / "grafik_akis_dongusu.png"
IMG_DASHBOARD = HERE / "screenshots" / "dashboard_ui.png"
IMG_NR_TEL = HERE / "screenshots" / "nodered_telemetry_flow.png"
IMG_NR_YZ = HERE / "screenshots" / "nodered_yz_flow.png"

YAZARLAR = [
    ("Yusuf Mert Özkul", "21360859057", False),
    ("Levent Kutay Sezer", "22360859013", True),
    ("Erva Aygüneş", "22360859027", False),
    ("Zeynep Erarslan", "22360859019", False),
]

# Akademik tipografi
BODY = 11
BODY_LH = 6.0
H1 = 14
H2 = 12
H3 = 11
CAPTION = 9.5
M_L, M_R, M_T, M_B = 25, 25, 20, 22

C_TEXT = (25, 25, 30)
C_MUTED = (70, 70, 80)
C_HEADER = (15, 45, 95)
C_TABLE_HEAD = (240, 244, 248)
C_TABLE_BORDER = (180, 190, 200)

_sekil_no = 0
_bolum_baslik = ""

# Sayfa kırılımı: en az bu kadar satır kalmadan paragraf bölünmesin
MIN_KALAN_MM = BODY_LH * 4
MIN_BASLIK_DEVAMI_MM = 18


def icerik_genisligi(pdf: FPDF) -> float:
    return pdf.w - pdf.l_margin - pdf.r_margin


def kalan_y(pdf: FPDF) -> float:
    return pdf.page_break_trigger - pdf.get_y()


def sayfa_yeterli(pdf: FPDF, yukseklik: float) -> bool:
    return pdf.get_y() + yukseklik <= pdf.page_break_trigger + 0.1


def yeni_sayfa_gerekirse(pdf: FPDF, yukseklik: float) -> None:
    if not sayfa_yeterli(pdf, yukseklik):
        pdf.add_page()


def metin_yuksekligi(
    pdf: FPDF,
    metin: str,
    *,
    font: str = "DejaVu",
    stil: str = "",
    boyut: float = BODY,
    satir: float = BODY_LH,
    genislik: float | None = None,
    hiza: str = "J",
) -> float:
    w = genislik if genislik is not None else icerik_genisligi(pdf)
    pdf.set_font(font, stil, boyut)
    return float(
        pdf.multi_cell(w, satir, metin, align=hiza, dry_run=True, output="HEIGHT")
    )


def gorsel_yukseklik(yol: Path, genislik_mm: float) -> float:
    if Image is None:
        return genislik_mm * 0.55
    with Image.open(yol) as im:
        return genislik_mm * (im.height / im.width)


def paragraf_bolumleri(metin: str) -> list[str]:
    """Paragrafı cümle gruplarına böl — sayfa sonunda tek satır kalmasın."""
    import re

    cumleler = re.split(r"(?<=[.;:])\s+", metin.strip())
    if len(cumleler) <= 2:
        return [metin]
    gruplar: list[str] = []
    buf: list[str] = []
    for c in cumleler:
        buf.append(c)
        if len(buf) >= 2:
            gruplar.append(" ".join(buf))
            buf = []
    if buf:
        if gruplar:
            gruplar[-1] = gruplar[-1] + " " + " ".join(buf)
        else:
            gruplar.append(" ".join(buf))
    return gruplar


def uret_gorseller() -> None:
    for script in ("generate_hub_mimari_diagram.py", "generate_ornek_grafikler.py"):
        p = HERE / script
        if p.is_file():
            subprocess.run([sys.executable, str(p)], cwd=str(HERE), check=False)


class RaporPDF(FPDF):
    def header(self) -> None:
        if self.page_no() <= 1:
            return
        self.set_font("DejaVu", "B", 8.5)
        self.set_text_color(*C_MUTED)
        self.cell(0, 6, "BLM-0482  |  Akıllı Sistemler Yönetim Birimi (IoT Hub)", align="L")
        self.ln(1)
        self.set_draw_color(*C_TABLE_BORDER)
        self.line(M_L, self.get_y(), self.w - M_R, self.get_y())
        self.ln(4)

    def footer(self) -> None:
        self.set_y(-14)
        self.set_draw_color(*C_TABLE_BORDER)
        self.line(M_L, self.get_y(), self.w - M_R, self.get_y())
        self.ln(2)
        self.set_font("DejaVu", "", 9)
        self.set_text_color(*C_MUTED)
        self.cell(0, 6, "Bursa Teknik Üniversitesi — Nesnelerin İnterneti", align="L")
        self.cell(0, 6, f"Sayfa {self.page_no()}", align="R")


def bolum(pdf: FPDF, metin: str) -> None:
    global _bolum_baslik
    _bolum_baslik = metin
    pdf.set_font("DejaVu", "B", H1)
    baslik_h = metin_yuksekligi(pdf, metin, stil="B", boyut=H1, satir=7.5, hiza="L")
    gerekli = 4 + baslik_h + 5 + MIN_BASLIK_DEVAMI_MM
    yeni_sayfa_gerekirse(pdf, gerekli)
    pdf.ln(4)
    pdf.set_text_color(*C_HEADER)
    pdf.multi_cell(0, 7.5, metin)
    pdf.set_draw_color(*C_HEADER)
    y = pdf.get_y()
    pdf.line(M_L, y, pdf.w - M_R, y)
    pdf.ln(5)


def alt_bolum(pdf: FPDF, metin: str) -> None:
    pdf.set_font("DejaVu", "B", H2)
    baslik_h = metin_yuksekligi(pdf, metin, stil="B", boyut=H2, satir=6.5, hiza="L")
    yeni_sayfa_gerekirse(pdf, 2 + baslik_h + 2 + MIN_BASLIK_DEVAMI_MM)
    pdf.ln(2)
    pdf.set_text_color(35, 35, 45)
    pdf.multi_cell(0, 6.5, metin)
    pdf.ln(2)


def alt_alt(pdf: FPDF, metin: str) -> None:
    pdf.set_font("DejaVu", "B", H3)
    baslik_h = metin_yuksekligi(pdf, metin, stil="B", boyut=H3, satir=6, hiza="L")
    yeni_sayfa_gerekirse(pdf, 1 + baslik_h + 1 + MIN_BASLIK_DEVAMI_MM)
    pdf.ln(1)
    pdf.set_text_color(45, 45, 55)
    pdf.multi_cell(0, 6, metin)
    pdf.ln(1)


def paragraf(pdf: FPDF, metin: str) -> None:
    pdf.set_font("DejaVu", "", BODY)
    pdf.set_text_color(*C_TEXT)
    w = icerik_genisligi(pdf)
    for parca in paragraf_bolumleri(metin):
        h = metin_yuksekligi(pdf, parca, boyut=BODY, satir=BODY_LH, genislik=w)
        kalan = kalan_y(pdf)
        sayfa_icerik = pdf.page_break_trigger - pdf.t_margin
        if h > kalan and (h <= sayfa_icerik or kalan < MIN_KALAN_MM):
            pdf.add_page()
        pdf.multi_cell(w, BODY_LH, parca, align="J")
        pdf.ln(2)


def madde(pdf: FPDF, metin: str) -> None:
    pdf.set_font("DejaVu", "", BODY)
    pdf.set_text_color(*C_TEXT)
    w = icerik_genisligi(pdf) - 4
    metin_full = f"–  {metin}"
    h = metin_yuksekligi(pdf, metin_full, boyut=BODY, satir=BODY_LH, genislik=w, hiza="L")
    yeni_sayfa_gerekirse(pdf, h + 0.8)
    pdf.set_x(pdf.l_margin + 4)
    pdf.multi_cell(w, BODY_LH, metin_full)
    pdf.ln(0.8)


def kod_blok(pdf: FPDF, metin: str) -> None:
    satirlar = metin.split("\n")
    h = len(satirlar) * 5.2 + 3
    yeni_sayfa_gerekirse(pdf, h)
    pdf.set_fill_color(248, 249, 251)
    pdf.set_draw_color(*C_TABLE_BORDER)
    pdf.set_font("DejaVu", "", 9.5)
    pdf.set_text_color(40, 40, 50)
    for line in satirlar:
        pdf.cell(0, 5.2, f"  {line}", border="LR", fill=True, new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 0, "", border="T")
    pdf.ln(3)


def tablo(pdf: FPDF, basliklar: list[str], satirlar: list[list[str]], widths: list[int]) -> None:
    satir_h = 7.5
    toplam_h = satir_h * (1 + len(satirlar)) + 3
    yeni_sayfa_gerekirse(pdf, toplam_h)

    pdf.set_font("DejaVu", "B", 9.5)
    pdf.set_fill_color(*C_TABLE_HEAD)
    pdf.set_draw_color(*C_TABLE_BORDER)
    pdf.set_text_color(30, 30, 40)
    for text, w in zip(basliklar, widths):
        pdf.cell(w, satir_h, text, border=1, fill=True)
    pdf.ln(satir_h)
    pdf.set_font("DejaVu", "", 9.5)
    for row in satirlar:
        yeni_sayfa_gerekirse(pdf, satir_h)
        if not sayfa_yeterli(pdf, satir_h):
            pdf.add_page()
            pdf.set_font("DejaVu", "B", 9.5)
            for text, w in zip(basliklar, widths):
                pdf.cell(w, satir_h, text, border=1, fill=True)
            pdf.ln(satir_h)
            pdf.set_font("DejaVu", "", 9.5)
        for text, w in zip(row, widths):
            pdf.cell(w, satir_h, text, border=1)
        pdf.ln(satir_h)
    pdf.ln(3)


def sekil(pdf: FPDF, yol: Path, aciklama: str, genislik: float = 160) -> None:
    global _sekil_no
    _sekil_no += 1
    no = _sekil_no
    if not yol.is_file():
        paragraf(pdf, f"[Şekil {no} üretilemedi: {yol.name}]")
        return

    kull_w = icerik_genisligi(pdf)
    w = min(genislik, kull_w)
    img_h = gorsel_yukseklik(yol, w)
    pdf.set_font("DejaVu", "I", CAPTION)
    cap_h = metin_yuksekligi(
        pdf, f"Şekil {no}. {aciklama}", stil="I", boyut=CAPTION, satir=4.8, hiza="C"
    )
    blok_h = 2 + img_h + 2 + cap_h + 4
    yeni_sayfa_gerekirse(pdf, blok_h)

    x = pdf.l_margin + (kull_w - w) / 2
    pdf.ln(2)
    pdf.image(str(yol), x=x, w=w)
    pdf.ln(2)
    pdf.set_text_color(*C_MUTED)
    pdf.multi_cell(0, 4.8, f"Şekil {no}. {aciklama}", align="C")
    pdf.ln(4)


def kapak(pdf: RaporPDF) -> None:
    pdf.add_page()
    pdf.ln(18)
    pdf.set_font("DejaVu", "B", 11)
    pdf.set_text_color(*C_HEADER)
    pdf.cell(0, 7, "BURSA TEKNİK ÜNİVERSİTESİ", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("DejaVu", "", 10.5)
    pdf.set_text_color(*C_MUTED)
    pdf.cell(0, 6, "Mühendislik ve Doğa Bilimleri Fakültesi", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, "BLM-0482 Nesnelerin İnterneti — IoT Simülasyon Projesi", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(16)
    pdf.set_draw_color(*C_HEADER)
    pdf.line(40, pdf.get_y(), pdf.w - 40, pdf.get_y())
    pdf.ln(14)
    pdf.set_font("DejaVu", "B", 20)
    pdf.set_text_color(15, 15, 20)
    pdf.multi_cell(0, 10, "Akıllı Sistemler Yönetim Birimi\n(IoT Hub) Proje Raporu", align="C")
    pdf.ln(10)
    pdf.set_font("DejaVu", "", 12)
    pdf.set_text_color(50, 50, 60)
    pdf.multi_cell(0, 7, "Raspberry Pi Tabanlı Merkezi IoT Yönetim,\nVeri Depolama ve Yapay Zeka Destekli Karar Sistemi", align="C")
    pdf.ln(14)
    pdf.line(40, pdf.get_y(), pdf.w - 40, pdf.get_y())
    pdf.ln(14)
    pdf.set_font("DejaVu", "B", 11)
    pdf.set_text_color(*C_TEXT)
    pdf.cell(0, 7, "Hazırlayanlar", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(3)
    pdf.set_font("DejaVu", "", 11)
    for ad, no, yildiz in YAZARLAR:
        ad_satir = f"{ad} *" if yildiz else ad
        pdf.cell(0, 6.5, f"{ad_satir}  —  {no}", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    pdf.set_font("DejaVu", "", 9)
    pdf.set_text_color(*C_MUTED)
    pdf.cell(0, 5, "* Proje sorumlusu", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.ln(18)
    pdf.set_font("DejaVu", "", 10.5)
    pdf.set_text_color(*C_MUTED)
    pdf.cell(0, 6, "Hazırlanma Tarihi: Haziran 2026", align="C", new_x="LMARGIN", new_y="NEXT")
    pdf.cell(0, 6, "Bursa — Türkiye", align="C")


def icindekiler(pdf: RaporPDF) -> None:
    pdf.add_page()
    bolum(pdf, "İçindekiler")
    maddeler = [
        ("1.", "Özet"),
        ("2.", "Giriş ve Proje Amacı"),
        ("3.", "Seçilen Alt Problemler"),
        ("4.", "Sistem Mimarisi"),
        ("5.", "Donanım Altyapısı"),
        ("6.", "Yazılım Bileşenleri ve Teknolojiler"),
        ("7.", "MQTT İletişim Protokolü"),
        ("8.", "Veritabanı Tasarımı"),
        ("9.", "Hub REST API ve Yapay Zeka Karar Motoru"),
        ("10.", "Node-RED Dashboard ve Otomasyon Akışları"),
        ("11.", "Uygulama Ekran Görüntüleri"),
        ("12.", "Veri Akışı ve Çalışma Mantığı"),
        ("13.", "Örnek Ölçüm Grafikleri"),
        ("14.", "Kurulum, Dağıtım ve Test"),
        ("15.", "Sonuç ve Değerlendirme"),
        ("16.", "Kaynakça"),
        ("Ek A", "Kaynak Kod Organizasyonu"),
    ]
    pdf.set_font("DejaVu", "", BODY)
    for no, bas in maddeler:
        pdf.set_text_color(*C_HEADER)
        pdf.cell(12, BODY_LH, no)
        pdf.set_text_color(*C_TEXT)
        pdf.cell(0, BODY_LH, bas, new_x="LMARGIN", new_y="NEXT")


def bolum_ozet(pdf: RaporPDF) -> None:
    bolum(pdf, "1. Özet")
    paragraf(
        pdf,
        "Bu rapor, Bursa Teknik Üniversitesi Nesnelerin İnterneti (BLM-0482) dersi kapsamında "
        "geliştirilen merkezi IoT yönetim birimini (hub) akademik biçimde sunmaktadır. Hub, "
        "Raspberry Pi üzerinde çalışarak farklı takımlardan gelen sensör telemetrilerini MQTT "
        "protokolü ile toplar; PostgreSQL veritabanında kalıcı olarak saklar; Node-RED "
        "dashboard üzerinde gerçek zamanlı görselleştirir; Google Gemini yapay zeka modeli "
        "ile analiz ederek sulama ve havalandırma sistemlerine MQTT komutları iletir.",
    )
    paragraf(
        pdf,
        "Projede iki alt problem üstlenilmiştir: Takım 7 tarım sulama (tarim_sulama) ve "
        "Takım 8 tarım havalandırma (tarim_havalandirma). Her iki senaryo standart JSON "
        "telemetri formatı ve {problem_id}/{takim_no}/telemetry topic yapısı ile hub'a "
        "bağlanır. Sistem; telemetri ingest, geçmiş sorgulama, eşik tabanlı YZ tetikleme "
        "ve periyodik analiz döngüsünü uçtan uca gerçekleştirmektedir.",
    )


def bolum_giris(pdf: RaporPDF) -> None:
    bolum(pdf, "2. Giriş ve Proje Amacı")
    paragraf(
        pdf,
        "Nesnelerin İnterneti (IoT), gömülü sensörler, kablosuz iletişim protokolleri ve "
        "edge/bulut bilişim bileşenlerinin bütünleşmesiyle fiziksel ortamın dijital "
        "sistemlere bağlanmasını ifade eder. Ders kapsamındaki simülasyon projesinde her "
        "takım belirli bir alt problem için sensör tabanlı uç cihaz geliştirir; merkezi hub "
        "ise tüm takımların verilerini toplayan, depolayan, görselleştiren ve gerektiğinde "
        "komut yayan yönetim katmanıdır.",
    )
    paragraf(
        pdf,
        "Projenin temel amacı, tarım IoT senaryosuna uygun uçtan uca bir mimari kurarak "
        "aşağıdaki yetenekleri göstermektir: çoklu takım desteği, standart MQTT topic "
        "yapısı, ilişkisel veritabanı ile zaman serisi depolama, web tabanlı canlı "
        "dashboard, yapay zeka destekli karar motoru ve MQTT üzerinden kapalı döngü otomasyon.",
    )
    alt_bolum(pdf, "2.1 Proje kapsamı")
    madde(pdf, "Merkezi hub yazılımının Raspberry Pi üzerinde kurulması ve yapılandırılması")
    madde(pdf, "İki alt problemin (sulama ve havalandırma) eşzamanlı yönetimi")
    madde(pdf, "Telemetri toplama, depolama, görselleştirme ve analiz pipeline'ı")
    madde(pdf, "Eşik ve periyodik tetiklemeli yapay zeka analizi")
    madde(pdf, "Komut yayınlama ile kapalı döngü otomasyon")


def bolum_alt_problemler(pdf: RaporPDF) -> None:
    bolum(pdf, "3. Seçilen Alt Problemler")
    paragraf(
        pdf,
        "IoT simülasyon projesi kapsamında sunulan alt problemler arasından hub olarak "
        "Tarım Sulama ve Tarım Havalandırma senaryoları seçilmiş; eşzamanlı desteklenecek "
        "şekilde yapılandırılmıştır.",
    )
    alt_bolum(pdf, "3.1 Takım 7 — Tarım Sulama (tarim_sulama)")
    paragraf(
        pdf,
        "Sulama alt problemi, tarım alanındaki ortam neminin izlenmesini ve buna göre "
        "sulama sisteminin kontrolünü hedefler. Takım 7 cihazında DS18B20 dijital "
        "sıcaklık sensörü ve DHT11 nem/sıcaklık sensörü kullanılmaktadır.",
    )
    tablo(
        pdf, ["Özellik", "Değer"],
        [
            ["problem_id", "tarim_sulama"],
            ["Takım no", "7"],
            ["MQTT telemetri", "tarim_sulama/7/telemetry"],
            ["MQTT komut", "tarim_sulama/7/command"],
            ["Sensörler", "DS18B20, DHT11"],
            ["Ölçülen değerler", "sicaklik, nem"],
            ["Komutlar", "sulama_ac, sulama_kapat"],
        ], [52, 118],
    )
    alt_bolum(pdf, "3.2 Takım 8 — Tarım Havalandırma (tarim_havalandirma)")
    paragraf(
        pdf,
        "Havalandırma alt problemi, sera ortamında sıcaklık, nem ve hava kalitesinin "
        "izlenmesini; fan sisteminin otomatik kontrolünü amaçlar. Takım 8 cihazında "
        "DHT11 ve MQ-135 hava kalitesi sensörü bulunur.",
    )
    tablo(
        pdf, ["Özellik", "Değer"],
        [
            ["problem_id", "tarim_havalandirma"],
            ["Takım no", "8"],
            ["MQTT telemetri", "tarim_havalandirma/8/telemetry"],
            ["MQTT komut", "tarim_havalandirma/8/command"],
            ["Sensörler", "DHT11, MQ-135"],
            ["Ölçülen değerler", "sicaklik, nem, hava_kalitesi"],
            ["Komutlar", "fan_ac, fan_kapat"],
        ], [52, 118],
    )


def bolum_mimari(pdf: RaporPDF) -> None:
    bolum(pdf, "4. Sistem Mimarisi")
    paragraf(
        pdf,
        "Sistem katmanlı bir edge computing mimarisi izler. Uç katmanda takım cihazları "
        "sensör okumalarını JSON formatında MQTT broker'a yayınlar. Edge katmanda "
        "Raspberry Pi üzerinde Mosquitto, mqtt_ingest, PostgreSQL, Node-RED ve FastAPI "
        "hub-api birlikte çalışır. Bulut katmanda Google Gemini API karar desteği sağlar.",
    )
    sekil(pdf, IMG_MIMARI, "Raspberry Pi IoT Hub genel sistem mimarisi")
    alt_bolum(pdf, "4.1 Mimari bileşenler")
    madde(pdf, "Mosquitto MQTT Broker (port 1883): Telemetri ve komut mesajlarının merkezi dağıtım noktası")
    madde(pdf, "mqtt_ingest.py: +/+/telemetry aboneliği ile JSON kayıtlarını PostgreSQL'e yazar")
    madde(pdf, "Node-RED: Canlı dashboard, veri ayırma, YZ tetikleme ve komut yayını")
    madde(pdf, "FastAPI hub-api (port 5000): REST arayüzü, geçmiş sorgulama ve analiz")
    madde(pdf, "PostgreSQL 17: Kalıcı telemetri deposu")
    madde(pdf, "Google Gemini 2.5 Flash: Telemetri analizi ve aksiyon önerisi")


def bolum_donanim(pdf: RaporPDF) -> None:
    bolum(pdf, "5. Donanım Altyapısı")
    paragraf(
        pdf,
        "IoT hub yazılımı Raspberry Pi single-board computer üzerinde çalıştırılmıştır. "
        "Kurulum sırasında cihazın 32-bit ARM (armv7l) mimarisinde olduğu tespit edilmiş; "
        "veritabanı seçiminde platform uyumluluğu gözetilmiştir.",
    )
    tablo(
        pdf, ["Donanım / Sistem", "Değer"],
        [
            ["Cihaz", "Raspberry Pi (IoT Hub sunucusu)"],
            ["İşlemci mimarisi", "ARM 32-bit (armv7l)"],
            ["İşletim sistemi", "Raspberry Pi OS (Debian tabanlı Linux)"],
            ["Disk kapasitesi", "29 GB (yaklaşık 21 GB kullanılabilir)"],
            ["Ağ", "Yerel ağ / hotspot"],
        ], [68, 102],
    )
    alt_bolum(pdf, "5.1 Sensör özellikleri")
    tablo(
        pdf, ["Sensör", "Tip", "Ölçüm"],
        [
            ["DS18B20", "Dijital (1-Wire)", "Sıcaklık (°C)"],
            ["DHT11", "Dijital", "Sıcaklık (°C), nem (%)"],
            ["MQ-135", "Analog", "Hava kalitesi indeksi"],
        ], [35, 42, 93],
    )


def bolum_yazilim(pdf: RaporPDF) -> None:
    bolum(pdf, "6. Yazılım Bileşenleri ve Teknolojiler")
    tablo(
        pdf, ["Bileşen", "Teknoloji", "Port / Servis"],
        [
            ["MQTT Broker", "Eclipse Mosquitto 2.x", ":1883"],
            ["Veritabanı", "PostgreSQL 17", ":5432"],
            ["Görselleştirme", "Node-RED + Dashboard 2.0", ":1880"],
            ["REST API", "FastAPI + Uvicorn", ":5000"],
            ["Veri ingest", "Python 3 + paho-mqtt", "iot-mqtt-ingest.service"],
            ["YZ motoru", "Google Gemini API", "gemini-2.5-flash"],
        ], [42, 58, 70],
    )
    alt_bolum(pdf, "6.1 PostgreSQL tercih gerekçesi")
    paragraf(
        pdf,
        "Başlangıçta InfluxDB 2 değerlendirilmiş; ancak 32-bit ARM mimarisinde resmi "
        "InfluxDB 2 arm64 paketinin çalışmadığı (systemd exit code 126) tespit edilmiştir. "
        "Bu nedenle telemetri depolama için PostgreSQL 17'ye geçilmiştir.",
    )


def bolum_mqtt(pdf: RaporPDF) -> None:
    bolum(pdf, "7. MQTT İletişim Protokolü")
    paragraf(
        pdf,
        "MQTT (Message Queuing Telemetry Transport), IoT uygulamalarında yaygın kullanılan "
        "hafif publish/subscribe mesajlaşma protokolüdür. Hub, Mosquitto broker üzerinden "
        "QoS 0 telemetri mesajlarını alır.",
    )
    tablo(
        pdf, ["Yön", "Topic kalıbı", "Örnek"],
        [
            ["Telemetri", "{problem_id}/{takim_no}/telemetry", "tarim_sulama/7/telemetry"],
            ["Komut", "{problem_id}/{takim_no}/command", "tarim_havalandirma/8/command"],
        ], [24, 72, 74],
    )
    alt_alt(pdf, "Telemetri JSON örneği")
    kod_blok(
        pdf,
        '{\n  "sensor": "dht11",\n  "sicaklik": 26.4,\n  "nem": 58.2,\n'
        '  "problem_id": "tarim_sulama",\n  "takim_no": "7"\n}',
    )


def bolum_veritabani(pdf: RaporPDF) -> None:
    bolum(pdf, "8. Veritabanı Tasarımı (PostgreSQL)")
    paragraf(
        pdf,
        "iot_telemetry veritabanında telemetry tablosu tüm sensör kayıtlarını tutar. "
        "mqtt_ingest servisi her geçerli MQTT mesajını INSERT eder; hub-api son N "
        "dakikalık kayıtları analiz için okur.",
    )
    tablo(
        pdf, ["Sütun", "Tip", "Açıklama"],
        [
            ["id", "SERIAL PK", "Birincil anahtar"],
            ["time", "TIMESTAMPTZ", "Kayıt zaman damgası"],
            ["problem_id", "TEXT", "Alt problem tanımlayıcı"],
            ["takim_no", "TEXT", "Takım numarası"],
            ["sensor", "TEXT", "Sensör adı"],
            ["sicaklik", "DOUBLE PRECISION", "Sıcaklık (°C)"],
            ["nem", "DOUBLE PRECISION", "Nem (%)"],
            ["hava_kalitesi", "DOUBLE PRECISION", "Hava kalitesi indeksi"],
        ], [38, 48, 84],
    )


def bolum_api(pdf: RaporPDF) -> None:
    bolum(pdf, "9. Hub REST API ve Yapay Zeka Karar Motoru")
    tablo(
        pdf, ["Metot", "Endpoint", "Açıklama"],
        [
            ["GET", "/health", "Servis ve yapılandırma durumu"],
            ["POST", "/analyze", "Telemetri analizi → aksiyon, sure_sn, gerekce"],
            ["GET", "/history/{pid}/{takim}", "Son N dakika telemetri"],
            ["POST", "/command", "MQTT komut yayınlama"],
        ], [20, 58, 92],
    )
    alt_bolum(pdf, "9.1 YZ analiz akışı")
    madde(pdf, "Node-RED her 60 saniyede veya eşik aşımında (nem>70, hava_kalitesi>400) /analyze çağırır")
    madde(pdf, "API son 15 dakikalık PostgreSQL kayıtlarını okur")
    madde(pdf, "Gemini modeline Türkçe prompt ile JSON aksiyon istenir")
    madde(pdf, "Yanıt dashboard'da gösterilir; aksiyon ≠ bekle ise MQTT command topic'ine yazılır")


def bolum_nodered(pdf: RaporPDF) -> None:
    bolum(pdf, "10. Node-RED Dashboard ve Otomasyon Akışları")
    paragraf(
        pdf,
        "Node-RED, hub'ın ETL ve otomasyon katmanını oluşturur. İki ana akış grubu "
        "bulunmaktadır: telemetri işleme akışı ve yapay zeka analiz/komut akışı.",
    )
    alt_bolum(pdf, "10.1 Telemetri işleme akışı")
    paragraf(
        pdf,
        "Tüm Telemetry MQTT input node'u +/+/telemetry kalıbına abonedir. Gelen JSON "
        "Veriyi Ayır (Hub) function node'u ile sensör tipine göre altı çıkışa yönlendirilir: "
        "DS18B20 sıcaklık gauge, DHT11 sıcaklık gauge, nem gauge, sıcaklık chart, nem chart "
        "ve hava kalitesi gauge. Paralel olarak Eşik → YZ Tetik node'u nem ve AQI eşiklerini "
        "kontrol eder.",
    )
    sekil(
        pdf, IMG_NR_TEL,
        "Node-RED telemetri işleme akışı — MQTT abonelik, JSON parse, veri ayırma ve dashboard widget'ları",
        168,
    )
    alt_bolum(pdf, "10.2 Yapay zeka analiz ve komut akışı")
    paragraf(
        pdf,
        "Her 60 sn inject node'u YZ İstek Oluştur function'ını tetikler; HTTP POST /analyze "
        "ile FastAPI'ye istek gönderilir. Yanıt YZ → Dashboard function'ı ile Sulama YZ ve "
        "Havalandırma YZ template widget'larına yönlendirilir. Command Oluştur node'u "
        "aksiyon ≠ bekle durumunda MQTT Command out ile komut yayınlar.",
    )
    sekil(
        pdf, IMG_NR_YZ,
        "Node-RED YZ analiz akışı — periyodik tetikleme, POST /analyze, dashboard ve MQTT komut",
        168,
    )


def bolum_ekran(pdf: RaporPDF) -> None:
    bolum(pdf, "11. Uygulama Ekran Görüntüleri")
    paragraf(
        pdf,
        "Node-RED Dashboard arayüzü http://<pi-ip>:1880/ui adresinden erişilir. Arayüz "
        "üç ana bölümden oluşur: Sulama (Takım 7), Havalandırma (Takım 8) ve AI Analiz.",
    )
    sekil(
        pdf, IMG_DASHBOARD,
        "Akıllı Sistemler dashboard — canlı gauge/chart göstergeleri ve Gemini YZ analiz kartları",
        168,
    )
    alt_bolum(pdf, "11.1 Dashboard gözlemleri")
    madde(pdf, "Sulama paneli: DS18B20 ve DHT11 sıcaklık gauge'ları, nem göstergesi ve zaman serisi grafikleri")
    madde(pdf, "Havalandırma paneli: sıcaklık, nem ve hava kalitesi (MQ-135) göstergeleri")
    madde(pdf, "AI Analiz: Takım 7 için bekle aksiyonu (nem %60–64 aralığında); Takım 8 için fan_ac (sıcaklık 28.4°C)")
    madde(pdf, "Gemini kaynaklı gerekçe metinleri Türkçe olarak dashboard kartlarında görüntülenir")


def bolum_veri_akisi(pdf: RaporPDF) -> None:
    bolum(pdf, "12. Veri Akışı ve Çalışma Mantığı")
    sekil(pdf, IMG_AKIS, "Telemetri–analiz–komut kapalı döngüsü")
    paragraf(
        pdf,
        "Sistem sürekli bir kapalı döngü olarak çalışır. Takım cihazları sensör okumalarını "
        "JSON telemetri mesajı halinde MQTT broker'a gönderir. Mosquitto mesajı hem Node-RED'e "
        "hem mqtt_ingest servisine iletir. FastAPI, PostgreSQL kayıtlarını Gemini ile analiz "
        "eder; Node-RED yanıtı dashboard'da gösterir ve gerekirse command topic'ine yazar.",
    )


def bolum_grafikler(pdf: RaporPDF) -> None:
    bolum(pdf, "13. Örnek Ölçüm Grafikleri")
    paragraf(
        pdf,
        "Hub'a iletilen telemetri kayıtlarından elde edilen tipik zaman serisi örnekleri "
        "aşağıda sunulmaktadır.",
    )
    sekil(pdf, IMG_SULAMA, "Takım 7 — sulama sensör ölçümleri (30 dakikalık pencere)")
    sekil(pdf, IMG_HAVA, "Takım 8 — havalandırma sensör ölçümleri (30 dakikalık pencere)")


def bolum_kurulum(pdf: RaporPDF) -> None:
    bolum(pdf, "14. Kurulum, Dağıtım ve Test")
    paragraf(
        pdf,
        "Hub kurulumu run_step.sh scriptleri ile SSH üzerinden adım adım uygulanmıştır. "
        "Tüm bileşenler systemd servisi olarak yapılandırılmıştır.",
    )
    tablo(
        pdf, ["Servis", "Açıklama"],
        [
            ["iot-hub-api.service", "FastAPI Uvicorn :5000"],
            ["iot-mqtt-ingest.service", "MQTT → PostgreSQL ingest"],
            ["mosquitto.service", "MQTT broker"],
            ["postgresql.service", "Veritabanı sunucusu"],
            ["nodered.service", "Node-RED runtime"],
        ], [55, 115],
    )
    alt_bolum(pdf, "14.1 Doğrulama testleri")
    madde(pdf, "GET /health → postgres_configured: true, gemini_configured: true")
    madde(pdf, "POST /analyze → source: gemini, aksiyon ve gerekce alanları")
    madde(pdf, "MQTT telemetri → PostgreSQL INSERT → /history sorgusu")
    madde(pdf, "Dashboard canlı gauge/chart ve YZ analiz kartı güncellemesi")


def bolum_sonuc(pdf: RaporPDF) -> None:
    bolum(pdf, "15. Sonuç ve Değerlendirme")
    paragraf(
        pdf,
        "Bu projede Bursa Teknik Üniversitesi Nesnelerin İnterneti dersi kapsamında "
        "Raspberry Pi tabanlı merkezi bir IoT hub başarıyla tasarlanmış ve uygulanmıştır. "
        "Hub; tarım sulama ve havalandırma alt problemlerini eşzamanlı yönetebilmekte; "
        "MQTT, PostgreSQL, Node-RED, FastAPI ve Google Gemini bileşenlerini bütünleşik "
        "biçimde kullanmaktadır.",
    )
    paragraf(
        pdf,
        "Projenin öne çıkan kazanımları: standart topic yapısı ile çoklu takım desteği, "
        "edge cihazda tam işlevli veri pipeline'ı, yapay zeka destekli karar mekanizması, "
        "web tabanlı gerçek zamanlı izleme paneli ve 32-bit ARM platformuna uygun "
        "veritabanı adaptasyonudur.",
    )


def bolum_kaynakca(pdf: RaporPDF) -> None:
    bolum(pdf, "16. Kaynakça")
    kaynaklar = [
        "MQTT Version 3.1.1 Specification, OASIS Standard, 2014.",
        "Eclipse Mosquitto Documentation. https://mosquitto.org/documentation/",
        "PostgreSQL 17 Documentation. https://www.postgresql.org/docs/",
        "Node-RED Documentation. https://nodered.org/docs/",
        "FastAPI Documentation. https://fastapi.tiangolo.com/",
        "Google Gemini API Documentation. https://ai.google.dev/",
        "Raspberry Pi Documentation. https://www.raspberrypi.com/documentation/",
        "DS18B20 Datasheet, Maxim Integrated.",
        "DHT11 Product Manual.",
        "MQ-135 Gas Sensor Datasheet, Hanwei Electronics.",
        "BLM-0482 IoT Simülasyon Projesi Ders Dokümanı, Bursa Teknik Üniversitesi.",
    ]
    pdf.set_font("DejaVu", "", 10)
    for i, k in enumerate(kaynaklar, 1):
        satir = f"[{i}]  {k}"
        h = metin_yuksekligi(pdf, satir, boyut=10, satir=5.5, hiza="L")
        yeni_sayfa_gerekirse(pdf, h)
        pdf.set_x(pdf.l_margin)
        pdf.multi_cell(0, 5.5, satir)


def bolum_ek_a(pdf: RaporPDF) -> None:
    bolum(pdf, "Ek A — Kaynak Kod Organizasyonu")
    tablo(
        pdf, ["Dizin / Dosya", "Görev"],
        [
            ["raspi/hub-api/", "FastAPI REST servisi"],
            ["raspi/hub-api/postgres_client.py", "PostgreSQL sorgu ve INSERT"],
            ["raspi/mqtt_ingest.py", "MQTT abone → veritabanı"],
            ["raspi/node-red/flows_hub_postgres.json", "Node-RED akış tanımı"],
            ["raspi/scripts/steps/", "Kurulum adımları (step0–11)"],
        ], [72, 98],
    )


def main() -> None:
    if not FONT_REG.exists():
        raise SystemExit(f"Font bulunamadı: {FONT_REG}")

    uret_gorseller()

    pdf = RaporPDF()
    pdf.set_auto_page_break(auto=True, margin=M_B + 4)
    pdf.set_margins(M_L, M_T, M_R)
    pdf.add_font("DejaVu", "", str(FONT_REG))
    pdf.add_font("DejaVu", "B", str(FONT_BOLD))
    pdf.add_font("DejaVu", "I", str(FONT_REG))  # italic approx

    kapak(pdf)
    icindekiler(pdf)
    bolum_ozet(pdf)
    bolum_giris(pdf)
    bolum_alt_problemler(pdf)
    bolum_mimari(pdf)
    bolum_donanim(pdf)
    bolum_yazilim(pdf)
    bolum_mqtt(pdf)
    bolum_veritabani(pdf)
    bolum_api(pdf)
    bolum_nodered(pdf)
    bolum_ekran(pdf)
    bolum_veri_akisi(pdf)
    bolum_grafikler(pdf)
    bolum_kurulum(pdf)
    bolum_sonuc(pdf)
    bolum_kaynakca(pdf)
    bolum_ek_a(pdf)

    pdf.output(OUT)
    print(f"Yazıldı: {OUT} ({pdf.page_no()} sayfa)")


if __name__ == "__main__":
    main()
