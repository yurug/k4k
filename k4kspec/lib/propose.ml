(* Propose — intent-seeded generation (ADR-014): the agent DRAFTS spec + guidance + a decision
   list from prose intent; revise proposes changesets against an existing triple; propose-fix
   drafts a spec change from a certify-agent failure report. The human is the SOLE writer of
   the spec and hints — everything here produces PROPOSALS (ledger records + .new files); the
   only files this module ever creates at top level are the INITIAL drafts of a spec that does
   not exist yet. Backend: $K4K_AGENT_CMD (prompt on stdin -> text on stdout), deterministic
   stubs when unset so the whole loop runs agent-free. *)

open Ast

(* ---- output contract: tagged fenced blocks ---------------------------------- *)
(* ```k4kspec ... ``` / ```hints ... ``` / ```decisions ... ``` / ```summary ... ``` *)
let extract_sections (s : string) : (string * string) list =
  let lines = String.split_on_char '\n' s in
  let out = ref [] and cur = ref None in
  List.iter
    (fun line ->
      let t = String.trim line in
      let is_fence = String.length t >= 3 && String.sub t 0 3 = "```" in
      match !cur, is_fence with
      | None, true ->
          let tag = String.trim (String.sub t 3 (String.length t - 3)) in
          if tag <> "" then cur := Some (tag, [])
      | Some (tag, body), true -> out := (tag, String.concat "\n" (List.rev body) ^ "\n") :: !out; cur := None
      | Some (tag, body), false -> cur := Some (tag, line :: body)
      | None, false -> ())
    lines;
  List.rev !out

