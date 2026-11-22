// Heist Escape rooms server.
// Keeps rooms in memory (they reset on restart) and relays messages between players in a room.
// Plain WebSocket + JSON. Runs anywhere Node 18+ runs (Render, a VM, your PC).

const http = require("http");
const { WebSocketServer } = require("ws");

const PORT = Number(process.env.PORT) || 8080;
const MAX_PLAYERS = 8;
const MAX_MSG_BYTES = 4096;      // bigger messages are dropped
const MAX_MSGS_PER_SEC = 60;     // more than this from one player per second: dropped
const PING_EVERY_MS = 25000;     // keeps connections alive through proxies and detects dead ones
const CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no 0/O/1/I to avoid confusion

const rooms = new Map();         // code -> room
let nextId = 1;

function makeCode() {
  for (let tries = 0; tries < 1000; tries++) {
    let c = "";
    for (let i = 0; i < 4; i++) c += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
    if (!rooms.has(c)) return c;
  }
  throw new Error("no free room codes");
}

function send(ws, obj) {
  if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
}

function roomPlayers(room) {
  return [...room.players.values()].map((p) => ({ id: p.id, name: p.name, host: p.id === room.host }));
}

function broadcast(room, obj, exceptId = null) {
  for (const p of room.players.values()) {
    if (p.id !== exceptId) send(p.ws, obj);
  }
}

function cleanName(v) {
  const s = String(v || "").replace(/[^\w \-]/g, "").trim().slice(0, 16);
  return s || "runner";
}

function leaveRoom(conn) {
  const room = rooms.get(conn.code);
  conn.code = null;
  if (!room) return;
  room.players.delete(conn.id);
  if (room.players.size === 0) {
    rooms.delete(room.code);
    return;
  }
  if (room.host === conn.id) {
    room.host = room.players.keys().next().value; // next player becomes host
  }
  broadcast(room, { t: "players", players: roomPlayers(room), host: room.host });
}

function openRooms() {
  const out = [];
  for (const r of rooms.values()) {
    if (r.state === "lobby") out.push({ code: r.code, host: r.players.get(r.host)?.name || "runner", count: r.players.size, max: MAX_PLAYERS });
  }
  return out;
}

const server = http.createServer((req, res) => {
  if (req.url === "/health") {
    res.writeHead(200, { "Content-Type": "text/plain" });
    res.end("ok");
    return;
  }
  res.writeHead(404);
  res.end();
});

const wss = new WebSocketServer({ server, maxPayload: MAX_MSG_BYTES });

wss.on("connection", (ws) => {
  const conn = { ws, id: nextId++, name: "runner", code: null, alive: true, times: [] };
  ws.on("pong", () => { conn.alive = true; });

  ws.on("message", (raw) => {
    // rate limit: at most MAX_MSGS_PER_SEC messages in any one second
    const now = Date.now();
    conn.times = conn.times.filter((t) => now - t < 1000);
    if (conn.times.length >= MAX_MSGS_PER_SEC) return;
    conn.times.push(now);

    let msg;
    try { msg = JSON.parse(raw.toString()); } catch { return; }
    if (!msg || typeof msg.t !== "string") return;

    switch (msg.t) {
      case "hello": {
        send(ws, { t: "hello", id: conn.id });
        break;
      }
      case "list": {
        send(ws, { t: "rooms", rooms: openRooms() });
        break;
      }
      case "create": {
        leaveRoom(conn);
        conn.name = cleanName(msg.name);
        const code = makeCode();
        const room = { code, host: conn.id, state: "lobby", players: new Map() };
        room.players.set(conn.id, conn);
        rooms.set(code, room);
        conn.code = code;
        send(ws, { t: "joined", code, id: conn.id, host: true, players: roomPlayers(room) });
        break;
      }
      case "join": {
        const code = String(msg.code || "").toUpperCase().trim();
        const room = rooms.get(code);
        if (!room) return send(ws, { t: "error", reason: "no_room" });
        if (room.state !== "lobby") return send(ws, { t: "error", reason: "started" });
        if (room.players.size >= MAX_PLAYERS) return send(ws, { t: "error", reason: "full" });
        leaveRoom(conn);
        conn.name = cleanName(msg.name);
        room.players.set(conn.id, conn);
        conn.code = code;
        send(ws, { t: "joined", code, id: conn.id, host: room.host === conn.id, players: roomPlayers(room) });
        broadcast(room, { t: "players", players: roomPlayers(room), host: room.host }, conn.id);
        break;
      }
      case "leave": {
        leaveRoom(conn);
        send(ws, { t: "left" });
        break;
      }
      case "start": {
        const room = rooms.get(conn.code);
        if (!room || room.host !== conn.id) return send(ws, { t: "error", reason: "not_host" });
        room.state = "racing";
        broadcast(room, { t: "start" });
        break;
      }
      case "update": {
        // relays a player's position/state to the others in the same room
        const room = rooms.get(conn.code);
        if (!room || room.state !== "racing") return;
        broadcast(room, { t: "update", from: conn.id, data: msg.data }, conn.id);
        break;
      }
      default:
        break;
    }
  });

  ws.on("close", () => leaveRoom(conn));
  ws.on("error", () => leaveRoom(conn));
});

// ping every connection; drop the ones that stopped answering
const pinger = setInterval(() => {
  for (const ws of wss.clients) {
    if (ws.isAlive === false) { ws.terminate(); continue; }
    ws.isAlive = false;
    ws.ping();
  }
}, PING_EVERY_MS);
wss.on("connection", (ws) => { ws.isAlive = true; ws.on("pong", () => { ws.isAlive = true; }); });
wss.on("close", () => clearInterval(pinger));

server.listen(PORT, () => {
  console.log(`rooms server listening on ${PORT}`);
});

module.exports = { server, wss, rooms };
