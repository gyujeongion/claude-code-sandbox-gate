---
name: sandbox-gate
description: A verification gate that runs BEFORE a change touches main/production. Instead of accepting "it works now," it re-states what the change actually promises, scans the architecture it touches, reproduces it in an isolated sandbox, runs it against golden / edge / failure / concurrency cases, traces the flow for accidental passes, and only then reports whether it's safe to apply. Use when an agent is about to apply a fix, when you say "/sandbox-gate", "verify before applying", "is this change actually safe", "test this properly, not a quick check", "don't patch and pray".
---

# /sandbox-gate — verify before it touches main

## What this is

This is the gate that stops *"it works now, applying to main."* When an agent (or you)
has a change ready, this skill refuses to call it done until the change has been
re-stated as a promise, reproduced in isolation, and beaten on from every angle.

It is **not** a unit-test runner you invoke once. It's a final gate that treats
"the symptom went away" as the *start* of verification, not the end.

Core stance:
- **No patch-and-pray.** A vanished symptom isn't success; structural safety is.
- **Big picture first.** Even a one-line patch is verified within the architecture,
  data flow, and contracts it lives in.
- **No "apply to main" recommendation until it passes.** The aim is to push hard for
  safety, not to finish verification fast. (This is an instruction skill — it shapes
  and gates the agent's behavior; it can't technically *enforce* anything the agent
  is determined to skip. The discipline is the value.)