let require_sections (tags : string list) (secs : (string * string) list) : (unit, string) result =
  let missing = List.filter (fun t -> not (List.mem_assoc t secs)) tags in
  let dup = List.filter (fun t -> List.length (List.filter (fun (t', _) -> t' = t) secs) > 1) tags in
  if missing <> [] then
    Error (Printf.sprintf "missing fenced block(s): %s — return each as ```<tag> ... ```"
             (String.concat ", " missing))
  else if dup <> [] then Error (Printf.sprintf "duplicate fenced block(s): %s" (String.concat ", " dup))
  else Ok ()

(* ---- tiny line diff (LCS) for revise output ---------------------------------- *)
let line_diff (a : string) (b : string) : string =
  let xs = Array.of_list (String.split_on_char '\n' a) in
  let ys = Array.of_list (String.split_on_char '\n' b) in
  let n = Array.length xs and m = Array.length ys in
  let c = Array.make_matrix (n + 1) (m + 1) 0 in
  for i = n - 1 downto 0 do
    for j = m - 1 downto 0 do
      c.(i).(j) <- (if xs.(i) = ys.(j) then 1 + c.(i + 1).(j + 1) else max c.(i + 1).(j) c.(i).(j + 1))
    done
  done;
  let buf = Buffer.create 256 in
  let rec go i j =
    if i < n && j < m && xs.(i) = ys.(j) then go (i + 1) (j + 1)
    else if j < m && (i = n || c.(i).(j + 1) >= c.(i + 1).(j)) then (Buffer.add_string buf ("+ " ^ ys.(j) ^ "\n"); go i (j + 1))
    else if i < n && (j = m || c.(i).(j + 1) < c.(i + 1).(j)) then (Buffer.add_string buf ("- " ^ xs.(i) ^ "\n"); go (i + 1) j)
  in
  go 0 0;
  Buffer.contents buf

(* ---- the language reference the model gets (context economy: ~1 screenful) --- *)
let grepf_example =
  "# grepf NEEDLE FILE — print the lines of FILE that contain the fixed string NEEDLE.\n\
   interface cli \"grepf\":\n\
  \  reads: file at argv[1]\n\
  \  writes: nothing\n\
   cases on argv, file:\n\
  \  when len(argv) != 2: exit 2 ; stderr: one nonempty line ; stdout: \"\"\n\
  \  when file absent:    exit 2 ; stderr: one nonempty line ; stdout: \"\"\n\
  \  otherwise:\n\
  \    let matched = filter(lines(file.bytes), \\L -> contains(L, argv[0]))\n\
  \    stdout: unlines(matched)\n\
  \    stderr: \"\"\n\
  \    exit:   if is_empty(matched) then 1 else 0\n\
   examples:\n\
  \  argv=[\"b\",\"f\"] file=\"alpha\\nbob\\ncab\\n\" -> stdout=\"bob\\ncab\\n\" exit=0\n\
  \  argv=[\"zz\",\"f\"] file=\"a\\nb\\n\" -> stdout=\"\" exit=1\n\
  \  argv=[\"x\"] -> exit=2\n\
  \  argv=[\"x\",\"nope\"] -> exit=2\n"

let k4kspec_blurb =
  "You draft a k4kspec — a SMALL formal specification of ONE CLI program. A human will review\n\
   and sign it; a prover will hold an implementation to it, byte for byte. Keep it minimal.\n\n\
   GRAMMAR (line-oriented; ';' or newline separates statements):\n\
  \  interface cli \"NAME\":\n\
  \    reads:  nothing | file at argv[i]        # the fs footprint (all else is out of frame)\n\
  \    writes: nothing\n\
  \  cases on argv, file:\n\
  \    when <bool-expr>: <stmts>                # ordered decision table\n\
  \    otherwise: <stmts>                       # MANDATORY last case\n\
  \  statements: let x = <expr> | stdout: <rhs> | stderr: <rhs> | exit: <int-expr> | law <prop>\n\
  \  <rhs>: \"<bytes>\" | <expr> | one nonempty line | nonempty | any\n\
  \  examples:                                  # concrete rows, statically checked\n\
  \    argv=[\"a\",\"f\"] file=\"x\\ny\\n\" -> stdout=\"x\\n\" exit=0\n\
  \    argv=[] -> exit=2\n\n\
   BUILTINS (the WHOLE vocabulary — nothing else exists):\n\
  \  len concat contains starts_with ends_with split join lines unlines ascii_upper ascii_lower\n\
  \  is_decimal int_of get head first filter map any all count fold is_empty add sub not\n\
  \  argv argv[i] file.bytes | file absent | file present | if <b> then <e> else <e>\n\
  \  \\x -> ...   (lambdas ONLY as combinator arguments)\n\
  \  `lines` is POSIX: a final newline TERMINATES (lines \"a\\nb\\n\" = [\"a\",\"b\"] = lines \"a\\nb\");\n\
  \  `unlines` terminates every line.\n\n\
   LAWS (relational, proof-discharged; for outputs you deliberately do NOT pin):\n\
  \  sorted(xs) sorted_strict(xs) sorted_lines(xs) partitioned(xs) permutation(a,b) same_set(a,b)\n\
  \  with list_of(bytes) = its byte list, lines(bytes) = its line list.\n\
  \  Inside `law` (and ONLY there) `stdout`/`stderr`/`exit` denote the OUTPUT channels.\n\
  \  A law-constrained output is written `stdout: any` plus `law ...` lines. Laws NEVER go in\n\
  \  when-guards.\n\n\
   POSTURE — pin what matters, free what does not:\n\
  \  exit codes and stdout bytes are CONTRACT: pin them (or constrain by law).\n\
  \  stderr diagnostics: `one nonempty line` is the DEFAULT (content stays agent-authored).\n\
  \  Error handling is an ordered decision table of `when` guards + a mandatory `otherwise`.\n\n\
   SPLIT RULE (what goes where):\n\
  \  CONTRACTUAL (exit codes, stdout bytes, detection guards, laws — anything a consumer may\n\
  \  rely on) -> the spec. COSMETIC (error wording, help text, formatting preferences) -> the\n\
  \  hints block. NEVER put safety or security obligations in hints.\n\n\
   EXAMPLE of a complete, signed-quality spec:\n\n" ^ grepf_example

let decisions_contract =
  "The decisions block lists every judgment call you made, numbered D1..Dn, EXACTLY in this form:\n\n\
   D1. [active] short title\n\
  \  decided: what you decided\n\
  \  alternatives: what else was considered\n\
  \  why: the reason, tied to the intent\n\
  \  spec: case #N | case #N <channel> | case #N law #M | header\n"

(* ---- prompts ------------------------------------------------------------------ *)
let propose_prompt ~name ~intent =
  k4kspec_blurb
  ^ "\n\nNAME: " ^ name ^ "\nINTENT: " ^ intent
  ^ "\n\nDraft (1) the spec, (2) a hints file (cosmetic guidance ONLY, per the split rule; short),\n\
     (3) the decision list. " ^ decisions_contract
  ^ "\nReturn EXACTLY three fenced blocks tagged k4kspec, hints, decisions. No other output."

let revise_prompt ~spec ~hints ~decisions ~request =
  k4kspec_blurb
  ^ "\n\nYou are REVISING an existing k4kspec triple. Current artifacts:\n\n```k4kspec\n" ^ spec
  ^ "```\n```hints\n" ^ hints ^ "```\n```decisions\n" ^ decisions ^ "```\n\nCHANGE REQUEST: " ^ request
  ^ "\n\nRULES: return FULL files, not diffs. In decisions, COPY every existing entry VERBATIM —\n\
     you may ONLY flip a status to [superseded-by:Dk] and APPEND new entries with fresh numbers.\n"
  ^ decisions_contract
  ^ "\nReturn EXACTLY four fenced blocks tagged k4kspec, hints, decisions, summary (the summary\n\
     says what changed and which cases/laws are affected). No other output."

let fix_prompt ~spec ~hints ~failure =
  k4kspec_blurb
  ^ "\n\nThe spec below was SIGNED, but certification FAILED — the prover could not close the\n\
     proof. Propose a spec CHANGE that preserves as much of the intent as possible while making\n\
     it provable (e.g. weaken exactly the unprovable law, split a case, narrow the fragment).\n\n\
     ```k4kspec\n" ^ spec ^ "```\n```hints\n" ^ hints
  ^ "```\n\nTHE FAILURE REPORT:\n" ^ failure
  ^ "\n\nReturn EXACTLY four fenced blocks tagged k4kspec (the FULL revised spec), hints,\n\
     decisions (per the contract below; record what the failure taught as decisions), and\n\
     summary (what you changed and what it trades away).\n" ^ decisions_contract

(* ---- deterministic stubs ($K4K_AGENT_CMD unset): plumbing coverage, agent-free -- *)
let stub_propose_backend ~(name : string) : Agent_proof.backend =
  { Agent_proof.name = "stub";
    invoke =
      (fun _ ->
        Printf.sprintf
          "```k4kspec\n\
           # %s ARG — echo ARG followed by a newline (stub draft; replace with a real spec).\n\
           interface cli \"%s\":\n\
          \  reads: nothing\n\
          \  writes: nothing\n\
           cases on argv:\n\
          \  when len(argv) != 1: exit 2 ; stderr: one nonempty line ; stdout: \"\"\n\
          \  otherwise: stdout: concat(argv[0], \"\\n\") ; stderr: \"\" ; exit: 0\n\
           examples:\n\
          \  argv=[\"hi\"] -> stdout=\"hi\\n\" exit=0\n\
          \  argv=[] -> exit=2\n\
           ```\n\
           ```hints\n\
           usage line: mention the program name and expected argument count.\n\
           ```\n\
           ```decisions\n\
           D1. [active] exactly one argument\n\
          \  decided: len(argv) != 1 is exit 2\n\
          \  alternatives: read stdin when no argument\n\
          \  why: stub default; the intent was not consulted ($K4K_AGENT_CMD unset)\n\
          \  spec: case #0\n\
           D2. [active] output is ARG + newline\n\
          \  decided: stdout is the argument terminated by a newline\n\
          \  alternatives: no trailing newline\n\
          \  why: POSIX line convention\n\
          \  spec: case #1 stdout\n\
           ```\n" name name)}

(* revise/fix stub: echo the artifacts embedded in the prompt, appending one decision + a comment *)
let stub_revise_backend : Agent_proof.backend =
  { Agent_proof.name = "stub";
    invoke =
      (fun prompt ->
        let secs = extract_sections prompt in
        let spec = Option.value (List.assoc_opt "k4kspec" secs) ~default:"" in
        let hints = Option.value (List.assoc_opt "hints" secs) ~default:"" in
        let decisions = Option.value (List.assoc_opt "decisions" secs) ~default:"" in
        let next_d =
          match Decisions.parse decisions with Ok es -> Decisions.max_id es + 1 | Error _ -> 1
        in
        Printf.sprintf
          "```k4kspec\n%s```\n```hints\n%s```\n```decisions\n%sD%d. [active] stub revision\n\
          \  decided: no change ($K4K_AGENT_CMD unset)\n\
          \  alternatives: a real revision\n\
          \  why: deterministic stub\n\
          \  spec: header\n\
           ```\n\
           ```summary\nstub: no agent configured; the spec is unchanged.\n```\n"
          spec hints decisions next_d) }

let authoring_backend ~(stub : Agent_proof.backend) : Agent_proof.backend =
  match Sys.getenv_opt "K4K_AGENT_CMD" with
  | Some cmd -> Agent_proof.external_backend cmd
  | None -> stub

(* ---- the retry-gated drivers -------------------------------------------------- *)

type draft = {
  spec_text : string;
  hints_text : string;
  decisions_text : string;
  summary_text : string option;
  check_ok : bool;
  check_report : string;
  attempts : int;
  backend_name : string;
}

(* run the backend through the gates; [required] = fenced tags; [old_decisions] = monotone base *)
let drive ~(backend : Agent_proof.backend) ~(required : string list)
    ~(old_decisions : Decisions.entry list option) ~(check_must_pass : bool)
    (base_prompt : string) : (draft, string) result =
  let max_attempts = 4 in
  let rec go attempt prompt last_err =
    if attempt > max_attempts then Error last_err
    else
      let resp = backend.Agent_proof.invoke prompt in
      let secs = extract_sections resp in
      let reject why = go (attempt + 1) (base_prompt ^ "\n\nYour previous output was rejected:\n" ^ why ^ "\nReturn the corrected blocks (same rules).") why in
      match require_sections required secs with
      | Error why -> reject why
      | Ok () -> (
          let spec_text = List.assoc "k4kspec" secs in
          match Parse.parse spec_text with
          | exception Parse.Parse_error m -> reject ("the k4kspec block does not parse: " ^ m)
          | sp -> (
              let check_ok, check_report = Check.report sp in
              if check_must_pass && not check_ok then
                reject ("the spec parses but FAILS check:\n" ^ check_report)
              else
                let decisions_text = List.assoc "decisions" secs in
                match Decisions.parse decisions_text with
                | Error m -> reject ("the decisions block is malformed: " ^ m)
                | Ok fresh -> (
                    match old_decisions with
                    | Some old -> (
                        match Decisions.check_monotone ~old ~fresh with
                        | Error m -> reject ("decisions history was rewritten: " ^ m)
                        | Ok () ->
                            Ok { spec_text; hints_text = List.assoc "hints" secs; decisions_text;
                                 summary_text = List.assoc_opt "summary" secs;
                                 check_ok; check_report; attempts = attempt; backend_name = backend.Agent_proof.name })
                    | None ->
                        Ok { spec_text; hints_text = List.assoc "hints" secs; decisions_text;
                             summary_text = List.assoc_opt "summary" secs;
                             check_ok; check_report; attempts = attempt; backend_name = backend.Agent_proof.name })))
  in
  go 1 base_prompt "no attempt made"

let propose ~(backend : Agent_proof.backend) ~(name : string) ~(intent : string) : (draft, string) result =
  drive ~backend ~required:[ "k4kspec"; "hints"; "decisions" ] ~old_decisions:None
    ~check_must_pass:true (propose_prompt ~name ~intent)

let revise ~(backend : Agent_proof.backend) ~(spec : string) ~(hints : string)
    ~(decisions : string) ~(request : string) : (draft, string) result =
  match Decisions.parse decisions with
  | Error m -> Error ("existing decisions file is malformed: " ^ m)
  | Ok old ->
      drive ~backend ~required:[ "k4kspec"; "hints"; "decisions"; "summary" ] ~old_decisions:(Some old)
        ~check_must_pass:false (revise_prompt ~spec ~hints ~decisions ~request)

let propose_fix ~(backend : Agent_proof.backend) ~(spec : string) ~(hints : string)
    ~(failure : string) : (draft, string) result =
  drive ~backend ~required:[ "k4kspec"; "hints"; "decisions"; "summary" ] ~old_decisions:None
    ~check_must_pass:false (fix_prompt ~spec ~hints ~failure)

(* ---- the mechanical delta (computed by parsing BOTH specs, never trusted prose) -- *)
let mechanical_delta (old_sp : spec) (new_sp : spec) : string =
  let b = Buffer.create 256 in
  let p fmt = Printf.ksprintf (fun s -> Buffer.add_string b s; Buffer.add_char b '\n') fmt in
  if old_sp.reads <> new_sp.reads then p "  footprint CHANGED";
  let n_old = List.length old_sp.cases and n_new = List.length new_sp.cases in
  if n_old <> n_new then p "  case count: %d -> %d" n_old n_new;
  List.iteri
    (fun i (nc : case) ->
      match List.nth_opt old_sp.cases i with
      | None -> p "  case #%d ADDED [%s] (%d law(s))" i (Check.describe_guard nc.guard) (List.length nc.laws)
      | Some oc ->
          if Check.describe_guard oc.guard <> Check.describe_guard nc.guard then
            p "  case #%d guard: %s -> %s" i (Check.describe_guard oc.guard) (Check.describe_guard nc.guard);
          if oc.outs <> nc.outs then p "  case #%d outputs changed" i;
          if oc.laws <> nc.laws then
            p "  case #%d laws: %d -> %d (%s)" i (List.length oc.laws) (List.length nc.laws)
              (String.concat "; " (List.map Check.describe_expr nc.laws)))
    new_sp.cases;
  List.iteri
    (fun i (oc : case) ->
      if List.nth_opt new_sp.cases i = None then
        p "  case #%d REMOVED [%s]" i (Check.describe_guard oc.guard))
    old_sp.cases;
  if List.length old_sp.examples <> List.length new_sp.examples then
    p "  examples: %d -> %d" (List.length old_sp.examples) (List.length new_sp.examples);
  if Buffer.length b = 0 then "  (no structural change)\n" else Buffer.contents b
