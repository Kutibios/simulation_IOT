#!/usr/bin/env python3
"""Panel ekran görüntüleri (Klasik + Grafana). Docker ayakta ve localhost:8050 açık olmalı."""

from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
OUT = HERE / "screenshots"
URL = "http://127.0.0.1:8050/"


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 900})
        page.goto(URL, wait_until="networkidle", timeout=60000)
        page.wait_for_timeout(4000)
        page.screenshot(path=str(OUT / "panel_klasik.png"), full_page=True)
        page.get_by_role("button", name="Grafana").click()
        page.wait_for_timeout(3500)
        page.screenshot(path=str(OUT / "panel_grafana.png"), full_page=True)
        browser.close()
    print("OK:", OUT / "panel_klasik.png", OUT / "panel_grafana.png")


if __name__ == "__main__":
    main()
