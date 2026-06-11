// /analyze yanıtını dashboard ui_text için biçimlendirir (2 çıkış).
// 1 → tarim_sulama, 2 → tarim_havalandirma

const res = msg.payload;
if (!res || typeof res !== "object") {
    return [null, null];
}

const when = new Date().toLocaleString("tr-TR", {
    timeZone: "Europe/Istanbul",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
});

const pid = res.problem_id || msg.problem_id;
const takim = res.takim_no || msg.takim_no;

const text =
    `Son analiz: ${when}\n\n` +
    `Takim: ${takim}\n` +
    `Aksiyon: ${res.aksiyon || "—"}\n` +
    `Sure: ${Number(res.sure_sn) || 0} sn\n` +
    `Kaynak: ${res.source || "—"}\n\n` +
    `Gerekce:\n${res.gerekce || "—"}`;

const out = { payload: text };

if (pid === "tarim_sulama") {
    return [out, null];
}
if (pid === "tarim_havalandirma") {
    return [null, out];
}
return [null, null];
