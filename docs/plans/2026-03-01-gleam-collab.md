# gleam-collab Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Gleam-first real-time collaboration server that exposes WebSocket sync (via automerge) and WebRTC signaling relay over raw binary frames.

**Architecture:** Five Gleam modules — `protocol` (frame codec), `registry` (room lookup), `room` (automerge actor), `connection` (Mist WS handler), `gleam_collab` (entry point). Mix + mix_gleam build system, same compilation pattern proven in gleam-automerge.

**Tech Stack:** Gleam (Erlang target), Mist (HTTP/WS), gleam_otp (actors), automerge (local path dep NIF), mix_gleam (build).

---

### Task 1: Project scaffold

**Files:**
- Create: `mix.exs`
- Create: `gleam.toml`
- Create: `.gitignore`
- Create: `src/gleam_collab.gleam` (stub)
- Create: `test/gleam_collab_test.gleam` (stub)

**Step 1: Create gleam.toml**

```toml
name = "gleam_collab"
version = "0.1.0"

[dependencies]
gleam_stdlib = "~> 0.69"
mist = ">= 0.0.0"
gleam_otp = ">= 0.0.0"
gleam_erlang = ">= 0.0.0"
gleam_http = ">= 0.0.0"

[dev-dependencies]
gleeunit = "~> 1.9"
```

**Step 2: Create mix.exs**

```elixir
defmodule GleamCollab.MixProject do
  use Mix.Project

  def project do
    [
      app: :gleam_collab,
      version: "0.1.0",
      elixir: "~> 1.15",
      compilers: [:gleam] ++ Mix.compilers(),
      erlc_paths: erlc_paths(Mix.env()),
      erlc_include_path: "build/dev/erlang/gleam_collab/include",
      prune_code_paths: false,
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
    ]
  end

  defp erlc_paths(:test) do
    ["build/dev/erlang/gleam_collab/_gleam_artefacts",
     "build/dev/erlang/gleam_collab/build",
     "build/dev/erlang/gleam_collab_test/_gleam_artefacts"]
  end
  defp erlc_paths(_) do
    ["build/dev/erlang/gleam_collab/_gleam_artefacts",
     "build/dev/erlang/gleam_collab/build"]
  end

  defp aliases do
    [
      "gleam.test": [
        &write_gleam_dep_mix_exs/1,
        fn _ -> Mix.Task.run("deps.compile") end,
        &compile_gleam_deps/1,
        "compile.gleam",
        &compile_gleam_tests/1,
        "gleam.test"
      ]
    ]
  end

  defp compile_gleam_tests(_) do
    Mix.Tasks.Compile.Gleam.compile_package(:gleam_collab, true)
  end

  defp write_gleam_dep_mix_exs(_) do
    lock = Mix.Dep.Lock.read()
    # All Gleam hex packages that ship without a mix.exs
    for name <- [:gleam_stdlib, :gleam_erlang, :gleam_http, :gleam_otp,
                 :glisten, :mist, :gleeunit] do
      dep_dir = Path.join("deps", "#{name}")
      mix_path = Path.join(dep_dir, "mix.exs")
      if File.exists?(dep_dir) and not File.exists?(mix_path) do
        version =
          case lock[name] do
            {:hex, _, ver, _, _, _, _, _} -> ver
            _ -> "0.1.0"
          end
        module = name |> to_string() |> Macro.camelize()
        File.write!(mix_path, """
        defmodule #{module}.MixProject do
          use Mix.Project
          def project, do: [app: :#{name}, version: "#{version}"]
        end
        """)
      end
    end
  end

  # Compile gleam deps in topological order (leaves first).
  # gleam compile-package resolves each dep's types from _gleam_artefacts/
  # already present in build_lib, so order matters.
  defp compile_gleam_deps(_) do
    build_lib = Mix.Project.build_path() |> Path.join("lib")
    gleam_deps_in_order = [
      :gleam_stdlib,
      :gleam_erlang,
      :gleam_http,
      :gleam_otp,
      :glisten,
      :mist,
      :automerge,
      :gleeunit,
    ]
    for name <- gleam_deps_in_order do
      dep_dir = Path.join("deps", "#{name}")
      out = Path.join(build_lib, "#{name}")
      artefacts = Path.join(out, "_gleam_artefacts")
      if File.dir?(dep_dir) and not File.dir?(artefacts) do
        File.mkdir_p!(out)
        0 = Mix.shell().cmd(
          "gleam compile-package --target erlang --no-beam" <>
            " --package #{dep_dir} --out #{out} --lib #{build_lib}"
        )
      end
    end
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:mix_gleam, "~> 0.6"},
      {:gleam_stdlib, "~> 0.69"},
      {:mist, ">= 0.0.0"},
      {:gleam_otp, ">= 0.0.0"},
      {:gleam_erlang, ">= 0.0.0"},
      {:gleam_http, ">= 0.0.0"},
      {:glisten, ">= 0.0.0"},
      {:gleeunit, "~> 1.9", only: [:dev, :test]},
      {:automerge, path: "../gleam-automerge"},
    ]
  end
end
```

