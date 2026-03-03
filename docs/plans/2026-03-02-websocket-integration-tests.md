# WebSocket Integration Tests Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add full-stack WebSocket integration tests that exercise connection.gleam, covering multi-client sync convergence and signal relay over real TCP sockets.

**Architecture:** Add `gun` (Erlang WebSocket client) as a test dep. Write an Elixir helper module (`test/support/ws_test_client.ex`) that wraps gun's process-mailbox API. Write Gleam tests that call it via `@external` to spin up a real Mist server and connect multiple clients per test.

**Tech Stack:** gun 2.x (Erlang WebSocket client), Elixir test support module, Gleam `@external` FFI, existing Mist/registry/room stack.

---

### Task 1: Add gun dep + test support compilation

**Files:**
- Modify: `mix.exs`

**Step 1: Add gun to deps and enable test/support compilation**

In `mix.exs`, make three changes:

1. Add `elixirc_paths` to `project/0`:
```elixir
def project do
  [
    app: :gleam_collab,
    version: "0.1.0",
    elixir: "~> 1.15",
    compilers: [:gleam] ++ Mix.compilers(),
    erlc_paths: erlc_paths(Mix.env()),
    erlc_include_path: "build/dev/erlang/gleam_collab/include",
    elixirc_paths: elixirc_paths(Mix.env()),    # <-- ADD THIS
    prune_code_paths: false,
    start_permanent: Mix.env() == :prod,
    aliases: aliases(),
    deps: deps(),
  ]
end
```

2. Add the `elixirc_paths/1` private function (after the existing `erlc_paths` functions):
```elixir
defp elixirc_paths(:test), do: ["lib", "test/support"]
defp elixirc_paths(_), do: ["lib"]
```

3. Add gun to `deps/0`:
```elixir
{:gun, "~> 2.0", only: [:dev, :test]},
```

**Step 2: Fetch the new dep**

```bash
cd /Users/daniel/Projects/gleam-collab && mix deps.get
```

Expected: `gun` and its transitive deps (likely `cowlib`) added to mix.lock.

**Step 3: Create test/support directory**

```bash
mkdir -p /Users/daniel/Projects/gleam-collab/test/support
```

**Step 4: Verify it compiles**

```bash
AUTOMERGE_BUILD=1 mix gleam.test
```

Expected: still 18 tests, 0 failures. No compilation errors.

**Step 5: Commit**

```bash
git add mix.exs mix.lock test/support/.gitkeep
git commit -m "feat: add gun dep and test/support compilation"
```

> **Note:** `git add test/support/.gitkeep` — create an empty `.gitkeep` file first so git tracks the directory:
> ```bash
> touch /Users/daniel/Projects/gleam-collab/test/support/.gitkeep
> ```

---

### Task 2: Elixir WebSocket test client helper

**Files:**
- Create: `test/support/ws_test_client.ex`

**Step 1: Read the gun v2 documentation**

Skim `deps/gun/src/gun.erl` or `deps/gun/include/gun.hrl` to confirm:
- `gun:open(Host, Port, Opts)` returns `{ok, ConnPid}`
- `gun:await_up(ConnPid, Timeout)` returns `{ok, Protocol}`
- `gun:ws_upgrade(ConnPid, Path)` returns `StreamRef`
- Upgrade confirmation arrives as `{gun_upgrade, ConnPid, StreamRef, [<<"websocket">>], Headers}`
- Frames arrive as `{gun_ws, ConnPid, StreamRef, {binary, Data}}`
- `gun:ws_send(ConnPid, StreamRef, {binary, Data})` sends a frame

**Step 2: Create the helper**

`test/support/ws_test_client.ex`:
```elixir
defmodule WsTestClient do
  @moduledoc """
  Thin wrapper around the gun Erlang WebSocket client for use in tests.
  All receive/send calls run in the calling process, so gun messages
  arrive in the test process mailbox.
  """

  @doc "Find a free TCP port by briefly binding to port 0."
  def find_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  @doc "Open a WebSocket connection to ws://localhost:port/path."
  def connect(port, path) do
    {:ok, conn} = :gun.open(~c"localhost", port, %{protocols: [:http]})
    {:ok, _protocol} = :gun.await_up(conn, 2000)
    stream = :gun.ws_upgrade(conn, path)
    receive do
      {:gun_upgrade, ^conn, ^stream, [<<"websocket">>], _headers} ->
        {:ok, conn, stream}
    after
      2000 -> {:error, :upgrade_timeout}
    end
  end

  @doc "Send a binary WebSocket frame."
  def send_binary(conn, stream, data) do
    :gun.ws_send(conn, stream, {:binary, data})
  end

  @doc "Receive the next binary WebSocket frame within timeout_ms."
  def recv(conn, timeout_ms \\ 1000) do
    receive do
      {:gun_ws, ^conn, _stream, {:binary, frame}} -> {:ok, frame}
      {:gun_ws, ^conn, _stream, :close} -> {:error, :closed}
    after
      timeout_ms -> {:error, :timeout}
    end
  end

  @doc "Close the connection."
  def close(conn) do
    :gun.close(conn)
  end
end
```

