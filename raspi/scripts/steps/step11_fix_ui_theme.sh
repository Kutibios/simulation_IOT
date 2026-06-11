#!/usr/bin/env bash
# ui_base themeState tamamlanmazsa dashboard 'reading value/sy' hatasi verir.
set -euo pipefail
PW="${SUDO_PW:-kutay123}"
log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== STEP 11: ui_base theme tam onarim ==="
python3 << 'PYEOF'
import json
from pathlib import Path

THEME_STATE = {
    "base-color": {"default": "#0094CE", "value": "#0094CE", "edited": False},
    "page-titlebar-backgroundColor": {"value": "#0094CE", "edited": False},
    "page-backgroundColor": {"value": "#fafafa", "edited": False},
    "page-sidebar-backgroundColor": {"value": "#ffffff", "edited": False},
    "group-textColor": {"value": "#1bbfff", "edited": False},
    "group-borderColor": {"value": "#ffffff", "edited": False},
    "group-backgroundColor": {"value": "#ffffff", "edited": False},
    "widget-textColor": {"value": "#111111", "edited": False},
    "widget-backgroundColor": {"value": "#0094ce", "edited": False},
    "widget-borderColor": {"value": "#ffffff", "edited": False},
    "base-font": {
        "value": "-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Oxygen-Sans,Ubuntu,Cantarell,Helvetica Neue,sans-serif"
    },
}
SIZES = {"sx": 48, "sy": 48, "gx": 6, "gy": 6, "cx": 6, "cy": 6, "px": 0, "py": 0}

path = Path.home() / ".node-red/flows.json"
flows = json.loads(path.read_text())
for node in flows:
    if node.get("type") != "ui_base":
        continue
    theme = node.setdefault("theme", {})
    theme["name"] = "theme-light"
    theme.setdefault("lightTheme", {
        "default": "#0094CE", "baseColor": "#0094CE",
        "baseFont": "-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Oxygen-Sans,Ubuntu,Cantarell,Helvetica Neue,sans-serif",
        "edited": False,
    })
    theme.setdefault("darkTheme", {
        "default": "#097479", "baseColor": "#097479",
        "baseFont": "-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Oxygen-Sans,Ubuntu,Cantarell,Helvetica Neue,sans-serif",
        "edited": False,
    })
    theme.setdefault("customTheme", {
        "name": "Untitled Theme 1", "default": "#4B7930", "baseColor": "#4B7930",
        "baseFont": "-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,Oxygen-Sans,Ubuntu,Cantarell,Helvetica Neue,sans-serif",
    })
    theme["themeState"] = THEME_STATE
    theme.setdefault("angularTheme", {
        "primary": "indigo", "accents": "blue", "warn": "red", "background": "grey", "palette": "light",
    })
    site = node.setdefault("site", {})
    site.setdefault("name", "IoT Hub Dashboard")
    site.setdefault("hideToolbar", "false")
    site.setdefault("allowSwipe", "false")
    site.setdefault("lockMenu", "false")
    site.setdefault("allowTempTheme", "true")
    site.setdefault("dateFormat", "DD/MM/YYYY")
    site["sizes"] = SIZES
    print("  ui_base themeState tamamlandi")

path.write_text(json.dumps(flows, indent=4, ensure_ascii=False) + "\n")
PYEOF

echo "${PW}" | sudo -S systemctl restart nodered
sleep 5
curl -sf -o /dev/null http://127.0.0.1:1880/ui/ && log "  /ui OK" || log "  UYARI: /ui"
log "=== STEP 11 BITTI ==="