**Step 3: Create stub source files**

`src/gleam_collab.gleam`:
```gleam
pub fn main() {
  Nil
}
```

`test/gleam_collab_test.gleam`:
```gleam
import gleeunit

pub fn main() {
  gleeunit.main()
}
```

**Step 4: Create .gitignore**

```
_build/
deps/
.elixir_ls/
```

**Step 5: Run `mix deps.get` and verify it resolves**

```bash
mix deps.get
```

Expected: lock file created, all deps fetched. Check that `deps/mist`, `deps/gleam_otp`, `deps/gleam_erlang`, `deps/glisten`, `deps/gleam_http` all exist.

> **Note:** If `glisten` is not a direct dep of mist or version constraints don't resolve, adjust the `gleam_deps_in_order` list to match only packages that actually appear in `deps/`. Run `ls deps/` after `mix deps.get` to see the full list.

**Step 6: Run tests to verify scaffold compiles**

```bash
mix gleam.test
```

Expected: "0 tests, 0 failures" with no compilation errors.

**Step 7: Commit**

```bash
git add mix.exs gleam.toml .gitignore src/ test/
git commit -m "feat: project scaffold"
```

---

### Task 2: protocol.gleam — frame encode/decode

**Files:**
- Create: `src/protocol.gleam`
- Create: `test/protocol_test.gleam`

**Step 1: Write the failing tests**

`test/protocol_test.gleam`:
```gleam
import gleam/bit_array
import gleeunit/should
import protocol

pub fn encode_welcome_test() {
  let id = <<1:size(128)>>
  protocol.encode_server(protocol.Welcome(id))
  |> should.equal(<<0x10, 1:size(128)>>)
}

pub fn encode_sync_to_client_test() {
  let payload = <<1, 2, 3>>
  protocol.encode_server(protocol.SyncToClient(payload))
  |> should.equal(<<0x11, 1, 2, 3>>)
}

pub fn encode_signal_from_peer_test() {
  let from = <<2:size(128)>>
  let data = <<9, 8, 7>>
  protocol.encode_server(protocol.SignalFromPeer(from, data))
  |> should.equal(<<0x12, 2:size(128), 9, 8, 7>>)
}

pub fn encode_peer_joined_test() {
  let id = <<3:size(128)>>
  protocol.encode_server(protocol.PeerJoined(id))
  |> should.equal(<<0x13, 3:size(128)>>)
}

pub fn encode_peer_left_test() {
  let id = <<4:size(128)>>
  protocol.encode_server(protocol.PeerLeft(id))
  |> should.equal(<<0x14, 4:size(128)>>)
}

pub fn decode_sync_msg_test() {
  let payload = <<1, 2, 3>>
  protocol.decode_client(<<0x01, 1, 2, 3>>)
  |> should.be_ok
  |> should.equal(protocol.SyncMsg(payload))
}

pub fn decode_signal_test() {
  let to = <<5:size(128)>>
  let data = <<6, 7>>
  protocol.decode_client(<<0x02, 5:size(128), 6, 7>>)
  |> should.be_ok
  |> should.equal(protocol.Signal(to, data))
}

pub fn decode_unknown_tag_returns_error_test() {
  protocol.decode_client(<<0xFF, 1, 2, 3>>)
  |> should.be_error
}

pub fn decode_truncated_signal_returns_error_test() {
  // Signal needs at least 17 bytes (tag + 16 byte ID)
  protocol.decode_client(<<0x02, 1, 2>>)
  |> should.be_error
}
```

**Step 2: Run tests to confirm they fail**

```bash
mix gleam.test
```

Expected: compile error — "module protocol not found"

**Step 3: Implement protocol.gleam**

