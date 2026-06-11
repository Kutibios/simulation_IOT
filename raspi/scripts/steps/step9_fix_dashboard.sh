#!/usr/bin/env bash
# ui_base.site.sizes eksikse dashboard beyaz ekran + 'reading sy' hatası verir.
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 9: Dashboard ui_base düzelt ==="
python3 << 'PYEOF'
import json
from pathlib import Path

flows_path = Path.home() / ".node-red/flows.json"
flows = json.loads(flows_path.read_text())
fixed = False
for node in flows:
    if node.get("type") != "ui_base":
        continue
    site = node.setdefault("site", {})
    site.setdefault("name", "IoT Hub Dashboard")
    site.setdefault("hideToolbar", "false")
    site.setdefault("allowSwipe", "false")
    site.setdefault("lockMenu", "false")
    site.setdefault("allowTempTheme", "true")
    site.setdefault("dateFormat", "DD/MM/YYYY")
    if "sizes" not in site or not isinstance(site.get("sizes"), dict):
        site["sizes"] = {
            "sx": 48, "sy": 48, "gx": 6, "gy": 6,
            "cx": 6, "cy": 6, "px": 0, "py": 0,
        }
        fixed = True
    theme = node.setdefault("theme", {})
    theme.setdefault("name", "theme-light")
    theme.setdefault("angularTheme", {
        "primary": "indigo", "accents": "blue", "warn": "red",
        "background": "grey", "palette": "light",
    })
    fixed = True

if not fixed:
    print("  ui_base bulunamadı")
else:
    flows_path.write_text(json.dumps(flows, indent=4, ensure_ascii=False) + "\n")
    print("  ui_base.site.sizes eklendi")
PYEOF

echo "${PW}" | sudo -S systemctl restart nodered
sleep 5
curl -sf -o /dev/null http://127.0.0.1:1880/ui/ && log "  /ui OK" || log "  UYARI: /ui"
log "=== STEP 9 BİTTİ ==="
