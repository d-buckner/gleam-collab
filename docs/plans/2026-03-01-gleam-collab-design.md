# gleam-collab — Design Document
*2026-03-01*

## Overview

A Gleam-first real-time collaboration server built on top of the `automerge` NIF package.
Clients connect over WebSocket for centralised persistent collaboration and can relay
WebRTC signaling messages through the server for peer-to-peer connections.

v1 scope: in-memory only, no auth, raw binary wire protocol.

---

## Architecture

### Process tree

```
OTP Application
├── RoomRegistry  (gleam_otp Actor)
│     state: Map(room_id, Subject(RoomMsg))
└── Mist HTTP server
      └── [one Mist WS callback per connected client]
            → talks to RoomRegistry to get/create a Room Subject
            → bridges binary frames to/from the Room actor

Room actors (spawned on demand by Registry)
  state: DocRef + Map(client_id, Peer)
  Peer  = { sync_state: SyncStateRef, subject: Subject(ConnMsg) }
```

Connection handlers are plain Mist WebSocket callbacks — not full OTP actors.
Rooms are `gleam_otp` Actors spawned lazily on first join, kept alive while the
process tree is running (doc lives in memory for the lifetime of the actor).

### Module layout

```
src/
  gleam_collab.gleam     # application entry — starts Mist + RoomRegistry
  registry.gleam         # RoomRegistry actor — get_or_create(room_id)
  room.gleam             # Room actor — automerge sync + peer map
  connection.gleam       # Mist WS handler — parse frames, bridge to Room
  protocol.gleam         # binary frame encode/decode
```

### Dependencies

| Package | Purpose |
|---|---|
| `mist` | HTTP/WebSocket server (pure Gleam) |
| `gleam_otp` | Actors / process management |
| `gleam_erlang` | Erlang interop (`crypto.strong_rand_bytes`) |
| `gleam_stdlib` | Standard library |
| `automerge` | Local path dep — the NIF binding layer |

---

## Binary Wire Protocol

All frames are raw binary WebSocket messages. First byte is the message type tag.

### Client → Server

| Tag | Frame | Meaning |
|---|---|---|
| `0x01` | `<<0x01, msg::binary>>` | Automerge sync message |
| `0x02` | `<<0x02, to_id::binary-16, data::binary>>` | WebRTC signal to specific peer |

### Server → Client

| Tag | Frame | Meaning |
|---|---|---|
| `0x10` | `<<0x10, my_id::binary-16>>` | Welcome — your assigned client ID |
| `0x11` | `<<0x11, msg::binary>>` | Automerge sync message from server |
| `0x12` | `<<0x12, from_id::binary-16, data::binary>>` | WebRTC signal from peer |
| `0x13` | `<<0x13, peer_id::binary-16>>` | Peer joined |
| `0x14` | `<<0x14, peer_id::binary-16>>` | Peer left |

Client IDs are 16 bytes from `:crypto.strong_rand_bytes(16)`.

---

## Room Lifecycle

1. Client connects to `ws://host/rooms/:room_id`
2. Connection handler calls `registry.get_or_create(room_id)` → Room actor spawned if new
3. Room assigns the client a random 16-byte ID, sends `welcome` frame
4. Room calls `generate_sync_message` for the new client → sends initial sync frame if `Some`
5. Room broadcasts `peer_joined` to all existing peers
6. Client sends sync frames → Room calls `receive_sync_message`, then fans out
   `generate_sync_message` to all connected peers (sends if `Some`)
7. Client disconnects (clean or TCP drop) → Mist `on_close` → Room receives `Leave` →
   removes peer from map, broadcasts `peer_left`
8. Room actor stays alive after all clients leave (doc preserved in memory)

---

## Error Handling

| Scenario | Behaviour |
|---|---|
| `receive_sync_message` returns `Error(_)` | Drop frame silently (non-sync frames can arrive legitimately via the sync pump) |
| Unknown frame tag | Drop silently |
| Room actor crashes | Its clients disconnect (Mist WS closes); Registry removes entry; no restart |
| Client TCP drop | Mist fires `on_close` → normal `Leave` path |

---

## Testing

- **Unit:** `protocol.gleam` encode/decode round-trips for every frame type
- **Integration:** Two in-process connections to the same room — assert automerge sync
  converges (mirrors the two-doc sync pattern from the automerge NIF tests)
- **Signaling relay:** Client A sends a signal frame addressed to client B — assert B
  receives the correct `0x12` frame with A's ID and the payload

---

## Out of scope (v1)

- Authentication / authorisation
- Persistence across restarts
- Horizontal scaling / BEAM distribution
- WebRTC media (server is signaling relay only)
- Broader automerge surface (map/list mutations, change inspection)
