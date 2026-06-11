#!/usr/bin/env python3
"""Generate flows_hub_complete.json from JS function files."""
from __future__ import annotations

import json
from pathlib import Path

DIR = Path(__file__).parent


def read_js(name: str) -> str:
    return (DIR / name).read_text(encoding="utf-8")


THRESHOLD_FUNC = """const p = msg.payload;
if (!p || typeof p !== \"object\") {
    return null;
}

const topicParts = String(msg.topic || \"\").split(\"/\");
const problem_id = topicParts[0] || p.problem_id;
const takim_no = topicParts[1] || p.takim_no;

if (!problem_id || !takim_no) {
    return null;
}

let nem = p.nem;
let hava_kalitesi = p.hava_kalitesi;

if (p.values && typeof p.values === \"object\") {
    if (nem === undefined) nem = p.values.nem;
    if (hava_kalitesi === undefined) hava_kalitesi = p.values.hava_kalitesi;
}

let trigger = false;
let trigger_reason = \"\";

if (nem !== undefined && nem !== null && Number(nem) > 70) {
    trigger = true;
    trigger_reason = `nem>${70} (${Number(nem)})`;
}

if (hava_kalitesi !== undefined && hava_kalitesi !== null && Number(hava_kalitesi) > 400) {
    trigger = true;
    trigger_reason = trigger_reason
        ? `${trigger_reason}; hava_kalitesi>400 (${Number(hava_kalitesi)})`
        : `hava_kalitesi>400 (${Number(hava_kalitesi)})`;
}

if (!trigger) {
    return null;
}

msg.payload = {
    problem_id,
    takim_no,
    minutes: 15,
    trigger_reason
};
msg.problem_id = problem_id;
msg.takim_no = takim_no;
msg.url = \"http://127.0.0.1:5000/analyze\";
msg.method = \"POST\";
msg.headers = { \"content-type\": \"application/json\" };
return msg;"""


def switch_node(nid: str, z: str, name: str, x: int, y: int, wires: list) -> dict:
    return {
        "id": nid,
        "type": "switch",
        "z": z,
        "name": name,
        "property": "problem_id",
        "propertyType": "msg",
        "rules": [
            {"t": "eq", "v": "tarim_sulama", "vt": "str"},
            {"t": "eq", "v": "tarim_havalandirma", "vt": "str"},
        ],
        "checkall": "false",
        "repair": False,
        "outputs": 2,
        "x": x,
        "y": y,
        "wires": wires,
    }


def gauge(nid: str, z: str, name: str, group: str, order: int, title: str, label: str,
          min_v: int, max_v: int, seg1: int, seg2: int, colors: list, x: int, y: int) -> dict:
    return {
        "id": nid,
        "type": "ui_gauge",
        "z": z,
        "name": name,
        "group": group,
        "order": order,
        "width": 4,
        "height": 4,
        "gtype": "gage",
        "title": title,
        "label": label,
        "format": "{{value}}",
        "min": min_v,
        "max": max_v,
        "colors": colors,
        "seg1": seg1,
        "seg2": seg2,
        "x": x,
        "y": y,
        "wires": [],
    }


def chart(nid: str, z: str, name: str, group: str, order: int, label: str, x: int, y: int) -> dict:
    return {
        "id": nid,
        "type": "ui_chart",
        "z": z,
        "name": name,
        "group": group,
        "order": order,
        "width": 12,
        "height": 6,
        "label": label,
        "chartType": "line",
        "legend": "true",
        "xformat": "HH:mm:ss",
        "interpolate": "linear",
        "nodata": "Veri bekleniyor",
        "removeOlder": 1,
        "removeOlderUnit": "3600",
        "outputs": 1,
        "x": x,
        "y": y,
        "wires": [[]],
    }


TAB_TEL = "hub_tab_telemetry"
TAB_YZ = "hub_tab_yz"
TAB_CMD = "hub_tab_command"

