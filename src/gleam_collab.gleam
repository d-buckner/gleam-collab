import connection
import gleam/erlang/process
import mist
import registry

pub fn main() {
  let assert Ok(reg) = registry.start()

  let assert Ok(_) =
    mist.new(fn(req) { connection.handle(req, reg) })
    |> mist.port(8080)
    |> mist.start

  process.sleep_forever()
}
