// 5 çıkış:
// 1 → DS18B20 sıcaklık gauge
// 2 → DHT11 sıcaklık gauge
// 3 → Nem gauge
// 4 → Sıcaklık chart (topic: ds18b20, dht11)
// 5 → Nem chart (topic: dht11_nem)

const p = msg.payload;
if (!p || typeof p !== "object") {
    return null;
}

const sensor = String(p.sensor || p.cihaz_id || p.device_id || "unknown").toLowerCase();

let sicaklik = p.sicaklik;
let nem = p.nem;

if (p.values && typeof p.values === "object") {
    if (sicaklik === undefined) sicaklik = p.values.sicaklik;
    if (nem === undefined) nem = p.values.nem;
}

const isDs18 = sensor.includes("ds18");
const isDht = sensor.includes("dht");

const outDs18Gauge = [];
const outDhtTempGauge = [];
const outNemGauge = [];
const outTempChart = [];
const outNemChart = [];

if (sicaklik !== undefined && sicaklik !== null && !Number.isNaN(Number(sicaklik))) {
    const t = Number(sicaklik);

    if (isDs18) {
        outDs18Gauge.push({ payload: t });
        outTempChart.push({ payload: t, topic: "ds18b20" });
    } else if (isDht || (nem !== undefined && nem !== null)) {
        outDhtTempGauge.push({ payload: t });
        outTempChart.push({ payload: t, topic: "dht11" });
    } else {
        outDs18Gauge.push({ payload: t });
        outTempChart.push({ payload: t, topic: "ds18b20" });
    }
}

if (nem !== undefined && nem !== null && !Number.isNaN(Number(nem))) {
    const n = Number(nem);
    outNemGauge.push({ payload: n });
    outNemChart.push({ payload: n, topic: "dht11_nem" });
}

if (
    outDs18Gauge.length === 0 &&
    outDhtTempGauge.length === 0 &&
    outNemGauge.length === 0 &&
    outTempChart.length === 0 &&
    outNemChart.length === 0
) {
    return null;
}

return [outDs18Gauge, outDhtTempGauge, outNemGauge, outTempChart, outNemChart];