flows: list[dict] = [
    {"id": TAB_TEL, "type": "tab", "label": "Telemetry", "disabled": False, "info": "", "env": []},
    {"id": TAB_YZ, "type": "tab", "label": "YZ Analiz", "disabled": False, "info": "", "env": []},
    {"id": TAB_CMD, "type": "tab", "label": "Command Log", "disabled": False, "info": "", "env": []},
    {
        "id": "broker1",
        "type": "mqtt-broker",
        "name": "Local Mosquitto",
        "broker": "localhost",
        "port": "1883",
        "clientid": "nodered_hub",
        "usetls": False,
        "keepalive": "60",
        "cleansession": True,
    },
    {
        "id": "influx_cfg1",
        "type": "influxdb",
        "hostname": "127.0.0.1",
        "port": "8086",
        "protocol": "http",
        "database": "",
        "name": "InfluxDB 2.x (iot_telemetry)",
        "usetls": False,
        "tls": "",
        "influxdbVersion": "2.0",
        "url": "http://127.0.0.1:8086",
        "timeout": 10,
        "rejectUnauthorized": True,
        "org": "iot-hub",
        "bucket": "iot_telemetry",
    },
    {"id": "ui_base_hub", "type": "ui_base", "theme": {"name": "theme-light"}, "site": {"name": "IoT Hub Dashboard"}},
    {"id": "tab1", "type": "ui_tab", "name": "Akıllı Sistemler", "icon": "dashboard", "order": 1, "disabled": False},
    {"id": "group_sulama", "type": "ui_group", "name": "Sulama", "tab": "tab1", "order": 1, "disp": True, "width": "12", "collapse": False},
    {"id": "group_hava", "type": "ui_group", "name": "Havalandırma", "tab": "tab1", "order": 2, "disp": True, "width": "12", "collapse": False},
    {
        "id": "hub_global_cfg",
        "type": "global-config",
        "env": [],
        "modules": {
            "node-red-dashboard": "3.6.6",
            "node-red-contrib-influxdb": "0.7.2",
        },
    },
    # --- Telemetry tab ---
    {
        "id": "mqtt_telemetry_in",
        "type": "mqtt in",
        "z": TAB_TEL,
        "name": "Tüm Telemetry",
        "topic": "+/+/telemetry",
        "qos": "1",
        "broker": "broker1",
        "inputs": 0,
        "x": 140,
        "y": 200,
        "wires": [["json_telemetry"]],
    },
    {
        "id": "json_telemetry",
        "type": "json",
        "z": TAB_TEL,
        "name": "JSON Parse",
        "property": "payload",
        "action": "",
        "pretty": False,
        "x": 330,
        "y": 200,
        "wires": [["func_veriyi_ayir", "func_influx_prep", "func_threshold", "debug_telemetry"]],
    },
    {
        "id": "debug_telemetry",
        "type": "debug",
        "z": TAB_TEL,
        "name": "Telemetry Debug",
        "active": True,
        "tosidebar": True,
        "console": False,
        "complete": "payload",
        "targetType": "msg",
        "x": 330,
        "y": 300,
        "wires": [],
    },
    {
        "id": "func_veriyi_ayir",
        "type": "function",
        "z": TAB_TEL,
        "name": "Veriyi Ayır (Hub)",
        "func": read_js("FUNCTION_VERIYI_AYIR_HUB.js"),
        "outputs": 6,
        "timeout": 0,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 560,
        "y": 160,
        "wires": [
            ["sw_ds18"],
            ["sw_dht"],
            ["sw_nem"],
            ["sw_temp_chart"],
            ["sw_nem_chart"],
            ["sw_hava"],
        ],
    },
    switch_node("sw_ds18", TAB_TEL, "DS18 → problem", 760, 60,
                [["gauge_ds18_sul"], ["gauge_ds18_hava"]]),
    switch_node("sw_dht", TAB_TEL, "DHT → problem", 760, 120,
                [["gauge_dht_sul"], ["gauge_dht_hava"]]),
    switch_node("sw_nem", TAB_TEL, "Nem → problem", 760, 180,
                [["gauge_nem_sul"], ["gauge_nem_hava"]]),
    switch_node("sw_temp_chart", TAB_TEL, "Sıcaklık chart → problem", 760, 240,
                [["chart_temp_sul"], ["chart_temp_hava"]]),
    switch_node("sw_nem_chart", TAB_TEL, "Nem chart → problem", 760, 300,
                [["chart_nem_sul"], ["chart_nem_hava"]]),
    switch_node("sw_hava", TAB_TEL, "Hava → problem", 760, 360,
                [[], ["gauge_hava_hava"]]),
    gauge("gauge_ds18_sul", TAB_TEL, "DS18 Sulama", "group_sulama", 1, "DS18B20 (°C)", "°C", 0, 50, 25, 35,
          ["#00b500", "#e6e600", "#ca3838"], 980, 40),
    gauge("gauge_dht_sul", TAB_TEL, "DHT Sulama", "group_sulama", 2, "DHT11 Sıcaklık (°C)", "°C", 0, 50, 25, 35,
          ["#00b500", "#e6e600", "#ca3838"], 980, 100),
    gauge("gauge_nem_sul", TAB_TEL, "Nem Sulama", "group_sulama", 3, "Nem (%)", "%", 0, 100, 30, 60,
          ["#ca3838", "#e6e600", "#00b500"], 980, 160),
    chart("chart_temp_sul", TAB_TEL, "Sıcaklık Sulama", "group_sulama", 4, "Sıcaklık (ds18b20, dht11)", 980, 220),
    chart("chart_nem_sul", TAB_TEL, "Nem Sulama", "group_sulama", 5, "Nem (dht11_nem)", 980, 300),
    gauge("gauge_ds18_hava", TAB_TEL, "DS18 Hava", "group_hava", 1, "DS18B20 (°C)", "°C", 0, 50, 25, 35,
          ["#00b500", "#e6e600", "#ca3838"], 980, 400),
    gauge("gauge_dht_hava", TAB_TEL, "DHT Hava", "group_hava", 2, "DHT11 Sıcaklık (°C)", "°C", 0, 50, 25, 35,
          ["#00b500", "#e6e600", "#ca3838"], 980, 460),
    gauge("gauge_nem_hava", TAB_TEL, "Nem Hava", "group_hava", 3, "Nem (%)", "%", 0, 100, 30, 60,
          ["#ca3838", "#e6e600", "#00b500"], 980, 520),
    gauge("gauge_hava_hava", TAB_TEL, "Hava Kalitesi", "group_hava", 4, "Hava Kalitesi", "AQI", 0, 600, 200, 400,
          ["#00b500", "#e6e600", "#ca3838"], 980, 580),
    chart("chart_temp_hava", TAB_TEL, "Sıcaklık Hava", "group_hava", 5, "Sıcaklık (ds18b20, dht11)", 980, 640),
    chart("chart_nem_hava", TAB_TEL, "Nem Hava", "group_hava", 6, "Nem (dht11_nem)", 980, 720),
    {
        "id": "func_influx_prep",
        "type": "function",
        "z": TAB_TEL,
        "name": "Influx Hazırla",
        "func": read_js("FUNCTION_INFLUX_PREP.js"),
        "outputs": 1,
        "timeout": 0,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 560,
        "y": 420,
        "wires": [["influx_out1", "debug_influx"]],
    },
    {
        "id": "debug_influx",
        "type": "debug",
        "z": TAB_TEL,
        "name": "Influx Debug",
        "active": False,
        "tosidebar": True,
        "complete": "payload",
        "targetType": "msg",
        "x": 760,
        "y": 480,
        "wires": [],
    },
    {
        "id": "influx_out1",
        "type": "influxdb out",
        "z": TAB_TEL,
        "influxdb": "influx_cfg1",
        "name": "InfluxDB telemetry",
        "measurement": "telemetry",
        "precision": "",
        "retentionPolicy": "",
        "database": "",
        "precisionV18FluxV20": "ms",
        "retentionPolicyV18Flux": "",
        "org": "iot-hub",
        "bucket": "iot_telemetry",
        "x": 760,
        "y": 420,
        "wires": [],
    },
    {
        "id": "func_threshold",
        "type": "function",
        "z": TAB_TEL,
        "name": "Eşik → YZ Tetik",
        "func": THRESHOLD_FUNC,
        "outputs": 1,
        "timeout": 0,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 560,
        "y": 520,
        "wires": [["http_analyze"]],
    },
    # --- YZ Analiz tab ---
    {
        "id": "inject_analyze_60s",
        "type": "inject",
        "z": TAB_YZ,
        "name": "Her 60 sn",
        "props": [{"p": "payload"}],
        "repeat": "60",
        "crontab": "",
        "once": False,
        "onceDelay": 0.1,
        "topic": "",
        "payload": "",
        "payloadType": "date",
        "x": 150,
        "y": 120,
        "wires": [["func_analyze_trigger"]],
    },
    {
        "id": "func_analyze_trigger",
        "type": "function",
        "z": TAB_YZ,
        "name": "YZ İstek Oluştur",
        "func": read_js("FUNCTION_ANALYZE_TRIGGER.js"),
        "outputs": 2,
        "timeout": 0,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 360,
        "y": 120,
        "wires": [["http_analyze"], ["http_analyze"]],
    },
    {
        "id": "http_analyze",
        "type": "http request",
        "z": TAB_YZ,
        "name": "POST /analyze",
        "method": "use",
        "ret": "obj",
        "paytoqs": "ignore",
        "url": "",
        "tls": "",
        "persist": False,
        "proxy": "",
        "insecureHTTPParser": False,
        "authType": "",
        "senderr": False,
        "headers": [],
        "x": 580,
        "y": 200,
        "wires": [["func_command_from_api", "debug_analyze"]],
    },
    {
        "id": "debug_analyze",
        "type": "debug",
        "z": TAB_YZ,
        "name": "Analyze Yanıt",
        "active": True,
        "tosidebar": True,
        "complete": "payload",
        "targetType": "msg",
        "x": 780,
        "y": 280,
        "wires": [],
    },
    {
        "id": "func_command_from_api",
        "type": "function",
        "z": TAB_YZ,
        "name": "Command Oluştur",
        "func": read_js("FUNCTION_COMMAND_FROM_API.js"),
        "outputs": 1,
        "timeout": 0,
        "noerr": 0,
        "initialize": "",
        "finalize": "",
        "libs": [],
        "x": 780,
        "y": 200,
        "wires": [["mqtt_command_out", "debug_command_build"]],
    },
    {
        "id": "debug_command_build",
        "type": "debug",
        "z": TAB_YZ,
        "name": "Command Debug",
        "active": True,
        "tosidebar": True,
        "complete": "true",
        "targetType": "full",
        "x": 1000,
        "y": 280,
        "wires": [],
    },
    {
        "id": "mqtt_command_out",
        "type": "mqtt out",
        "z": TAB_YZ,
        "name": "MQTT Command",
        "topic": "",
        "qos": "1",
        "retain": "false",
        "respTopic": "",
        "contentType": "",
        "userProps": "",
        "correl": "",
        "expiry": "",
        "broker": "broker1",
        "x": 1000,
        "y": 200,
        "wires": [],
    },
    # --- Command Log tab ---
    {
        "id": "mqtt_command_in",
        "type": "mqtt in",
        "z": TAB_CMD,
        "name": "Tüm Command",
        "topic": "+/+/command",
        "qos": "1",
        "broker": "broker1",
        "inputs": 0,
        "x": 150,
        "y": 120,
        "wires": [["json_command", "debug_command_in"]],
    },
    {
        "id": "json_command",
        "type": "json",
        "z": TAB_CMD,
        "name": "JSON Parse",
        "property": "payload",
        "action": "",
        "pretty": False,
        "x": 360,
        "y": 120,
        "wires": [["debug_command_parsed"]],
    },
    {
        "id": "debug_command_in",
        "type": "debug",
        "z": TAB_CMD,
        "name": "Command Raw",
        "active": True,
        "tosidebar": True,
        "complete": "true",
        "targetType": "full",
        "x": 360,
        "y": 200,
        "wires": [],
    },
    {
        "id": "debug_command_parsed",
        "type": "debug",
        "z": TAB_CMD,
        "name": "Command Parsed",
        "active": True,
        "tosidebar": True,
        "complete": "payload",
        "targetType": "msg",
        "x": 560,
        "y": 120,
        "wires": [],
    },
]

# Wire threshold to YZ tab http node - threshold is on TAB_TEL but http is on TAB_YZ
# Node-RED allows cross-tab wiring; update func_threshold wires to http_analyze
# http_analyze needs to be referenced from telemetry tab - already same id

# Fix: func_threshold and func_analyze_trigger both wire to http_analyze
# Move http_analyze to shared - it's in TAB_YZ z but can receive from TAB_TEL

out = DIR / "flows_hub_complete.json"
out.write_text(json.dumps(flows, ensure_ascii=False, indent=4) + "\n", encoding="utf-8")
print(f"Wrote {out} ({len(flows)} nodes)")