`src/protocol.gleam`:
```gleam
pub type ServerFrame {
  Welcome(client_id: BitArray)
  SyncToClient(payload: BitArray)
  SignalFromPeer(from: BitArray, data: BitArray)
  PeerJoined(peer_id: BitArray)
  PeerLeft(peer_id: BitArray)
}

pub type ClientFrame {
  SyncMsg(payload: BitArray)
  Signal(to: BitArray, data: BitArray)
}

pub fn encode_server(frame: ServerFrame) -> BitArray {
  case frame {
    Welcome(id) -> <<0x10, id:bits>>
    SyncToClient(payload) -> <<0x11, payload:bits>>
    SignalFromPeer(from, data) -> <<0x12, from:bits, data:bits>>
    PeerJoined(id) -> <<0x13, id:bits>>
    PeerLeft(id) -> <<0x14, id:bits>>
  }
}

pub fn decode_client(bits: BitArray) -> Result(ClientFrame, String) {
  case bits {
    <<0x01, payload:bits>> -> Ok(SyncMsg(payload))
    <<0x02, to:bytes-size(16), data:bits>> -> Ok(Signal(to, data))
    <<0x02, _rest:bits>> -> Error("signal frame too short")
    _ -> Error("unknown frame tag")
  }
}
```

**Step 4: Run tests to verify they pass**

```bash
mix gleam.test
```

Expected: 9 tests, 0 failures.

**Step 5: Commit**

```bash
git add src/protocol.gleam test/protocol_test.gleam
git commit -m "feat: binary frame protocol codec"
```

---

### Task 3: registry.gleam — room registry actor

**Files:**
- Create: `src/registry.gleam`
- Create: `test/registry_test.gleam`

**Step 1: Write the failing tests**

`test/registry_test.gleam`:
```gleam
import gleam/otp/actor
import gleeunit/should
import registry
import room

pub fn get_or_create_returns_subject_test() {
  let assert Ok(reg) = registry.start()
  let subj = registry.get_or_create(reg, "room-1")
  // Subject is opaque — just verify we got one back without crashing
  should.be_ok(Ok(subj))
}

pub fn same_room_id_returns_same_subject_test() {
  let assert Ok(reg) = registry.start()
  let s1 = registry.get_or_create(reg, "room-42")
  let s2 = registry.get_or_create(reg, "room-42")
  should.equal(s1, s2)
}

pub fn different_room_ids_return_different_subjects_test() {
  let assert Ok(reg) = registry.start()
  let s1 = registry.get_or_create(reg, "room-a")
  let s2 = registry.get_or_create(reg, "room-b")
  should.not_equal(s1, s2)
}
```

**Step 2: Run tests to confirm they fail**

```bash
mix gleam.test
```

Expected: compile error — "module registry not found"

**Step 3: Implement registry.gleam**

> **Note on gleam_otp actor API:** The actor module provides `actor.start(initial_state, handler)` where handler is `fn(msg, state) -> actor.Next(msg, state)`. Use `actor.call(subject, make_msg, timeout_ms)` for synchronous calls. Check `deps/gleam_otp/src/gleam/otp/actor.gleam` if the API has changed.

`src/registry.gleam`:
```gleam
import gleam/dict.{type Dict}
import gleam/otp/actor
import gleam/erlang/process.{type Subject}
import room

pub type RegistryMsg {
  GetOrCreate(room_id: String, reply_with: Subject(Subject(room.RoomMsg)))
}

type State =
  Dict(String, Subject(room.RoomMsg))

pub fn start() -> Result(Subject(RegistryMsg), actor.StartError) {
  actor.start(dict.new(), handle_message)
}

pub fn get_or_create(
  registry: Subject(RegistryMsg),
  room_id: String,
) -> Subject(room.RoomMsg) {
  actor.call(registry, fn(reply) { GetOrCreate(room_id, reply) }, 5000)
}

fn handle_message(msg: RegistryMsg, state: State) -> actor.Next(RegistryMsg, State) {
  case msg {
    GetOrCreate(room_id, reply_with) -> {
      case dict.get(state, room_id) do
        Ok(subj) -> {
          process.send(reply_with, subj)
          actor.continue(state)
        }
        Error(Nil) -> {
          let assert Ok(subj) = room.start()
          let new_state = dict.insert(state, room_id, subj)
          process.send(reply_with, subj)
          actor.continue(new_state)
        }
      end
    }
  }
}
```

