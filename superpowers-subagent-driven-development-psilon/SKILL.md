---
name: superpowers-subagent-driven-development-psilon
description: Use to execute an accepted plan with three or more substantial tasks or two large tasks when write scopes do not overlap, next-task exact-target prerequisites are proved, and delegation beats overhead. Skip small, coupled, overlapping, shared-state-mutation, unresolved Discovery/Provisional, or overhead-dominated plans. Run sequential implementers with task and final review; the primary owns integration; never parallel-dispatch inside.
---

# Subagent-Driven Development

> **Codex 5.6 adaptation:** The description is the scope gate. Preserve upstream execution, recovery, and review for qualifying large plans; higher-priority policy controls workspace, branches, commits, tests, models, and integration.

Run one fresh implementer per task, one task review for applicability/spec/quality, then one integrated final review.

**Core principle:** Fresh task context + three-verdict task review + broad final review = fast, controlled execution.

- Narrate at most one short line between tool calls; artifacts and the ledger hold detail.
- Do not pause between tasks. Stop only for an unresolved `BLOCKED`, progress-preventing ambiguity, or completion. Never ask “continue?” after accepting the plan.
- This controller owns plan tasks. Do not invoke `superpowers-dispatching-parallel-agents-psilon` inside them; use it only for separate external workstreams.

## Eligibility

Use only in the same session for an accepted plan whose substantial task scopes are independent enough for sequential ownership. Otherwise use durable handoff, native execution, or brainstorm first.

Every Ready task must have proved load-bearing prerequisites for its exact target. An accepted plan records intent, not factual truth. Reject false prerequisites; resolve unknowns and open `Discovery`/`Provisional` gates before SDD.

## Setup and Recovery

Follow workspace policy. Use a worktree only when allowed; never access a prohibited one. Work on the current branch, including main/master, only when authorized. Record working directory and starting revision.

Run `scripts/sdd-workspace PLAN_FILE`. It returns the ignored workspace
`<repo>/.superpowers/sdd/<plan-basename>-<path-hash>/` and writes canonical plan identity to `plan-path`. Only this plan may use that directory.

Use `<workspace>/progress.md` as the durable controller state:

- first line: `# SDD ledger — plan: <canonical plan-path>`;
- a `Task <N>: complete` line means never redispatch that task;
- a latest fix-round line means resume at the next round;
- a different plan identity or old `.superpowers/sdd/progress.md` is foreign: leave it and use this plan's workspace.

In commit mode, verify recorded boundaries with `git log`. Snapshot tree IDs are unreferenced, session-scoped objects; verify each with `git cat-file -e '<tree>^{tree}'` and never call them durable. `git clean -fdx` destroys this ignored state. If snapshot recovery is lost, stop; never reconstruct it from memory.

Read the plan once. Record context, target, authoritative references, Global Constraints, statuses, and one todo per task. Preflight:

- find task/task or task/constraint contradictions and plan mandates the reviewer would treat as defects;
- verify each Ready task's prerequisites for the exact target and search disconfirming evidence;
- before later tasks, reuse current evidence and recheck only facts affected by prior work or drift;
- treat APIs, examples, and prior tasks as capability—not target coverage.

Resolve conflicts from authoritative requirements, policy, and evidence. Ask one batched question only for a genuinely unresolved consequential requirement or authority choice.

Before Task 1, require a clean tree without cleaning, stashing, or restoring user work; otherwise do not use SDD. Record mode and plan-wide `MERGE_BASE` separately from task BASE values:

- commit mode: `git rev-parse HEAD`;
- snapshot mode: `git rev-parse HEAD^{tree}`.

Create one cumulative plan-scope file. Add each task's exact, non-overlapping write paths before first dispatch. Snapshot mode may carry later uncommitted work only inside that cumulative scope; any other dirt stops SDD.

## Model Choice

Inherit parent model and reasoning by default. Override only when user, policy, or a concrete supported role need justifies it.