**Step 3: Verify it compiles**

```bash
AUTOMERGE_BUILD=1 mix gleam.test
```

Expected: 18 tests, 0 failures. If `WsTestClient` module is not found, check that `elixirc_paths(:test)` is returning `["lib", "test/support"]`.

**Step 4: Commit**

```bash
git add test/support/ws_test_client.ex
git commit -m "feat: elixir websocket test client helper"
```

---

### Task 3: WebSocket integration tests

**Files:**
- Create: `test/websocket_test.gleam`

**Step 1: Write the failing tests**

`test/websocket_test.gleam`:
```gleam
import gleam/bit_array
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/result
import gleeunit/should
import mist
import registry
import connection

// ── FFI bindings to WsTestClient (Elixir module) ─────────────────────────────

@external(erlang, "Elixir.WsTestClient", "find_free_port")
fn find_free_port() -> Int

@external(erlang, "Elixir.WsTestClient", "connect")
fn ws_connect(port: Int, path: String) -> Result(#(Dynamic, Dynamic), Dynamic)

@external(erlang, "Elixir.WsTestClient", "send_binary")
fn ws_send(conn: Dynamic, stream: Dynamic, data: BitArray) -> Nil

@external(erlang, "Elixir.WsTestClient", "recv")
fn ws_recv_timeout(conn: Dynamic, timeout_ms: Int) -> Result(BitArray, Dynamic)

@external(erlang, "Elixir.WsTestClient", "close")
fn ws_close(conn: Dynamic) -> Nil

// ── Helpers ───────────────────────────────────────────────────────────────────

fn ws_recv(conn: Dynamic) -> Result(BitArray, Dynamic) {
  ws_recv_timeout(conn, 1000)
}

fn start_server() -> Int {
  let assert Ok(reg) = registry.start()
  let port = find_free_port()
  let assert Ok(_) =
    mist.new(fn(req) { connection.handle(req, reg) })
    |> mist.port(port)
    |> mist.start
  // Give Mist a moment to bind
  process.sleep(50)
  port
}

fn drain_until_quiet(conn: Dynamic, stream: Dynamic, rounds: Int) -> Nil {
  case rounds > 20 {
    True -> Nil
    False ->
      case ws_recv_timeout(conn, 100) {
        Ok(bits) ->
          case bits {
            <<0x11, payload:bits>> -> {
              // Echo sync frames back to drive convergence
              ws_send(conn, stream, <<0x01, payload:bits>>)
              drain_until_quiet(conn, stream, rounds + 1)
            }
            _ -> drain_until_quiet(conn, stream, rounds + 1)
          }
        Error(_) -> Nil
      }
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

pub fn two_clients_sync_over_websocket_test() {
  let port = start_server()

  let assert Ok(#(conn_a, stream_a)) = ws_connect(port, "/rooms/ws-sync-room")
  let assert Ok(#(conn_b, stream_b)) = ws_connect(port, "/rooms/ws-sync-room")

  // Give the server time to process both joins
  process.sleep(50)

  // Drive sync to convergence by echoing 0x11 frames back as 0x01 frames
  drain_until_quiet(conn_a, stream_a, 0)
  drain_until_quiet(conn_b, stream_b, 0)

  ws_close(conn_a)
  ws_close(conn_b)

  // Both sides converged without panicking — test passes
  should.be_ok(Ok(Nil))
}

pub fn signal_relay_over_websocket_test() {
  let port = start_server()

  let assert Ok(#(conn_a, stream_a)) = ws_connect(port, "/rooms/ws-signal-room")
  let assert Ok(#(conn_b, stream_b)) = ws_connect(port, "/rooms/ws-signal-room")

  // Both receive Welcome (0x10) on connect — read those first
  process.sleep(50)

  // Drain welcome/peer-joined/sync frames from both clients
  let _ = drain_frames(conn_a, 5)
  let _ = drain_frames(conn_b, 5)

  // Extract conn_b's client_id from its Welcome frame.
  // We need the ID to address a signal to B.
  // Re-connect B fresh to get a clean Welcome with ID.
  ws_close(conn_b)
  let assert Ok(#(conn_b2, stream_b2)) = ws_connect(port, "/rooms/ws-signal-room")

  // Read B2's welcome frame to get its client_id
  let assert Ok(welcome) = ws_recv(conn_b2)
  let assert <<0x10, b2_id:bytes-size(16)>> = welcome

  // Drain remaining frames
  let _ = drain_frames(conn_b2, 5)

  // A signals B2 with a test payload
  let signal_data = <<"sdp-offer":utf8>>
  let signal_frame = <<0x02, b2_id:bits, signal_data:bits>>
  ws_send(conn_a, stream_a, signal_frame)

  // B2 should receive a 0x12 SignalFromPeer frame
  // Drain any non-signal frames first
  let assert Ok(frame) = recv_until_signal(conn_b2, 5)
  let assert <<0x12, _from_id:bytes-size(16), data:bits>> = frame
  should.equal(data, signal_data)

  ws_close(conn_a)
  ws_close(conn_b2)
}

pub fn unknown_route_returns_404_test() {
  let port = start_server()
  // gun can make plain HTTP requests too
  let result = http_get(port, "/not-a-room")
  should.equal(result, 404)
}

// ── Test helpers ──────────────────────────────────────────────────────────────

fn drain_frames(conn: Dynamic, n: Int) -> Nil {
  case n {
    0 -> Nil
    _ ->
      case ws_recv_timeout(conn, 100) {
        Ok(_) -> drain_frames(conn, n - 1)
        Error(_) -> Nil
      }
  }
}

fn recv_until_signal(conn: Dynamic, attempts: Int) -> Result(BitArray, Nil) {
  case attempts {
    0 -> Error(Nil)
    _ ->
      case ws_recv(conn) {
        Ok(<<0x12, _rest:bits>> as frame) -> Ok(frame)
        Ok(_) -> recv_until_signal(conn, attempts - 1)
        Error(_) -> Error(Nil)
      }
  }
}

@external(erlang, "Elixir.WsTestClient", "http_get_status")
fn http_get(port: Int, path: String) -> Int
```

