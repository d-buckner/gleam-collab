defmodule WsTestClient do
  def find_free_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end

  def connect(port, path) do
    {:ok, conn} = :gun.open(~c"localhost", port, %{protocols: [:http]})
    {:ok, _protocol} = :gun.await_up(conn, 2000)
    stream = :gun.ws_upgrade(conn, path)

    receive do
      {:gun_upgrade, ^conn, ^stream, [<<"websocket">>], _headers} ->
        {:ok, {conn, stream}}
    after
      2000 -> {:error, :upgrade_timeout}
    end
  end

  def send_binary(conn, stream, data) do
    :gun.ws_send(conn, stream, {:binary, data})
  end

  def recv(conn, timeout_ms \\ 1000) do
    receive do
      {:gun_ws, ^conn, _stream, {:binary, frame}} -> {:ok, frame}
      {:gun_ws, ^conn, _stream, :close} -> {:error, :closed}
    after
      timeout_ms -> {:error, :timeout}
    end
  end

  def close(conn) do
    :gun.close(conn)
  end

  def http_get_status(port, path) do
    {:ok, conn} = :gun.open(~c"localhost", port, %{protocols: [:http]})
    {:ok, _protocol} = :gun.await_up(conn, 1000)
    stream = :gun.get(conn, path)
    {:response, :fin, status, _headers} = :gun.await(conn, stream, 1000)
    :gun.close(conn)
    status
  end
end
