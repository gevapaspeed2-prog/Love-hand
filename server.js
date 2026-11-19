const http = require("http");
const fs = require("fs");
const path = require("path");

let latestPose = {
  detected: false, x: 0.5, y: 0.5, angle: 0, openness: 0,
  points: [], updatedAt: 0
};

const server = http.createServer((req, res) => {
  const origin = req.headers.origin || "*";
  res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") {
    res.writeHead(204); return res.end();
  }

  const url = new URL(req.url, "http://localhost");
  if (url.pathname === "/pose" && req.method === "GET") {
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    return res.end(JSON.stringify(latestPose));
  }

  if (url.pathname === "/pose" && req.method === "POST") {
    let body = "";
    req.on("data", chunk => { body += chunk; if (body.length > 100000) req.destroy(); });
    req.on("end", () => {
      try {
        const data = JSON.parse(body || "{}");
        if (data && Array.isArray(data.points) && data.points.length === 21) {
          latestPose = {
            detected: !!data.detected,
            x: Number(data.x) || 0.5,
            y: Number(data.y) || 0.5,
            angle: Number(data.angle) || 0,
            openness: Number(data.openness) || 0,
            points: data.points.map(p => ({
              x: Math.max(0, Math.min(1, Number(p.x) || 0)),
              y: Math.max(0, Math.min(1, Number(p.y) || 0))
            })),
            updatedAt: Date.now()
          };
        } else {
          latestPose = { ...latestPose, detected: false, updatedAt: Date.now() };
        }
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
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({ ok: true, service: "LIVE HAND v1.0" }));
  }

  if (url.pathname === "/" || url.pathname === "/index.html") {
    const file = path.join(__dirname, "index.html");
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    return fs.createReadStream(file).pipe(res);
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("Not found");
});

const port = process.env.PORT || 3000;
server.listen(port, "0.0.0.0", () => console.log("LIVE HAND listening on " + port));