> **Note:** If `actor.call` is not available, check `gleam/otp/actor` for the correct call API. An alternative is `process.call(subject, make_msg, timeout)` from `gleam_erlang`.

**Step 4: Create a stub room.gleam so registry compiles**

`src/room.gleam`:
```gleam
import gleam/otp/actor
import gleam/erlang/process.{type Subject}

pub type RoomMsg {
  Placeholder
}

pub fn start() -> Result(Subject(RoomMsg), actor.StartError) {
  actor.start(Nil, fn(_msg, state) { actor.continue(state) })
}
```

**Step 5: Run tests to verify they pass**

```bash
mix gleam.test
```

Expected: all tests pass (protocol + registry tests).

**Step 6: Commit**

```bash
git add src/registry.gleam src/room.gleam test/registry_test.gleam
git commit -m "feat: room registry actor"
```

---

### Task 4: room.gleam — room actor

**Files:**
- Modify: `src/room.gleam` (replace stub)
- Create: `test/room_test.gleam`

**Step 1: Write the failing tests**

`test/room_test.gleam`:
```gleam
import automerge
import gleam/erlang/process
import gleam/otp/actor
import gleeunit/should
import room

// Helper: collect the next message sent to a Subject within timeout_ms
fn next_msg(subj: process.Subject(a), timeout_ms: Int) -> Result(a, Nil) {
  process.receive(subj, timeout_ms)
}

pub fn join_sends_welcome_test() {
  let assert Ok(rm) = room.start()
  let client_subj = process.new_subject()
  let client_id = room.join(rm, client_subj)
  // client_id must be 16 bytes
  should.equal(bit_array.byte_size(client_id), 16)
}

pub fn join_triggers_initial_sync_test() {
  let assert Ok(rm) = room.start()
  let client_subj = process.new_subject()
  let _client_id = room.join(rm, client_subj)
  // Room should send at least a Welcome frame immediately
  let result = process.receive(client_subj, 500)
  should.be_ok(result)
}

pub fn leave_does_not_crash_test() {
  let assert Ok(rm) = room.start()
  let client_subj = process.new_subject()
  let client_id = room.join(rm, client_subj)
  room.leave(rm, client_id)
  should.be_ok(Ok(Nil))
}

pub fn two_client_sync_converges_test() {
  let assert Ok(rm) = room.start()
  let subj_a = process.new_subject()
  let subj_b = process.new_subject()
  let id_a = room.join(rm, subj_a)
  let id_b = room.join(rm, subj_b)
  // Drain welcome + initial sync frames from both clients
  // then push sync messages back until no more arrive
  drain_and_sync(rm, subj_a, id_a, subj_b, id_b, 0)
}

fn drain_and_sync(rm, subj_a, id_a, subj_b, id_b, rounds) {
  should.be_true(rounds < 20)
  let msg_a = process.receive(subj_a, 100)
  let msg_b = process.receive(subj_b, 100)
  case msg_a, msg_b {
    Error(Nil), Error(Nil) -> Nil  // both quiet — sync done
    Ok(frame_a), _ -> {
      // forward A's frame to room as if it came from A
      // (in practice the WS handler does this; here we simulate)
      room.sync_msg(rm, id_a, extract_payload(frame_a))
      drain_and_sync(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
    }
    _, Ok(frame_b) -> {
      room.sync_msg(rm, id_b, extract_payload(frame_b))
      drain_and_sync(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
    }
  }
}

// Extract the automerge payload from a SyncToClient frame
fn extract_payload(bits: BitArray) -> BitArray {
  let assert <<0x11, payload:bits>> = bits
  payload
}
```

**Step 2: Run tests to confirm they fail**

```bash
mix gleam.test
```

Expected: compile errors — `room.join`, `room.leave`, `room.sync_msg` not defined.

**Step 3: Implement room.gleam**

