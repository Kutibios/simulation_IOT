// FastAPI /analyze yanıtını MQTT command mesajına dönüştürür.
// topic: {problem_id}/{takim_no}/command

const res = msg.payload;
if (!res || typeof res !== "object") {
    return null;
}

const problem_id = res.problem_id || msg.problem_id;
const takim_no = res.takim_no || msg.takim_no;
const aksiyon = res.aksiyon;

if (!problem_id || !takim_no) {
    node.warn("command: problem_id veya takim_no eksik");
    return null;
}

if (!aksiyon || aksiyon === "bekle") {
    return null;
}

msg.topic = `${problem_id}/${takim_no}/command`;
msg.payload = {
    aksiyon,
    sure_sn: Number(res.sure_sn) || 0,
    gerekce: res.gerekce || "",
    source: res.source || "api",
    timestamp: new Date().toISOString()
};
return msg;
