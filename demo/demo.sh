#!/usr/bin/env bash
# Illustrative walkthrough — sandbox-gate is an instruction protocol the agent follows
# inside Claude Code (deliberately no runtime). Scripted so the GIF is stable; the phases
# and report shape mirror the SKILL.md template.
set -euo pipefail
say(){ printf '\033[1;36m$ %s\033[0m\n' "$1"; sleep .5; }
p(){ printf '%b\n' "$1"; sleep "${2:-.5}"; }

echo; printf '\033[1m"It works now." — the gate that checks before it hits main.\033[0m\n'; sleep 1.2; echo
p '\033[2mclaude:\033[0m fixed delete_user(). Looks good — applying to main—'
say '/sandbox-gate' .6
p 'Phase 1 — promise: delete is idempotent (2nd call = no-op, no error)'
p 'Phase 3 — sandbox: git worktree /tmp/gate-test (main untouched)'
p 'Phase 4 — 6 cases:' .4
p '   \033[32m✔ golden\033[0m      delete an existing user'
p '   \033[32m✔ golden\033[0m      delete → confirm gone'
p '   \033[32m✔ boundary\033[0m    delete a missing user → no-op'
p '   \033[31m✘ concurrency\033[0m two simultaneous deletes → KeyError' .8
p 'Phase 6 — cause: lock not held across read+delete; exception swallowed at L47'
p '\033[1;31m⛔ HOLD — 1/6 red. Do not apply to main until the race is fixed.\033[0m' 1.6
echo
printf '\033[2millustrative — an instruction protocol the agent runs in Claude Code (no scripts, by design).\033[0m\n'; sleep 2