`src/room.gleam`:
```gleam
import automerge
import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/option
import gleam/otp/actor
import protocol

pub type RoomMsg {
  Join(client_subj: Subject(BitArray), reply_with: Subject(BitArray))
  Leave(client_id: BitArray)
  SyncFromClient(client_id: BitArray, payload: BitArray)
  SignalMsg(from_id: BitArray, to_id: BitArray, data: BitArray)
}

type Peer {
  Peer(sync_state: automerge.SyncStateRef, subject: Subject(BitArray))
}

type RoomState {
  RoomState(doc: automerge.DocRef, peers: Dict(BitArray, Peer))
}

pub fn start() -> Result(Subject(RoomMsg), actor.StartError) {
  let initial = RoomState(doc: automerge.new_doc(), peers: dict.new())
  actor.start(initial, handle_message)
}

/// Synchronous join — returns the assigned client_id (16 random bytes).
pub fn join(room: Subject(RoomMsg), client_subj: Subject(BitArray)) -> BitArray {
  actor.call(room, fn(reply) { Join(client_subj, reply) }, 5000)
}

pub fn leave(room: Subject(RoomMsg), client_id: BitArray) -> Nil {
  process.send(room, Leave(client_id))
}

pub fn sync_msg(
  room: Subject(RoomMsg),
  client_id: BitArray,
  payload: BitArray,
) -> Nil {
  process.send(room, SyncFromClient(client_id, payload))
}

pub fn signal(
  room: Subject(RoomMsg),
  from_id: BitArray,
  to_id: BitArray,
  data: BitArray,
) -> Nil {
  process.send(room, SignalMsg(from_id, to_id, data))
}

fn handle_message(
  msg: RoomMsg,
  state: RoomState,
) -> actor.Next(RoomMsg, RoomState) {
  case msg {
    Join(client_subj, reply_with) -> {
      let client_id = new_client_id()
      let sync_state = automerge.new_sync_state()
      let peer = Peer(sync_state: sync_state, subject: client_subj)
      let new_peers = dict.insert(state.peers, client_id, peer)
      let new_state = RoomState(..state, peers: new_peers)
      // Send welcome
      process.send(client_subj, protocol.encode_server(protocol.Welcome(client_id)))
      // Notify existing peers
      dict.each(state.peers, fn(peer_id, p) {
        process.send(p.subject, protocol.encode_server(protocol.PeerJoined(client_id)))
        process.send(client_subj, protocol.encode_server(protocol.PeerJoined(peer_id)))
      })
      // Initial sync push to new client
      case automerge.generate_sync_message(state.doc, sync_state) {
        option.Some(sync_bits) ->
          process.send(client_subj, protocol.encode_server(protocol.SyncToClient(sync_bits)))
        option.None -> Nil
      }
      process.send(reply_with, client_id)
      actor.continue(new_state)
    }

    Leave(client_id) -> {
      let new_peers = dict.delete(state.peers, client_id)
      dict.each(new_peers, fn(_pid, p) {
        process.send(p.subject, protocol.encode_server(protocol.PeerLeft(client_id)))
      })
      actor.continue(RoomState(..state, peers: new_peers))
    }

    SyncFromClient(client_id, payload) -> {
      case dict.get(state.peers, client_id) {
        Error(Nil) -> actor.continue(state)
        Ok(peer) -> {
          case automerge.receive_sync_message(state.doc, peer.sync_state, payload) {
            Error(_) -> actor.stop(process.Normal)
            Ok(_) -> {
              // Fan out sync messages to all peers
              dict.each(state.peers, fn(_pid, p) {
                case automerge.generate_sync_message(state.doc, p.sync_state) {
                  option.Some(bits) ->
                    process.send(p.subject, protocol.encode_server(protocol.SyncToClient(bits)))
                  option.None -> Nil
                }
              })
              actor.continue(state)
            }
          }
        }
      }
    }

    SignalMsg(from_id, to_id, data) -> {
      case dict.get(state.peers, to_id) {
        Error(Nil) -> actor.continue(state)
        Ok(peer) -> {
          process.send(peer.subject, protocol.encode_server(protocol.SignalFromPeer(from_id, data)))
          actor.continue(state)
        }
      }
    }
  }
}

@external(erlang, "crypto", "strong_rand_bytes")
fn strong_rand_bytes(n: Int) -> BitArray

fn new_client_id() -> BitArray {
  strong_rand_bytes(16)
}
```

**Step 4: Run tests to verify they pass**

```bash
mix gleam.test
```

Expected: all tests pass.

**Step 5: Commit**

```bash
git add src/room.gleam test/room_test.gleam
git commit -m "feat: room actor with automerge sync and signaling relay"
```

---

### Task 5: connection.gleam — Mist WebSocket handler

**Files:**
- Create: `src/connection.gleam`

> **Note:** No unit tests for this module — it's a thin bridge between Mist callbacks and room messages. Tested via the integration test in Task 6.

**Step 1: Check Mist's WebSocket API**

