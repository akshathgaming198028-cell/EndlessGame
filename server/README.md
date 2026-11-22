# Heist Escape rooms server

Runs the multiplayer rooms: create a room, share the 4-letter code, join by code or from the lobby list,
the host starts the match and players' positions are passed to everyone else in the room.

Rooms live in memory. A restart (or Render's free sleep) clears them. That's fine for rooms; saved
progress will need a database later.

## Test it (on any computer with Node 18+)

    cd server
    npm install
    npm test

## Put it online on Render (free)

1. Go to render.com, sign in with GitHub, click **New > Web Service**.
2. Pick the `endlessgame` repository.
3. Set:
   - **Root Directory:** `server`
   - **Runtime:** Node
   - **Build Command:** `npm install`
   - **Start Command:** `node index.js`
   - **Instance Type:** Free
   - **Health Check Path:** `/health`
4. Click **Create Web Service**. When the log says "rooms server listening", copy the address
   (it looks like `https://heist-rooms-xxxx.onrender.com`). The game uses the same address with `wss://` in front.

Free notes: the service sleeps after 15 minutes with nobody connected and takes about a minute to wake
when the next player connects. Rooms are cleared on restart.

## Protocol (what the game sends and receives)

Client sends JSON:

| message | fields | reply |
|---|---|---|
| `{t:"create", name}` | name | `joined` (code, id, host, players) |
| `{t:"list"}` | | `rooms` (open rooms: code, host, count, max) |
| `{t:"join", code, name}` | code, name | `joined`, or `error` (`no_room`, `full`, `started`) |
| `{t:"start"}` | host only | `start` to everyone, or `error` (`not_host`) |
| `{t:"update", data}` | any small object | relayed to others as `{t:"update", from, data}` while racing |
| `{t:"leave"}` | | `left` |

Server also sends `{t:"players", players, host}` whenever someone joins or leaves.