- complete 1–2-file transcription/mechanical work: cheapest capable model;
- multi-file integration, prose implementation, and ordinary review: standard/mid-tier;
- architecture, subtle concurrency, and final integrated review: most capable available;
- fix rounds 4–5: at least one tier above the stuck implementer;
- small scoped re-review: cheap-to-mid tier.

Choose the least costly option that avoids retries. Cheap models can take 2–3× more turns on multi-step work; turn count can erase token savings.

## Task Loop

### 1. Establish the Task Boundary

Add the task's exclusive paths to the cumulative scope. Those paths must be clean before dispatch.

**Commit mode:** require the whole tree clean; set BASE to `git rev-parse HEAD`. After each authorized task/fix commit, require the whole tree clean and every `BASE..HEAD` changed path inside the task scope before recording HEAD or reviewing.

**Snapshot mode:** Task 1 BASE is `MERGE_BASE`; later BASE is the prior cumulative snapshot. After task/fix work run:

```bash
scripts/worktree-snapshot PLAN_FILE CUMULATIVE_PATHS_FILE MERGE_BASE
```

Record its tree as HEAD. The helper seeds from `MERGE_BASE`, rejects live HEAD drift, broad/non-literal paths, nested repositories, and gitlinks, then overlays only cumulative paths through a temporary index. It changes no ref, HEAD, or real index. Before and after dispatch, stop on dirt outside cumulative scope.

### 2. Dispatch the Implementer

Run `scripts/task-brief PLAN_FILE N`; pass its unique path, never the whole plan. The dispatch contains only:

1. one line of project position;
2. exact target and authoritative preflight references;
3. brief path, labeled as required outcome and binding constraints;
4. verified interfaces/decisions from prior tasks that the brief cannot know;
5. evidence-backed resolution of noticed ambiguity;
6. report path and contract.

Exact contractual values stay in the brief. Never call provisional detail exact. Do not paste accumulated task history; fresh agents need only their task, touched interfaces, and global constraints.

Name the report from the brief (`task-N-brief.md` → `task-N-report.md`). The implementer writes the full report there and returns only status, commits, one-line verification, and concerns. Carry pointers to relevant parked findings. Record agent identity so rounds 1–3 can resume it. Never run plan implementers in parallel.

Template: [implementer-prompt.md](implementer-prompt.md)

### 3. Handle Status

- **DONE:** record HEAD; run `scripts/review-package PLAN_FILE BASE HEAD`; review its printed file. Never use `HEAD~1`, which loses multi-commit task work.
- **DONE_WITH_CONCERNS:** resolve correctness/scope concerns before review; ledger observations and proceed.
- **NEEDS_CONTEXT:** supply missing context and redispatch.
- **BLOCKED:** provide missing context, use a stronger model for reasoning limits, split an oversized task, or correct a bad plan from authority. Escalate only a consequential unresolved choice.

Never ignore a block or repeat the same attempt unchanged. Answer mid-task questions fully; do not rush the implementer.

### 4. Review the Task

Task review is mandatory and separate from self-review. Require all three verdicts: target applicability, spec compliance, and task quality. Broad review remains final.

Give [task-reviewer-prompt.md](task-reviewer-prompt.md):

- task brief, implementer report, and exact review-package paths;
- binding Global Constraints only—not plan assumptions or process rules;
- exact target and authoritative sources that can prove/disprove prerequisites;
- stable BASE and HEAD commit/snapshot boundaries.

The package must contain stat, full contextual diff, and objective commit IDs. Without the script, redirect `git diff --stat` and `git diff -U10` to one unique file. Never dispatch without a diff file or use `HEAD~1`.

Do not add vague checks or ask the reviewer to repeat checks already evidenced by the report. If evidence is missing or inconsistent, use the smallest discriminating check. Never pre-judge findings with “do not flag,” “at most Minor,” “the plan chose,” or similar instructions.

For `⚠️ Cannot verify from diff`, resolve unchanged/cross-task evidence before completion. Confirmed gaps enter the fix path.

