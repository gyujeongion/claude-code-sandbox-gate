# claude-code-sandbox-gate

**Your AI agent says "it works now" and applies the patch to main. This is the gate that stops it.**

A [Claude Code](https://claude.com/claude-code) skill: before a change touches
main/production, it runs a real verification pass — restate what the change actually
promises, reproduce it in an isolated sandbox, beat on it with golden / edge / failure /
concurrency cases, trace the flow for accidental passes, and only then say whether it's
safe to apply.

> It's an instruction skill, so it *structures and gates* the agent's behavior — it
> doesn't technically enforce anything an agent is determined to skip. The value is the
> discipline it imposes, not a hard runtime lock.

---

## Why

The default agent loop is dangerous:

```
agent writes a fix
  → runs the happy path once
  → "it works now ✅"
  → applies to main
  → the edge case / race / swallowed error ships
```

"The symptom went away" is where most verification *stops*. It should be where it
*starts*. A passing golden-path test says almost nothing about empty input, a dead
dependency, a second concurrent call, or whether the change quietly broke a caller two
modules away.

`/sandbox-gate` makes the agent treat applying-to-main as a gated step, not a reflex.

## What it actually does

Eight phases, in order — the discipline is in not skipping the first two:

1. **Restate the change as a promise** — original goal, what new promise it makes,
   success criteria, blast radius on failure. (Skip this and you verify a change that
   "runs" but doesn't solve the goal — the #1 failure mode.)
2. **Scan the surface area** — responsibility boundary, data flow, callers,
   dependencies, the *implicit* contracts nobody wrote down.
3. **Build a sandbox** — `git worktree`, a temp dir, a container, a schema clone…
   reads can hit real data, **writes go only to the sandbox**.
4. **Test from every angle** — golden, boundaries, bad input, fault injection,
   concurrency & retry, state leakage, regression, rollback.
5. **Trace the flow** — did it enter the right branch? any swallowed exception? do the
   metrics still mean what they meant? (catches tests that *passed by accident*).
6. **Root-cause any issue** — symptom → direct cause → structural cause → fix layer.
7. **Verification report** — a structured pass/conditional/hold with evidence.
8. **Apply gate** — not all ✅ → it does **not** recommend touching main until you
   explicitly override.

It reports observed facts ("7/12 pass, 2 red, here's why"), never a bare "passed."

## Why no automation scripts?

Fair question — wouldn't shipped helper scripts (spin up a `git worktree`, a container,
a DB clone) make this more reliable? Deliberately not, because the right isolation
depends entirely on the change: a worktree for tracked code, a temp dir for a script, a
container for a daemon, a schema clone for a migration. A one-size sandbox script would
give a *false sense of safety* and quietly mismatch the change under test. So the skill
makes the agent choose and record the isolation per change, and — critically — **decide
teardown up front** (Phase 3), which is the actual guard against the state-leak and
context-burn failure mode. If you have a repeatable setup for *your* stack, wire it into
your own project as a command the skill can call; that belongs in your repo, not here.

## Install

```bash
git clone https://github.com/<you>/claude-code-sandbox-gate.git
cp -r claude-code-sandbox-gate/skills/sandbox-gate ~/.claude/skills/sandbox-gate
```

Pure instruction skill — no dependencies, no scripts, no API keys.

## Usage

- `/sandbox-gate` — before applying a change you're unsure about
- `"verify this before it goes to main"` — triggers the gate
- `"test this properly, not a quick check"` / `"don't patch and pray"` — same

The agent will refuse to call it done on a golden-path pass alone, and will tell you
*why* it's red, not just that it is.

## Where it fits

Part of a small family of verification/repair skills:

| If you need to… | Use |
|---|---|
| Verify a **code/system change** before it ships | **sandbox-gate** (this repo) |
| Fix the **cause** instead of the symptom / redesign a flawed structure | [rethink + deusex](https://github.com/gyujeongion/claude-code-rootcause) |
| Test whether a **doc** is followable by a newcomer | [cold-tester](https://github.com/gyujeongion/claude-code-cold-tester) |
| Route which **rules** apply to a given request | [context-router](https://github.com/gyujeongion/claude-code-context-router) |

`deusex` decides *how to build* the fix; `sandbox-gate` decides *whether the fix is safe
to ship*. Different stages, often used back to back.

## License

MIT — see [LICENSE](LICENSE). Not affiliated with Anthropic.
