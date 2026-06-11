// Periyodik YZ analiz tetikleyici — 2 çıkış:
// 1 → tarim_sulama / takim 7
// 2 → tarim_havalandirma / takim 8

const targets = [
    { problem_id: "tarim_sulama", takim_no: "7" },
    { problem_id: "tarim_havalandirma", takim_no: "8" }
];

function buildRequest(problem_id, takim_no) {
    return {
        payload: {
            problem_id,
            takim_no,
            minutes: 15
        },
        problem_id,
        takim_no,
        url: "http://127.0.0.1:5000/analyze",
        method: "POST",
        headers: {
            "content-type": "application/json"
        }
    };
}

return targets.map((t) => buildRequest(t.problem_id, t.takim_no));
