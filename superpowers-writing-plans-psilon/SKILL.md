---
name: superpowers-writing-plans-psilon
description: Use when implementation needs a durable plan because it spans three or more coherent stages, multiple components with dependency or interface coordination, a migration or rollout, cross-session handoff, or high-risk sequencing where ordering and recovery matter, or when the user explicitly requests a written plan. Produce outcome-level tasks with exact constraints, dependencies, verification, and recovery where applicable. Do not use for a clear local change, routine work, or a task the current agent can implement directly in one session without coordination risk.
---

# Writing Implementation Plans

> Forked from `superpowers:writing-plans` v6.2.0. Local changes: hard-task activation, outcome-level task sizing, and removal of universal TDD, complete-code steps, worktrees, per-step commits, and mandatory execution handoffs.

## Goal

Create the smallest plan that preserves the decisions, ordering, interfaces, and evidence a complex implementation needs. Optimize for reliable execution and handoff, not document length.

## Establish the plan boundary

- Confirm the required outcome, non-goals, governing contracts, and material constraints.
- Inspect enough of the repository and current state to avoid speculative paths or interfaces.
- Decompose independent subsystems only when each produces a coherent useful outcome.
- Do not plan unsupported behavior or convert incidental implementation details into requirements.

If the task no longer meets the trigger after inspection, stop planning and implement it directly.

## Plan structure

Include only applicable sections:

1. **Goal and supported outcome** — what observable result defines success.
2. **Current context** — facts the executor cannot cheaply rediscover.
3. **Approach** — the chosen architecture and important rejected alternatives.
4. **Constraints and interfaces** — exact external contracts, ownership boundaries, versions, formats, and cross-task dependencies.
5. **Implementation tasks** — coherent deliverables in dependency order.
6. **Verification** — evidence that can falsify each material outcome.
7. **Rollout and recovery** — only for migrations, releases, or operational state changes.

## Task sizing

- Make each task a substantial, independently understandable deliverable, not a two-minute action.
- Split when tasks have distinct ownership, dependencies, verification surfaces, or can be accepted independently.
- Keep tightly coupled edits and their verification together.
- Fold setup, configuration, documentation, and cleanup into the deliverable that needs them.
- State which tasks may proceed in parallel only after confirming non-overlapping mutable scope.

## Task contents

For each task, provide:

- the required outcome;
- relevant files or owned areas when known;
- inputs, outputs, and interfaces other tasks depend on;
- constraints and exact values that must survive delegation;
- focused verification and completion evidence;
- dependencies or ordering constraints.

Include code only when an exact snippet is itself a frozen contract or prevents a likely ambiguity. Do not duplicate full implementations into the plan, fabricate line numbers, or prescribe mechanics the executor can determine from current code.

## Tests and commits

- Plan permanent tests only when they protect required observable behavior and would fail under a plausible production regression.
- Use other focused verification when no permanent test qualifies.
- Do not force test-first sequencing, one commit per micro-step, or commits at all unless the repository workflow or user requires them.

## Self-check

Before handing off the plan:

1. Map every required outcome to a task and verification surface.
2. Check task interfaces and ordering for contradictions.
3. Remove placeholders, invented details, repeated prose, and unnecessary tasks.
4. Confirm rollback or recovery is concrete where failure could leave durable state.
5. Confirm the plan remains proportionate to the work.

Fix issues inline. Do not dispatch a plan reviewer unless the plan is independently high-risk and review would materially reduce risk.

## Handoff

Keep the plan in the conversation when that is sufficient. Write a durable plan file only when the user requests it, another session or agent must consume it, or the work is long enough that compaction threatens continuity. Use the repository's designated location; do not invent a `docs/superpowers` tree.

The terminal state is an executable plan. Do not mandate a worktree, subagent workflow, or another skill as the next step.
