// 6 çıkış:
// 1 → DS18B20 sıcaklık gauge
// 2 → DHT11 sıcaklık gauge
// 3 → Nem gauge
// 4 → Sıcaklık chart (topic: ds18b20, dht11)
// 5 → Nem chart (topic: dht11_nem)
// 6 → Hava kalitesi gauge (tarim_havalandirma / MQ sensörleri)

const p = msg.payload;
if (!p || typeof p !== "object") {
    return null;
}

const topicParts = String(msg.topic || "").split("/");
const problem_id = topicParts[0] || p.problem_id || "unknown";
const takim_no = topicParts[1] || p.takim_no || "unknown";

const sensor = String(p.sensor || p.cihaz_id || p.device_id || "unknown").toLowerCase();

let sicaklik = p.sicaklik;
let nem = p.nem;
let hava_kalitesi = p.hava_kalitesi;

if (p.values && typeof p.values === "object") {
    if (sicaklik === undefined) sicaklik = p.values.sicaklik;
    if (nem === undefined) nem = p.values.nem;
    if (hava_kalitesi === undefined) hava_kalitesi = p.values.hava_kalitesi;
}

const isDs18 = sensor.includes("ds18");
const isDht = sensor.includes("dht");

const outDs18Gauge = [];
const outDhtTempGauge = [];
const outNemGauge = [];
const outTempChart = [];
const outNemChart = [];
const outHavaGauge = [];

if (sicaklik !== undefined && sicaklik !== null && !Number.isNaN(Number(sicaklik))) {
    const t = Number(sicaklik);

    if (isDs18) {
        outDs18Gauge.push({ payload: t, problem_id, takim_no });
        outTempChart.push({ payload: t, topic: "ds18b20", problem_id, takim_no });
    } else if (isDht || (nem !== undefined && nem !== null)) {
        outDhtTempGauge.push({ payload: t, problem_id, takim_no });
        outTempChart.push({ payload: t, topic: "dht11", problem_id, takim_no });
    } else {
        outDs18Gauge.push({ payload: t, problem_id, takim_no });
        outTempChart.push({ payload: t, topic: "ds18b20", problem_id, takim_no });
    }
}

if (nem !== undefined && nem !== null && !Number.isNaN(Number(nem))) {
    const n = Number(nem);
    outNemGauge.push({ payload: n, problem_id, takim_no });
    outNemChart.push({ payload: n, topic: "dht11_nem", problem_id, takim_no });
}

if (hava_kalitesi !== undefined && hava_kalitesi !== null && !Number.isNaN(Number(hava_kalitesi))) {
    const h = Number(hava_kalitesi);
    outHavaGauge.push({ payload: h, problem_id, takim_no });
}

if (
    outDs18Gauge.length === 0 &&
    outDhtTempGauge.length === 0 &&
    outNemGauge.length === 0 &&
    outTempChart.length === 0 &&
    outNemChart.length === 0 &&
    outHavaGauge.length === 0
) {
    return null;
}

return [outDs18Gauge, outDhtTempGauge, outNemGauge, outTempChart, outNemChart, outHavaGauge];