> Sibling skills: if a change is needed because the design is wrong, that's a redesign
> ([deusex](https://github.com/gyujeongion/claude-code-rootcause)); if you're testing
> whether *docs* are followable, that's a cold reader
> ([cold-tester](https://github.com/gyujeongion/claude-code-cold-tester)). This skill
> verifies a concrete **code/system change** before it ships.

---

## Workflow (follow in order)

### Phase 1 — Restate purpose & identity (never skip)

Write these four down before anything else. Every later test case derives from them:

1. **Original goal** — the one-line problem the change is meant to solve.
2. **Identity of this change** — not "what it does" but *what new promise it makes*:
   added feature? bugfix? refactor? infra change?
3. **Success criteria** — what observable facts must be true to call it passed? If
   vague, ask the user before proceeding.
4. **Blast radius if it fails** — data loss? user-facing? reversible?

> Skip this and you get the most common failure: a change that "runs" but doesn't
> solve the original goal.

### Phase 2 — Scan the upper-layer architecture

Don't look only at the changed lines. Go one level up:

- **Responsibility boundary** — what the module promises externally (input/output
  shape, side effects, idempotency, concurrency assumptions).
- **Data flow** — where input comes from, where it goes, which point the change touches.
- **Callers** — who calls this; does the new behavior break their assumptions?
- **Dependencies** — what it calls (DB, API, FS, env, OS); how to isolate them in the sandbox.
- **Implicit contracts** — the unwritten things everyone relies on ("this is idempotent",
  "this path is never empty").

Output: a one-paragraph "surface area this change touches." Show it; confirm nothing's missing.

### Phase 3 — Build the sandbox

Pick isolation that fits the change. **Never** touch the real working tree, real data,
or production resources directly.

| Change type | Recommended sandbox |
|---|---|
| Git-tracked code | `git worktree` on a separate branch (or a temp clone) |
| Single script / function | temp dir (`mktemp -d`) + dummy inputs |
| Filesystem / sync / move | reproduce a fixture tree in a temp dir, dry-run first |
| Service / daemon / network | Docker container or a separate port |
| DB migration | a clone of the prod schema + representative sample data |
| External API | mock or a sandbox endpoint; real calls only with explicit consent |

Rules: reads against real data are fine, **writes go only to the sandbox**; record the
exact commands that built the environment; decide teardown up front.

### Phase 4 — Test from every angle

Start from Phase 1's success criteria, then cover every category:

1. **Golden path** — the most normal input yields the expected output.
2. **Boundaries** — empty / single / max input, 0 / negative, length 0/1, unicode &
   emoji, very long strings, very large files.
3. **Bad input** — type mismatch, broken JSON, missing fields, no permission,
   nonexistent path, broken encoding.
4. **Fault injection** — a dependency dies (network drop, DB timeout, disk full, perm denied).
5. **Concurrency & retry** — same input twice (idempotency?), two calls at once (race?),
   killed mid-run then restarted (where does it resume?).
6. **State leakage** — leftovers after a run (temp files, locks, caches, env, globals);
   does a second run get poisoned by the first?
7. **Regression** — does adjacent, untouched functionality still work? Run at least one
   caller scenario from Phase 2.
8. **Rollback** — does reverting actually work? For a migration, the down path too.

For each case record **what you put in, what came out, how it differed from expected** —
not just "pass." Record observed facts.

### Phase 5 — Trace the flow (catch accidental passes)

A passing test isn't the end. Follow the run:

- Did execution enter the intended branch? (log / print / debugger)
- Are intermediate values what you assumed — especially types, null, empty collections?
- Is any exception being swallowed? A silently-ignored error in a `catch` is a red flag.
- Are async / callback orderings as intended?
- Do logs / metrics / telemetry still mean what they meant before? (a renamed message
  silently breaking monitoring is common)
- Do transaction boundaries match the intended unit?

This catches tests that *passed by accident*. If the flow looks wrong, report red even
on a pass.

### Phase 6 — Root-cause analysis (when an issue is found)

Don't jump to a patch. Go up one level first:

1. **Symptom** — what misbehaves.
2. **Direct cause** — which line/condition took the wrong branch.
3. **Structural cause** — why was that branch possible? Ambiguous contract? Undocumented
   assumption? Responsibility in the wrong module? Is the same class of bug latent elsewhere?
4. **Recommended fix layer** — a one-line patch, or fix the contract/structure upstream?
   If you recommend the patch, state why and what risk remains.

> If the same bug can recur structurally, it isn't fixed.

### Phase 7 — Verification report

Report in this shape:

```
# Verification report — <one-line change summary>

## 1. Identity of the change
- Original goal:
- New promise it makes:
- Success criteria:
- Blast radius on failure:

## 2. Surface area touched
- Responsibility boundary / data flow / callers / dependencies / implicit contracts:

## 3. Sandbox setup
- Isolation / reproduce command / teardown:

## 4. Case results
| # | Category | Input | Expected | Actual | Verdict |
|---|----------|-------|----------|--------|---------|
| 1 | golden   | ...   | ...      | ...    | ✅ |
| 2 | boundary | ...   | ...      | ...    | ⚠️ |

## 5. What the flow trace found

## 6. Issues found (if any)
- symptom / direct cause / structural cause / recommended fix layer

## 7. Apply recommendation
- [ ] safe to apply as-is
- [ ] conditional (resolve items below first)
- [ ] hold (needs structural redesign)
```

### Phase 8 — Apply gate

- If the Phase 7 table is not all ✅, **do not recommend changing main.** Don't start
  applying until the user explicitly says "apply anyway."
- If any ⚠️/❌ exist, fix them and **re-run the affected cases** — not just some; a fix
  can break elsewhere.
- After applying, recommend one light smoke run against real data/environment.

---

## Anti-patterns (never do these while using this skill)

- Skipping Phase 1–2 because the user said "just apply it fast." The less time there is,
  the more you start from identity + surface area.
- Running one golden-path case and reporting "passed."
- Hiding an exception in try/except on a failure case and marking it passed.
- Assuming a sandbox pass means a production pass — always state the environment delta.
- Patching the direct cause and skipping structural analysis.
- Doing any write to the real working tree / real data during verification.
- **Substituting a dry-run for real verification.** A dry-run predicts; it can differ
  from real-environment results. Don't report "dry-run passed" as "passed." If you
  genuinely can't observe real behavior, report that honestly — never fabricate a result.

---

## Interaction tone

- Short, to the point. Announce each phase in one line ("Phase 4 — 7/12 cases pass, 2
  red, tracing").
- Don't guess ambiguous points — ask, especially about success criteria and blast radius.
- Never report only pass/fail; report **why**.
