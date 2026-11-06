# BolexTV — Dispatch Control (pause / resume)

**Status:** operating procedure · **Version:** v1 · **Date:** 29/10/2026
**Applies to:** all BolexTV development dispatched by Hermes from the build host `ai-agents` (VM105).

---

## 1. The two commands

Send these in chat — WebUI, Telegram, or CLI. Both work mid-run and both survive a session restart.

| Intent | Command to send |
|---|---|
| **Pause everything** | `/pause BolexTV` |
| **Resume** | `/pause off` |
| Check state | `/pause` (with no reason) replies "already paused" if engaged |

`/pause BolexTV` — the text after the command is the reason string, echoed back to you in the
paused notice. Any wording works.

Equivalent from a terminal (if chat is unavailable):

```bash
hermes pause --reason "BolexTV hold"   # engage
hermes resume                          # lift
```

**Why these are the right commands:** they are the platform's own emergency stop (`agent/estop.py`),
not something written for this project. The sentinel is a single file, checked on every dispatch tick.

- Sentinel: `/home/alex/hermes_data/ESTOP` (`HERMES_HOME=/home/alex/hermes_data`)
- A corrupt or empty file still counts as engaged — fail-safe. `touch ~/hermes_data/ESTOP` pauses
  even if the CLI is broken.
- Slash commands bypass the stop by design, so `/pause off` always reaches the gateway. You cannot
  lock yourself out of the chat.

---

## 2. What `/pause` stops — and what it does not

**Stops new work, fleet-wide:**

- cron job dispatch
- kanban dispatcher
- **new gateway turns** — every chat surface, and every Hermes profile on this host
- therefore every not-yet-started `delegate_task` child and every not-yet-launched `hermes -z` one-shot

**Does not stop:**

- a turn already running when you send it — it finishes
- subagents already live inside that turn

That gap is deliberate in the platform design ("in-flight work is never killed"), and it is the one
thing to remember. If something is actively burning quota and you want it dead now:

```
/pause BolexTV
/stop
```

`/stop` is `interrupt_then_dispatch`: it interrupts the running turn, releases the session lock, and
halts the subagent tree spawned from it. `/stop` alone does **not** stop the next dispatch — that is
what `/pause` is for. Use them as a pair.

**Side effect to be aware of:** the stop is fleet-wide, not project-scoped. Family bot profiles
(Ulises, Superman, Jarvis) honour the same sentinel, so while paused they answer with the paused
notice. That is the correct behaviour for an emergency stop, but it is not a BolexTV-only switch.

---

## 3. Batch discipline (why the gap stays small)

The orchestrator must never hand the platform a long-running turn it cannot interrupt cheaply.
Rules:

1. **One dispatch batch at a time.** At most two children in parallel, per plan §5.
2. **Bounded scope per child.** Each child owns one deliverable file or one measurement, not a phase.
3. **Report between batches.** Every batch ends with a visible message stating: what ran, what it
   cost, what is next. That is your decision point — and your pause window.
4. **No unsupervised long tail.** No dispatch that is expected to run longer than ~10 minutes
   without an intermediate report.

---

## 4. Budget rules

Baseline measured 29/10/2026 from `GET https://ollama.com/api/usage`:

| Metric | Value |
|---|---|
| Cloud requests, rolling 7 days | **7,808** |
| Busiest day | 2,063 (27/10) |
| Today so far | 119 |
| Quota percentage | **not exposed by the API** — the caps are UI-only |

Rules:

- `delegation.model` is the single lever for `delegate_task` cost. It is currently
  `kimi-k3:cloud`. **Pin it to the phase's intended model before dispatching**, never leave the
  flagship there by drift.
- Phase 0 is model-heterogeneous by design (Cartographer on `kimi-k3`, Field Tester on
  `glm-5.3-flash`). Cheapest faithful arrangement: pin `delegation.model: glm-5.3-flash:cloud` for the
  visible children, and run the Cartographer as one CLI one-shot on `kimi-k3`.
- One CLI one-shot on a high-effort model can return empty content — pass `--reasoning low`.
- Every batch report includes the request delta, so spend is never a surprise at the end of a week.

---

## 5. Resume behaviour

`/pause off` lifts the stop and dispatch picks up on the next tick. It does **not** by itself restart
interrupted work. On resume the orchestrator:

1. Reads this file and `docs/CONTINUATION-*.md` for the last completed batch.
2. Re-checks live state (branch, PR, container, IP) — never trusts the brief alone.
3. Reports the intended next batch and waits for go if the previous batch was interrupted mid-flight.

---

## 6. Verified evidence (29/10/2026)

Engage/release cycle run on the build host against the real sentinel path:

```
CLEAR → hermes pause --reason "BolexTV dev hold"
  sentinel body: {"engaged_at": "2026-10-29T07:48:14Z", "reason": "BolexTV dev hold"}
  estop.is_engaged() → True
  estop.paused_reply() → "⏸️ Hermes is paused (BolexTV dev hold). New work is on hold; ..."
hermes resume → CLEAR
```

Command surface confirmed by reading `hermes_cli/commands.py`: `/pause` is
`busy_policy="dispatch"` (accepted mid-run without interrupting) and is listed in
`gateway/run_busy.py::_PLAIN_COMMANDS`; `/stop` is `interrupt_then_dispatch`.

---

*Prepared by Hermes as orchestrator. Command semantics and the sentinel path were read from the
installed Hermes source (`/home/alex/hermes`) and exercised live, not inferred.*
