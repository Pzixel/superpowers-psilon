---
name: superpowers-subagent-driven-development-psilon
description: Use when executing an accepted multi-stage implementation plan with at least three substantial tasks, or two independently large tasks, whose mutable scopes can be assigned without overlap and whose combined context or duration makes delegation materially beneficial. Coordinate bounded implementers while retaining integration ownership. Do not use for small plans, tightly coupled tasks, overlapping files, shared-state mutation, exploratory work without fixed task boundaries, or when delegation and review overhead would rival the implementation.
---

# Subagent-Driven Development

> Forked from `superpowers:subagent-driven-development` v6.2.0. Local changes: hard-plan activation, bounded ownership, native progress tracking, and removal of worktrees, per-task reviewers, mandatory fix loops, scratch ledgers, branch menus, and cross-skill chaining.

## Goal

Execute a genuinely large decomposed plan faster without losing integration coherence or filling the primary context with task-local detail.

## Preconditions

Before delegating, confirm:

1. The plan and required outcomes are accepted and sufficiently concrete.
2. Each delegated task has a distinct deliverable and enough work to outweigh dispatch overhead.
3. Mutable scopes do not overlap, or dependent mutations will run sequentially.
4. The primary agent retains shared-state mutation, integration, verification, and commit ownership unless repository instructions explicitly assign otherwise.
5. Delegation is allowed by the active instructions and available tooling.

If these conditions fail, execute inline or refine the task boundary first.

## Prepare execution

- Read the plan once and identify dependencies, shared interfaces, and global constraints.
- Use the native plan or task tracker for progress. Create a durable recovery ledger only when the run is long enough that context compaction creates a demonstrated continuity risk.
- Do not create a worktree, branch, scratch hierarchy, or documentation tree unless the user or repository workflow requires it.
- Reserve shared files and integration points for the primary agent.

## Dispatch implementers

Give each implementer:

- one bounded task and exclusive mutable scope;
- the exact requirements and interfaces it owns;
- relevant repository instructions and authority boundaries;
- raw artifacts or source paths needed to reason independently;
- the verification expected for its deliverable;
- a concise return contract: outcome, changed paths, commands and results, concerns, and unresolved dependencies.

Do not paste the whole conversation, prior conclusions, unrelated plan sections, or accumulated agent summaries. Use the least expensive model that can reliably handle the task, while recognizing that repeated weak-agent turns can cost more than one capable pass.

## Schedule work

- Run tasks in parallel only when they have no sequential dependency and no overlapping mutable state.
- Run interface-defining or shared-boundary tasks before consumers when their outputs are not already fixed.
- Keep the primary agent on integration, shared-path work, or another genuinely independent deliverable.
- Do not create an implementer merely to satisfy a desired agent count.

## Integrate results

For each result:

1. Inspect the actual diff or artifact rather than trusting the status summary.
2. Verify that the task stayed inside its ownership boundary and preserved shared contracts.
3. Resolve cross-task interface mismatches centrally.
4. Run focused verification after integration; run broader gates once after the final relevant change when the outcome requires them.
5. Resume the same implementer for a bounded correction when its context remains useful; do not create automatic review/fix loops.

Use an independent reviewer only when the integrated change meets the high-risk review trigger. Do not review every task merely because it was delegated.

## Stop conditions

Stop dispatching and reassess when:

- task boundaries repeatedly overlap;
- agents require the whole system context to proceed;
- independent fixes conflict at integration;
- a plan assumption proves false;
- delegation consumes more coordination than implementation;
- additional authority or a material product decision is required.

The terminal state is an integrated, proportionately verified implementation—not another mandatory workflow skill.
