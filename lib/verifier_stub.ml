type t = unit
type config = unit

let name = "stub"
let version _t = "0.1.0-stub"
let create () = ()

let run () ~workdir ~focus =
  let _ = workdir in
  let _ = focus in
  `Ok Verifier.{
    by_property   = [];
    raw_exit_code = 0;
    stdout_path   = "";
    stderr_path   = "";
    duration_ms   = 0;
  }