### 5. Recover Applicability, Then Fix

Applicability failure never enters a code loop first:

- ❌: reject the false mechanism, prove an admissible replacement, and update plan/brief;
- blocking ⚠️: obtain the missing evidence; if still unknown, keep the task blocked.

Re-run applicability without code when evidence clears the current design. Code starts only after an admissible route exists. Ask the user only for unresolved consequential requirements or authority.

The code loop handles an admitted replacement, spec ❌, Critical/Important issues, or a confirmed spec ⚠️. Minor findings never enter it: ledger `Task <N>: minor (deferred): <finding>` and send them to final review. For plan conflicts, authority wins; resolve autonomously when clear, otherwise ask one consequential question. Never dismiss a finding because the plan mandates it.

A round is one fix dispatch plus one scoped re-review; maximum five:

- **Rounds 1–3:** resume the implementer with open findings verbatim. If resume is impossible, use a fresh agent with brief, report, and findings.
- **Rounds 4–5:** use a fresh stronger implementer with brief, report, findings, and: “A prior implementer attempted this task [N] times; you own it now. Read the report file for what was tried.”

Each round fixes, runs outcome-proportionate checks, appends commands/output to the report, and returns the short contract. Re-review only after covering evidence is present; name tests only when admitted. Record a fresh commit/snapshot HEAD and run `scripts/review-package PLAN_FILE FIX_BASE HEAD`; [re-review-prompt.md](re-review-prompt.md) verifies each finding and new breakage only. Add new Critical/Important breakage to the loop; ledger out-of-scope observations as deferred Minor.

After each round:

```text
Task <N>: fix round <R>/5 (<X> addressed, <Y> open — <findings>; commits <a7>..<b7>)
```

Use `snapshots` in snapshot mode. The controller never fixes code; doing so breaks context isolation and skips review.

At round five, stop dispatching and adjudicate every open finding:

- wrong/contestable: park with technical ruling;
- real but not load-bearing downstream: park as real and deferred;
- real and load-bearing or plan-breaking: append `Task <N>: BLOCKED — <reason>` and report finding, conflicting plan text, and fix history.

Parking a structural failure is forbidden. Adjudicate only at the cap; every ruling enters the ledger.

### 6. Complete the Task

After clean review or capped parked rulings, append:

```text
Task <N>: complete (commits <base7>..<head7>, review clean)
Task <N>: complete (commits <base7>..<head7>, <K> parked)
```

Use `snapshots` in snapshot mode. Mark the todo complete. Never advance with unreviewed or unadjudicated Critical/Important findings.

## Final Review

**Commit mode:** require a clean tree and prove every `MERGE_BASE..HEAD` path lies in cumulative plan scope.

**Snapshot mode:** take one final cumulative snapshot and record it as HEAD.

Run `scripts/review-package PLAN_FILE MERGE_BASE HEAD`. Pass its path as `[DIFF_FILE]`, with matching base/head, to `superpowers-requesting-code-review-psilon`'s [code-reviewer.md](../superpowers-requesting-code-review-psilon/code-reviewer.md). Give exact target, authoritative requirements/references, deferred/parked ledger entries, and the plan only as a decision record. Never present an implementation summary as established fact. Use the most capable available reviewer.

For final findings, dispatch ONE fixer with the complete list, then exactly one scoped fix-wave re-review. Per-finding fixers duplicate context and suites. Adjudicate residuals under the task breaker: park with rulings or keep load-bearing issues blocked until governing integration policy resolves them. No second fix wave inside this workflow.

## Finish

After clean integrated review and incorporated fixes, validate and remove only this plan's exact workspace, preferably through recoverable deletion. Never touch siblings. Follow governing integration, commit, and handoff policy; do not invoke an unavailable branch-finishing skill.

Read [common-rationalizations.md](common-rationalizations.md) only when tempted to skip a review, fix, ledger entry, or breaker. Read [example-workflow.md](example-workflow.md) only when a state trace would clarify the controller; it adds no requirements.
