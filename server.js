const http = require("http");
const fs = require("fs");
const path = require("path");
const { WebSocketServer, WebSocket } = require("ws");

let sequence = 0;
let latest = { hands: [], detected: false, updatedAt: 0, sequence: 0 };
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

// Принять данные, очистить, сохранить, вернуть JSON-строку
function ingest(data) {
  const hands = Array.isArray(data.hands) ? data.hands.slice(0, 2).map(cleanHand).filter(Boolean) : [];
  sequence++;
  latest = { hands, detected: hands.length > 0, updatedAt: Date.now(), sequence };
  latestJSON = JSON.stringify(latest);
  return latestJSON;
}

const server = http.createServer((req, res) => {
  const origin = req.headers.origin || "*";
  res.setHeader("Access-Control-Allow-Origin", origin);
  res.setHeader("Vary", "Origin");
  res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") { res.writeHead(204); return res.end(); }

  const url = new URL(req.url, "http://localhost");

  // Запасной вариант: старый HTTP
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
        const json = ingest(JSON.parse(body || "{}"));
        broadcast(json);
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
    return res.end(JSON.stringify({
      ok: true, service: "LIVE HAND v3 WS",
      hands: latest.hands.length, sequence,
      viewers: viewers.size
    }));
  }

  if (url.pathname === "/" || url.pathname === "/index.html") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-cache" });
    return fs.createReadStream(path.join(__dirname, "index.html")).pipe(res);
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("Not found");
});

// ---------- WebSocket ----------
// /ws?role=camera  - телефон с камерой, отправляет координаты
// /ws?role=viewer  - Roblox, получает координаты
const wss = new WebSocketServer({ noServer: true, maxPayload: 50000, perMessageDeflate: false });
const viewers = new Set();

function broadcast(json) {
  for (const ws of viewers) {
    // не копим очередь: если клиент не успевает, пропускаем кадр
    if (ws.readyState === WebSocket.OPEN && ws.bufferedAmount < 65536) ws.send(json);
  }
}

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname !== "/ws") { socket.destroy(); return; }
  const role = url.searchParams.get("role") === "camera" ? "camera" : "viewer";
  wss.handleUpgrade(req, socket, head, ws => {
    ws.role = role;
    ws.isAlive = true;
    ws.on("pong", () => { ws.isAlive = true; });

    if (role === "viewer") {
      viewers.add(ws);
      ws.send(latestJSON); // сразу отдать последнее состояние
      ws.on("close", () => viewers.delete(ws));
    } else {
      ws.on("message", raw => {
        try {
          const data = JSON.parse(raw.toString());
          if (data.ping) return ws.send('{"pong":true}'); // для замера задержки
          broadcast(ingest(data));
        } catch { /* игнорируем мусор */ }
      });
    }
    ws.on("error", () => {});
  });
});

// Проверка живых соединений каждые 20 с (Render рвёт молчащие)
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, 20000);

const port = process.env.PORT || 3000;
server.listen(port, "0.0.0.0", () => console.log("LIVE HAND v3 WS listening on " + port));