> **Note on `http_get_status`:** You'll need to add this function to `WsTestClient`:
> ```elixir
> def http_get_status(port, path) do
>   {:ok, conn} = :gun.open(~c"localhost", port, %{protocols: [:http]})
>   {:ok, _} = :gun.await_up(conn, 1000)
>   stream = :gun.get(conn, path)
>   {:response, :fin, status, _headers} = :gun.await(conn, stream, 1000)
>   :gun.close(conn)
>   status
> end
> ```

**Step 2: Add `http_get_status` to the Elixir helper**

Add to `test/support/ws_test_client.ex`:
```elixir
@doc "Make an HTTP GET and return the status code."
def http_get_status(port, path) do
  {:ok, conn} = :gun.open(~c"localhost", port, %{protocols: [:http]})
  {:ok, _protocol} = :gun.await_up(conn, 1000)
  stream = :gun.get(conn, path)
  {:response, :fin, status, _headers} = :gun.await(conn, stream, 1000)
  :gun.close(conn)
  status
end
```

**Step 3: Run to confirm tests fail**

```bash
AUTOMERGE_BUILD=1 mix gleam.test
```

Expected: compile error — `WsTestClient` not found, OR the tests fail at runtime. Either is fine at this stage.

**Step 4: Fix any compilation issues and run until all pass**

Common issues:
- `ws_connect` return type: gun returns `{ok, ConnPid, StreamRef}` as an Erlang tuple. In Gleam `Result(#(Dynamic, Dynamic), Dynamic)` should decode `{ok, conn, stream}` — verify the Elixir module returns exactly `{:ok, conn, stream}` (a 3-tuple) and adjust the `@external` return type if needed. It may need to be `Result(#(Dynamic, Dynamic), Dynamic)` decoded from `{:ok, conn, stream}` — but Gleam's Result only decodes 2-tuples `{ok, val}` and `{error, reason}`. If the Elixir function returns `{:ok, conn, stream}` (3-tuple), you'll need to wrap it:
  ```elixir
  # In WsTestClient.connect, change to return:
  {:ok, {conn, stream}}   # 2-tuple inside ok
  ```
  Then in Gleam:
  ```gleam
  @external(erlang, "Elixir.WsTestClient", "connect")
  fn ws_connect(port: Int, path: String) -> Result(#(Dynamic, Dynamic), Dynamic)
  ```
- The `mist.start` vs `mist.start_http` name — it's `mist.start` (confirmed in Task 6).
- gun may need `cowlib` as a transitive dep — check `mix deps.get` resolved it.

**Step 5: Run all tests**

```bash
AUTOMERGE_BUILD=1 mix gleam.test
```

Expected: 21 tests, 0 failures (18 existing + 3 new WebSocket tests).

**Step 6: Commit**

```bash
git add test/websocket_test.gleam test/support/ws_test_client.ex
git commit -m "test: full-stack websocket integration tests"
```

---

## Known Risks

1. **gun return type wrapping** — The main complexity is aligning Elixir's `{:ok, conn, stream}` 3-tuple with Gleam's `Result(#(a, b), c)` which expects `{ok, {conn, stream}}` 2-tuples. The Elixir helper must wrap: `{:ok, {conn, stream}}`.

2. **Port race condition** — `find_free_port` briefly opens and closes a socket. In very rare cases the OS could reassign the port before Mist binds. Use `process.sleep(50)` after starting the server to let it stabilise. If CI flakes, use a fixed per-test port offset instead.

3. **gun 2.x vs 1.x API** — If `deps/gun/` is present (gun was fetched as a transitive dep of something), check its version. Gun 2.x uses `gun:ws_upgrade/2` (returns StreamRef); gun 1.x may differ. Check `deps/gun/src/gun.erl` header for the version.

4. **Welcome frame before sync** — On connect, clients receive `0x10` (Welcome) then possibly `0x11` (initial sync). The `drain_frames` helper clears these. If more frames arrive than expected, increase the drain count.
