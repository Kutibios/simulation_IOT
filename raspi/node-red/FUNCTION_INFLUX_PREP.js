// InfluxDB out için msg.payload hazırlar.
// measurement: telemetry (influxdb out düğümünde de ayarlı)
// tags: problem_id, takim_no, sensor
// fields: sicaklik, nem, hava_kalitesi (payload'da olanlar)

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

const fields = {};

if (sicaklik !== undefined && sicaklik !== null && !Number.isNaN(Number(sicaklik))) {
    fields.sicaklik = Number(sicaklik);
}
if (nem !== undefined && nem !== null && !Number.isNaN(Number(nem))) {
    fields.nem = Number(nem);
}
if (hava_kalitesi !== undefined && hava_kalitesi !== null && !Number.isNaN(Number(hava_kalitesi))) {
    fields.hava_kalitesi = Number(hava_kalitesi);
}

if (Object.keys(fields).length === 0) {
    return null;
}

msg.measurement = "telemetry";
msg.payload = [
    fields,
    { problem_id, takim_no, sensor }
];
return msg;
