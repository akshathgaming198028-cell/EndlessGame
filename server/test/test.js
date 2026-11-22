// Starts the real server on a spare port and plays through the room rules with fake players.
const { spawn } = require("child_process");
const path = require("path");
const http = require("http");
const WebSocket = require("ws");
const assert = require("assert");

const PORT = 18099;
const URL = `ws://127.0.0.1:${PORT}`;
const server = spawn(process.execPath, [path.join(__dirname, "..", "index.js")], {
  env: { ...process.env, PORT: String(PORT) },
  stdio: ["ignore", "pipe", "pipe"],
});

function wait(ms) { return new Promise((r) => setTimeout(r, ms)); }

class Client {
  constructor(name) {
    this.name = name;
    this.inbox = [];
    this.ws = null;
  }
  open() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(URL);
      this.ws.on("message", (raw) => this.inbox.push(JSON.parse(raw.toString())));
      this.ws.on("open", resolve);
      this.ws.on("error", reject);
    });
  }
  send(obj) { this.ws.send(JSON.stringify(obj)); }
  // wait for a message matching the test (returns it and removes it from the inbox)
  async expect(pred, what, ms = 2000) {
    const end = Date.now() + ms;
    while (Date.now() < end) {
      const i = this.inbox.findIndex(pred);
      if (i >= 0) return this.inbox.splice(i, 1)[0];
      await wait(20);
    }
    throw new Error(`${this.name}: timed out waiting for ${what}; inbox=${JSON.stringify(this.inbox)}`);
  }
  // check that nothing matching arrives in a short time
  async none(pred, ms = 300) {
    await wait(ms);
    const hit = this.inbox.find(pred);
    assert.ok(!hit, `${this.name}: got unexpected ${JSON.stringify(hit)}`);
  }
  close() { if (this.ws) this.ws.close(); }
}

async function run() {
  await wait(400); // let the server start
  // health check
  const body = await new Promise((resolve, reject) => {
    http.get(`http://127.0.0.1:${PORT}/health`, (res) => {
      let d = ""; res.on("data", (c) => (d += c)); res.on("end", () => resolve({ code: res.statusCode, d }));
    }).on("error", reject);
  });
  assert.strictEqual(body.code, 200); assert.strictEqual(body.d, "ok");
  console.log("ok  health check");

  const A = new Client("A"), B = new Client("B"), C = new Client("C");
  await A.open(); await B.open(); await C.open();

  // create
  A.send({ t: "create", name: "Ann" });
  const made = await A.expect((m) => m.t === "joined", "joined after create");
  assert.strictEqual(made.host, true);
  const code = made.code;
  assert.strictEqual(code.length, 4);
  console.log("ok  create room, code " + code);

  // list shows the open room
  B.send({ t: "list" });
  const list = await B.expect((m) => m.t === "rooms", "room list");
  assert.ok(list.rooms.some((r) => r.code === code && r.count === 1), "room missing from list");
  console.log("ok  lobby list shows the room");

  // join with a lowercase code; the host is told about the new player
  B.send({ t: "join", code: code.toLowerCase(), name: "Bob" });
  const joinedB = await B.expect((m) => m.t === "joined", "B joined");
  assert.strictEqual(joinedB.host, false);
  assert.strictEqual(joinedB.players.length, 2);
  await A.expect((m) => m.t === "players" && m.players.length === 2, "host told of new player");
  console.log("ok  join by code (any case), host notified");

  // bad code
  C.send({ t: "join", code: "ZZZZ", name: "Cy" });
  const bad = await C.expect((m) => m.t === "error", "error for bad code");
  assert.strictEqual(bad.reason, "no_room");
  console.log("ok  bad code refused");

  // before start: no relay between players
  B.send({ t: "update", data: { x: 1 } });
  await A.none((m) => m.t === "update");
  console.log("ok  no position relay before the host starts");

  // only host can start
  B.send({ t: "start" });
  const notHost = await B.expect((m) => m.t === "error", "not_host error");
  assert.strictEqual(notHost.reason, "not_host");
  A.send({ t: "start" });
  await A.expect((m) => m.t === "start", "start for host");
  await B.expect((m) => m.t === "start", "start for B");
  console.log("ok  only the host can start the match");

  // during the race positions are relayed to the others
  B.send({ t: "update", data: { x: 1.5, z: -20 } });
  const up = await A.expect((m) => m.t === "update", "relayed update");
  assert.strictEqual(up.from, joinedB.id);
  assert.strictEqual(up.data.x, 1.5);
  await B.none((m) => m.t === "update" && m.from === joinedB.id, 150);
  console.log("ok  positions relayed to others, not echoed back");

  // no joining after the match starts
  C.send({ t: "join", code, name: "Cy" });
  const late = await C.expect((m) => m.t === "error", "started error");
  assert.strictEqual(late.reason, "started");
  console.log("ok  late join refused once started");

  // host leaves: the next player becomes host
  A.send({ t: "leave" });
  await A.expect((m) => m.t === "left", "left confirmation");
  const hostMsg = await B.expect((m) => m.t === "players" && m.host === joinedB.id, "B becomes host");
  assert.ok(hostMsg.players.find((p) => p.id === joinedB.id).host === true);
  console.log("ok  host leaves, next player takes over");

  // room not in the list once racing; empties and is deleted when the last player leaves
  C.send({ t: "list" });
  const list2 = await C.expect((m) => m.t === "rooms", "list after start");
  assert.ok(!list2.rooms.some((r) => r.code === code), "racing room still listed");
  B.close();
  await wait(200);
  C.send({ t: "join", code, name: "Cy" });
  const gone = await C.expect((m) => m.t === "error", "room gone");
  assert.strictEqual(gone.reason, "no_room");
  console.log("ok  racing room hidden from list; empty room removed");

  // room size limit
  const D = new Client("D"); await D.open();
  D.send({ t: "create", name: "Dee" });
  const room2 = await D.expect((m) => m.t === "joined", "room2");
  const fillers = [];
  for (let i = 0; i < 7; i++) {
    const f = new Client("F" + i); await f.open(); fillers.push(f);
    f.send({ t: "join", code: room2.code, name: "F" + i });
    await f.expect((m) => m.t === "joined", "filler joined");
  }
  const over = new Client("Over"); await over.open();
  over.send({ t: "join", code: room2.code, name: "Over" });
  const full = await over.expect((m) => m.t === "error", "full");
  assert.strictEqual(full.reason, "full");
  console.log("ok  room holds 8 players, 9th refused");

  // bad messages do not crash the server
  D.ws.send("not json {");
  D.send({ t: "unknown_thing" });
  await wait(100);
  D.send({ t: "list" });
  await D.expect((m) => m.t === "rooms", "still answering after bad messages");
  console.log("ok  bad messages ignored, server still answering");

  [A, B, C, D, over, ...fillers].forEach((c) => c.close());
}

run().then(() => {
  console.log("\nALL ROOM TESTS PASSED");
  server.kill();
  process.exit(0);
}).catch((e) => {
  console.error("\nTEST FAILED:", e.message);
  server.kill();
  process.exit(1);
});