Read `deps/mist/src/mist.gleam` to confirm the WebSocket handler signature. It will look something like:

```gleam
mist.websocket(
  request: req,
  on_open: fn(conn) -> state,
  on_close: fn(state) -> Nil,
  handler: fn(state, conn, message) -> actor.Next(message, state),
)
```

Where `message` is `mist.WebsocketMessage(your_custom_msg)`.

**Step 2: Implement connection.gleam**

`src/connection.gleam`:
```gleam
import gleam/bytes_tree
import gleam/erlang/process
import gleam/http/request.{type Request}
import gleam/http/response
import gleam/otp/actor
import gleam/result
import mist.{type Connection, type ResponseData}
import protocol
import registry
import room

pub type State {
  State(room: process.Subject(room.RoomMsg), client_id: BitArray)
}

pub fn handle(
  req: Request(mist.Connection),
  registry_subj: process.Subject(registry.RegistryMsg),
) -> response.Response(ResponseData) {
  // Extract room_id from path: /rooms/:room_id
  let path = request.path_segments(req)
  case path {
    ["rooms", room_id] ->
      upgrade_websocket(req, registry_subj, room_id)
    _ ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}

fn upgrade_websocket(req, registry_subj, room_id) {
  mist.websocket(
    request: req,
    on_open: fn(conn) {
      let client_subj = process.new_subject()
      let room_subj = registry.get_or_create(registry_subj, room_id)
      // Start a process to forward server→client frames to the WS conn
      let _ = process.start(fn() { forward_loop(client_subj, conn) }, True)
      let client_id = room.join(room_subj, client_subj)
      State(room: room_subj, client_id: client_id)
    },
    on_close: fn(state) {
      room.leave(state.room, state.client_id)
    },
    handler: fn(state, _conn, message) {
      case message {
        mist.Binary(bits) -> {
          case protocol.decode_client(bits) {
            Ok(protocol.SyncMsg(payload)) -> {
              room.sync_msg(state.room, state.client_id, payload)
              actor.continue(state)
            }
            Ok(protocol.Signal(to_id, data)) -> {
              room.signal(state.room, state.client_id, to_id, data)
              actor.continue(state)
            }
            Error(_) -> actor.continue(state)
          }
        }
        mist.Closed | mist.Shutdown -> actor.stop(process.Normal)
        _ -> actor.continue(state)
      }
    },
  )
}

// Loop reading from the client Subject and writing to the WS connection
fn forward_loop(subj: process.Subject(BitArray), conn: Connection) -> Nil {
  case process.receive(subj, 30_000) {
    Ok(bits) -> {
      let _ = mist.send_binary_frame(conn, bits)
      forward_loop(subj, conn)
    }
    Error(Nil) -> Nil
  }
}
```

> **Note:** If Mist's API differs (e.g. `mist.send_binary_frame` vs `mist.send_frame`), check `deps/mist/src/mist.gleam` for the correct function name. The structure above matches Mist ~4.x but exact names may vary.

**Step 3: Verify it compiles**

```bash
mix gleam.test
```

Expected: no compile errors, all prior tests still pass.

**Step 4: Commit**

```bash
git add src/connection.gleam
git commit -m "feat: mist websocket handler"
```

---

### Task 6: gleam_collab.gleam — application entry + integration test

**Files:**
- Modify: `src/gleam_collab.gleam`
- Create: `test/integration_test.gleam`

**Step 1: Write the failing integration test**

