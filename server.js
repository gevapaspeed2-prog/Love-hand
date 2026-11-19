const http = require("http");
const fs = require("fs");
const path = require("path");

let latest = { hands: [], detected: false, updatedAt: 0 };
let latestJSON = JSON.stringify(latest);

function cleanHand(hand) {
  if (!hand || !Array.isArray(hand.points) || hand.points.length !== 21) return null;
  const n = v => Number.isFinite(Number(v)) ? Number(v) : 0;
  return {
    handedness: hand.handedness === "Left" ? "Left" : "Right",
    score: Math.max(0, Math.min(1, n(hand.score))),
    points: hand.points.map(p => ({
      x: Math.max(0, Math.min(1, n(p.x))),
      y: Math.max(0, Math.min(1, n(p.y))),
      z: Math.max(-1, Math.min(1, n(p.z)))
    }))
  };
}

const server = http.createServer((req, res) => {
  const origin = req.headers.origin || "*";
  res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") { res.writeHead(204); return res.end(); }

  const url = new URL(req.url, "http://localhost");
  if (url.pathname === "/pose" && req.method === "GET") {
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    return res.end(latestJSON);
  }

  if (url.pathname === "/pose" && req.method === "POST") {
    let body = "";
    req.on("data", chunk => {
      body += chunk;
      if (body.length > 50000) { res.writeHead(413); res.end(); req.destroy(); }
    });
    req.on("end", () => {
      if (res.writableEnded) return;
      try {
        const data = JSON.parse(body || "{}");
        const hands = Array.isArray(data.hands) ? data.hands.slice(0, 2).map(cleanHand).filter(Boolean) : [];
        latest = { hands, detected: hands.length > 0, updatedAt: Date.now() };
        latestJSON = JSON.stringify(latest);
        res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
        res.end('{"ok":true}');
      } catch {
        res.writeHead(400, { "Content-Type": "application/json" });
        res.end('{"ok":false}');
      }
    });
    return;
  }

  if (url.pathname === "/health") {
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    return res.end(JSON.stringify({ ok: true, service: "LIVE HAND v2.1 FAST", hands: latest.hands.length }));
  }

  if (url.pathname === "/" || url.pathname === "/index.html") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache" });
    return fs.createReadStream(path.join(__dirname, "index.html")).pipe(res);
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("Not found");
});

const port = process.env.PORT || 3000;
server.listen(port, "0.0.0.0", () => console.log("LIVE HAND v2.1 FAST listening on " + port));
