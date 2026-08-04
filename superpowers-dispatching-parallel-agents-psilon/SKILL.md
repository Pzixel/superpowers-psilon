---
name: superpowers-dispatching-parallel-agents-psilon
description: Use when bounded scoping establishes at least two substantial independent workstreams with distinct deliverables, no sequential dependency, and non-overlapping mutable state, and parallel execution will materially reduce wall time. Dispatch focused agents while the primary retains integration ownership. Do not use for facets of one coupled decision, shared-path reconnaissance, related failures that may share a cause, trivial tasks split artificially, overlapping writes, or automatic review ceremony.
---

# Dispatching Parallel Agents

> Forked from `superpowers:dispatching-parallel-agents` v6.2.0. Local changes: substantial-workstream threshold, bounded scoping, exclusive mutable ownership, and removal of automatic one-agent-per-symptom behavior.

## Goal

Reduce elapsed time on genuinely independent work without multiplying coordination cost, duplicated investigation, or conflicting changes.

## Establish independence

Perform the smallest scoping pass needed to answer:

1. Does each workstream have a distinct deliverable?
2. Can it be understood with bounded context?
3. Can it proceed without waiting for another workstream's result?
4. Is its mutable scope exclusive and non-overlapping?
5. Is there enough work to outweigh dispatch and integration overhead?

If independence is unclear, keep the work with the primary agent until the shared boundary is fixed. Related failures remain one investigation until evidence establishes separate causes.

## Define ownership

For each delegated workstream, specify:

- the concrete outcome;
- exclusive mutable paths or a read-only scope;
- required contracts and constraints;
- source artifacts and commands needed to start;
- prohibited shared-state mutations;
- expected return: findings or changes, evidence, concerns, and unresolved dependencies.

The primary agent owns shared files, integration decisions, final verification, and commits unless active instructions explicitly say otherwise.

## Dispatch

- Dispatch independent agents concurrently when slots and tooling allow.
- Give agents only task-local context; do not pass the whole conversation or leading conclusions.
- Use read-only agents for overlapping investigation when independence of judgment matters.
- Keep useful primary-agent work moving while delegates run.
- Do not spawn replacement agents merely to keep slots full after meaningful parallel work is exhausted.

## Integrate

After results return:

1. Inspect evidence and actual diffs.
2. Reconcile interface or assumption conflicts centrally.
3. Serialize any shared-state mutation.
4. Run focused checks for each deliverable, then one integrated verification pass when required.
5. Report duplicated work, unresolved coupling, or gaps rather than hiding them behind parallel completion.

## Stop conditions

Collapse work back to the primary agent when delegates converge on the same root cause, need the same mutable paths, depend on an unsettled central decision, or cost more coordination than they save.

Parallel dispatch is a scheduling technique, not a requirement to use every available agent.