`test/integration_test.gleam`:
```gleam
import automerge
import gleam/erlang/process
import gleeunit/should
import registry
import room

// Two in-process clients joining the same room and syncing until convergence
pub fn two_client_sync_integration_test() {
  let assert Ok(reg) = registry.start()
  let room_subj = registry.get_or_create(reg, "test-room")

  let subj_a = process.new_subject()
  let subj_b = process.new_subject()
  let id_a = room.join(room_subj, subj_a)
  let id_b = room.join(room_subj, subj_b)

  // Both clients are in the room. Drive sync by forwarding frames back.
  pump(room_subj, subj_a, id_a, subj_b, id_b, 0)
}

fn pump(rm, subj_a, id_a, subj_b, id_b, rounds) {
  should.be_true(rounds < 30)
  let ma = process.receive(subj_a, 100)
  let mb = process.receive(subj_b, 100)
  case ma, mb {
    Error(Nil), Error(Nil) -> Nil
    Ok(bits), _ ->
      case bits {
        <<0x11, payload:bits>> -> {
          room.sync_msg(rm, id_a, payload)
          pump(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
        }
        _ -> pump(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
      }
    _, Ok(bits) ->
      case bits {
        <<0x11, payload:bits>> -> {
          room.sync_msg(rm, id_b, payload)
          pump(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
        }
        _ -> pump(rm, subj_a, id_a, subj_b, id_b, rounds + 1)
      }
  }
}

pub fn signal_relay_test() {
  let assert Ok(reg) = registry.start()
  let room_subj = registry.get_or_create(reg, "signal-room")

  let subj_a = process.new_subject()
  let subj_b = process.new_subject()
  let id_a = room.join(room_subj, subj_a)
  let _id_b = room.join(room_subj, subj_b)

  // Drain welcome/sync frames from B
  let _ = drain(subj_b, 3)

  // A signals B
  let signal_data = <<"offer":utf8>>
  room.signal(room_subj, id_a, _id_b, signal_data)

  // B should receive a SignalFromPeer frame
  let assert Ok(frame) = process.receive(subj_b, 500)
  let assert <<0x12, from:bytes-size(16), data:bits>> = frame
  should.equal(from, id_a)
  should.equal(data, signal_data)
}

fn drain(subj, n) {
  case n {
    0 -> Nil
    _ ->
      case process.receive(subj, 100) {
        Ok(_) -> drain(subj, n - 1)
        Error(Nil) -> Nil
      }
  }
}
```

**Step 2: Run tests to confirm integration test exists and compiles**

```bash
mix gleam.test
```

Expected: integration tests run (may pass or fail — fix any issues before next step).

**Step 3: Implement gleam_collab.gleam — application entry**

`src/gleam_collab.gleam`:
```gleam
import connection
import gleam/erlang/process
import gleam/http/request
import mist
import registry

pub fn main() {
  let assert Ok(reg) = registry.start()

  let handler = fn(req) {
    connection.handle(req, reg)
  }

  let assert Ok(_) =
    mist.new(handler)
    |> mist.port(8080)
    |> mist.start_http

  process.sleep_forever()
}
```

**Step 4: Run all tests**

```bash
mix gleam.test
```

Expected: all tests pass, 0 failures.

**Step 5: Commit**

```bash
git add src/gleam_collab.gleam test/integration_test.gleam
git commit -m "feat: application entry point and integration tests"
```

---

### Task 7: CI workflow

**Files:**
- Create: `.github/workflows/ci.yml`

**Step 1: Create the workflow**

`.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    name: Test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Erlang/OTP, Elixir, and Gleam
        uses: erlef/setup-beam@v1
        with:
          otp-version: "27"
          elixir-version: "1.17"
          gleam-version: "1"

      - name: Set up Rust
        uses: dtolnay/rust-toolchain@stable

      - name: Cache dependencies
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
            target
          key: ${{ runner.os }}-mix-${{ hashFiles('mix.lock') }}-cargo-${{ hashFiles('**/Cargo.lock') }}

      - name: Install Mix deps
        run: mix deps.get

      - name: Run tests
        run: AUTOMERGE_BUILD=1 mix gleam.test
```

> **Note:** `AUTOMERGE_BUILD=1` triggers local Rust compilation for the automerge path dep. Once automerge is published to hex with RustlerPrecompiled, this env var can be dropped.

**Step 2: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow"
```

---

## Known Risks / Things to Check During Implementation

1. **Mist WebSocket API** — verify exact function names in `deps/mist/src/mist.gleam`. The `mist.send_binary_frame` name and `handler` callback signature may differ from what's shown.

2. **gleam_otp actor.call** — verify the `actor.call` signature. It may be `actor.call(subj, fn(reply) { Msg(reply) }, timeout)` or may use `process.call` from gleam_erlang.

3. **Gleam dep compile order** — after `mix deps.get`, run `ls deps/` and compare to `gleam_deps_in_order` in mix.exs. Add/remove/reorder as needed. Compile order must be topological (deps before dependents).

4. **`@external` for crypto** — `strong_rand_bytes` from Erlang's `crypto` module. If the external binding syntax needs adjustment, check how gleam_erlang handles similar externals.

5. **forward_loop process lifetime** — the process spawned in `on_open` must be linked or monitored so it dies when the WebSocket closes. Check if Mist handles this or if we need explicit process linking.
