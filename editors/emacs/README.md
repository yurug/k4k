# editors/emacs

A major mode (`k4k-mode`) for `.k4k` interaction files — the user-facing
surface of the [k4k](https://github.com/yurug/k4k) coding agent.

## Layering

A `.k4k` file is markdown with a small set of k4k-managed sections
(`## k4k:status`, `## k4k:clarification:<ts>`,
`## k4k:tradeoff:proposal:<ts>`) interleaved with user-owned ones. The
k4k watcher writes the file concurrently with the user, so saves
**must** go through [cotype](https://github.com/yurug/cotype) to avoid
lost updates.

`k4k-mode` does NOT re-implement save coordination — it delegates to
[`cotype-mode`](https://github.com/yurug/cotype/tree/main/editors/emacs)
(a minor mode shipped with cotype). When `cotype-mode` is on
`load-path` and the file already has a `.<basename>.cotype/` sidecar
(k4k creates one on first `k4k <file>`), this mode turns `cotype-mode`
on automatically; saves then route through `cotype save` and the
watcher's writes auto-revert into the buffer.

If `markdown-mode` is on `load-path`, `k4k-mode` derives from it (you
get markdown's syntax + paragraph movement for free); otherwise it
falls back to `text-mode`.

## Requirements

- Emacs ≥ 27.1
- **Recommended**: `cotype-mode` from
  <https://github.com/yurug/cotype/tree/main/editors/emacs>.
  Without it, k4k-mode loads fine but concurrent edits race against
  the watcher.
- **Recommended**: `markdown-mode` from MELPA. Without it, derives
  from `text-mode`.

## Install

```elisp
(add-to-list 'load-path "~/path/to/k4k/editors/emacs")
(require 'k4k-mode)
```

That installs `auto-mode-alist` for `*.k4k` automatically. To
customise:

```elisp
(setq k4k-actor-label        "emacs:laptop"   ;; default "emacs:k4k"
      k4k-auto-enable-cotype t)               ;; default t
```

## What you get on top of markdown-mode

| Command | Key | What it does |
|---|---|---|
| `k4k-approve-tradeoff` | `C-c C-x a` | Appends `Approved: Tier <B\|C>` to the most recent `## k4k:tradeoff:proposal:*` block. Refuses if that block already has an Approved/Rejected line. |
| `k4k-reject-tradeoff` | `C-c C-x r` | Appends `Rejected: <reason>` to the most recent `## k4k:tradeoff:proposal:*` block. |
| `k4k-request-rollback` | `C-c C-x b` | Adds `- request: rollback` to the `## k4k:status` block (idempotent — refuses if already present). |
| `k4k-request-pause` | `C-c C-x p` | Adds `- request: pause` to the `## k4k:status` block. |
| `k4k-goto-pending-tradeoff` | `C-c C-x t` | Jumps to the oldest unanswered `## k4k:tradeoff:proposal:*` block (the one the watcher is currently waiting on). |
| `k4k-goto-pending-clarification` | `C-c C-x q` | Jumps to the most recent `## k4k:clarification:*` block. |

All bindings live under the `C-c C-x` prefix (markdown-mode's
extensions namespace) so they don't collide with markdown's own link /
style commands.

## Faces

- `k4k-managed-heading-face` — applied to `## k4k:*` heading lines.
  Visual cue that everything below the line is the watcher's writing
  area; the user only appends Approved/Rejected lines or
  clarification answers.
- `k4k-directive-face` — applied to `- request: <directive>` lines in
  the status block. These are your command channel to the watcher.

## Manual smoke test

There's no automated test suite (would require Emacs in CI; same trade-
off as cotype-mode). Verify by hand:

```bash
# In one terminal: launch the watcher on a scenario.
cp examples/scenarios/echo-tiny/echo-tiny.k4k /tmp/test.k4k
cd /tmp && git init -q && git add test.k4k && git commit -qm initial
k4k --exit-on-stable test.k4k    # creates .test.cotype/ sidecar
```

```bash
# In another terminal: open in Emacs.
emacs -Q -l ~/path/to/k4k/editors/emacs/k4k-mode.el /tmp/test.k4k
```

In Emacs:

1. The modeline shows `k4k` (and ` cotype` next to it when
   cotype-mode is on `load-path`).
2. The `## Goal` heading appears in `markdown-header-face-2` (or
   plain text-mode default). If/when a `## k4k:clarification:<ts>`
   block lands, it appears in `k4k-managed-heading-face`.
3. `M-x k4k-goto-pending-clarification` jumps to the newest
   clarification block (or signals "No clarification block found").
4. After a tradeoff is proposed inline, `C-c C-x a` prompts for tier
   and inserts `Approved: Tier C` at the block end. Save with
   `C-x C-s` — if cotype-mode is on, the echo area says
   `cotype: saved (direct)` or `cotype: saved (merged)`.
5. The watcher detects the save within ~500 ms (per the cotype
   poll interval); subsequent JSONL events should show
   `directive.tradeoff_resolution` or the gap-step resuming.

## License

MIT.
