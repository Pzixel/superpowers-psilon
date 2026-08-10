---
name: superpowers-writing-plans-psilon
description: >-
  Use when implementation needs a durable execution plan because it spans three
  or more coherent stages, multiple components with dependency or interface
  coordination, a migration or rollout, cross-session handoff, or high-risk
  sequencing where ordering and recovery matter, or when the user explicitly
  requests a written plan. Produce an evidence-backed, rolling-horizon plan:
  freeze verified contracts and the next risky milestone in executor-ready
  detail while keeping unvalidated later work outcome-level. When a
  consequential user-owned product or architecture decision remains unresolved,
  apply superpowers-brainstorming-psilon first. Do not use for clear local or
  routine work, or work the current agent can implement directly in one session
  without coordination risk. Never invent exact files, interfaces, schemas,
  commands, values, or performance methods merely to make a plan appear
  complete, and never treat implementation capability as proof that an approach
  applies to the exact target scope.
---

# Writing Plans

> **Superpowers v6.2.0 lineage, Codex 5.6 adaptation:** Preserve the upstream
> capability to hand complex work across sessions, but admit detail according to
> evidence. A durable plan is a living decision and coordination artifact, not a
> speculative transcript of implementation.

## Purpose

Write a plan that lets a capable engineer continue without rediscovering
consequential decisions. Preserve required outcomes, verified constraints,
cross-component contracts, sequencing, acceptance, rollout, and recovery.

Assume the executor has no session history, but does have the current repository
and its tools. Do not duplicate facts that are cheap and safe to rediscover. Do
not predict incidental implementation merely to make the plan self-contained.

**Announce at start:** "I'm using the superpowers-writing-plans-psilon skill to
create an evidence-backed implementation plan."

Follow governing user and repository policy. Save the plan at the user-selected
location; otherwise use `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`.

## Establish the Planning Boundary

Before drafting, perform the smallest bounded inspection needed to distinguish:

- the required product outcome and external contracts;
- the exact users, data, environment, deployment, or contract scope to which the outcome must apply;
- verified current repository or runtime facts;
- accepted design decisions and their rationale;
- implementation hypotheses that still need evidence;
- consequential unknowns that can change architecture, scope, or feasibility.

If product semantics, success criteria, persistent ownership, or a consequential
architecture choice remains user-owned and unresolved, stop and apply
`superpowers-brainstorming-psilon` before writing an implementation plan.

If the outcome is settled but implementation feasibility is uncertain, do not
guess a complete design. Write a discovery or prototype milestone with the
evidence to collect, the decision it will resolve, promotion criteria, and a
fallback. Detail later implementation only after that gate clears.

## Evidence Discipline

Every load-bearing plan statement must be supported by at least one of:

1. **Requirement** — explicit user intent, approved outcome, governing policy,
   or real external contract.
2. **Verified fact** — inspected current code, schema, dependency behavior,
   runtime evidence, or an authoritative reference.
3. **Decision** — an engineering choice justified by requirements and verified
   facts, including material tradeoffs.
4. **Provisional hypothesis** — clearly marked, paired with a bounded validation
   step and explicit promote, redesign, or stop criteria.

Classify statements while drafting. The finished plan need not label every
sentence, but it must expose every provisional load-bearing choice and the
evidence gate that controls it. An unknown is not a blank to fill with a
plausible answer.

Never promote correlation, a narrow benchmark, an unrepresentative cohort, a
historical observation, or one agent's architectural preference into a fixed
contract without stating what it actually proves. Record evidence scope and
date when drift matters.

For every selected approach, identify its load-bearing prerequisites. Verify
each one against current authoritative evidence for the exact target scope, and
search for evidence that disproves it or limits its coverage. A supported API,
parser, integration, working example, or prior success proves capability only.
Reject an approach whose prerequisite is false or conflicts with a requirement
or contract. Keep an approach with an unknown load-bearing prerequisite
conditional behind an explicit evidence gate; do not write it as the planned
implementation.

## Use a Rolling Horizon

Match detail to demonstrated certainty:

- Specify the next irreversible, coordinated, or risk-bearing milestone in
  executor-ready detail.
- Keep later milestones at outcome, dependency, invariant, acceptance, and
  recovery level until earlier gates establish their implementation boundary.
- Expand later milestones when new evidence makes their exact design stable.
- If the whole path is already verified and stable, detail the complete plan.

Do not specify an exact API shape, storage design, file decomposition, benchmark
sample count, rollout sequence, or UI representation before its prerequisite
design and feasibility gates clear. It is valid for a durable plan to stop at a
decision boundary and say what evidence authorizes the next revision.

When implementation or new authoritative evidence disproves a plan assumption,
update the plan, record the changed decision and reason, and remove superseded
instructions. Requirements and authority boundaries remain binding; unexpected
implementation difficulty does not silently relax them. Do not rewrite history
as though the new choice had always been known.

## Admit Only Useful Detail

Include an exact file, function, type, schema, command, value, or code fragment
only when at least one condition holds:

- it is contractual or explicitly approved;
- current inspection verified it and downstream coordination depends on it;
- it is a fragile safety, migration, recovery, or ordering instruction;
- it freezes a cross-task interface whose independent executors must share.

Otherwise name the owning module, behavioral boundary, or observable outcome
and let the executor inspect the current tree. Label likely files or interfaces
as candidates when they remain provisional. Prefer symbols over fragile line
numbers.

Use complete code only when literal content is itself the contract or a small
fragile sequence cannot be transferred safely in prose. Do not include
illustrative production counts, timestamps, IDs, performance budgets, benchmark
sample sizes, or expected outputs that could be mistaken for evidence. When a
measurement method is not externally fixed, state the risk and required
confidence, then select and justify the method at the measurement milestone.

Keep one authoritative owner for each fact. Reference approved specs, contracts,
runbooks, and evidence artifacts instead of copying them into the plan. Repeat
only the minimum constraint needed to execute safely.

## Structure Work Around Outcomes

Map verified ownership before defining tasks. Do not "lock in" a file structure
that has not been inspected or a decomposition that a prototype may invalidate.
Follow established repository boundaries; restructuring is a separate decision
that needs its own evidence and value.

A task is the smallest coherent outcome that can be implemented, verified, and
accepted independently. Fold setup, scaffolding, configuration, and docs into
the outcome that needs them. Split only for a real dependency, handoff,
deployment/recovery boundary, or independently meaningful acceptance gate.

Use 2-5 minute micro-steps only for a fragile stateful sequence where omitting or
reordering one operation plausibly causes failure. Do not manufacture tasks for
routine edits, individual files, tests, commits, reviewers, or tools.

## Plan Form

Start every plan with:

```markdown
# [Feature Name] Implementation Plan

> **Living plan:** Keep decisions and progress aligned with current evidence.
> The plan does not mandate delegation or review; select those workflows at
> execution time only when their own triggers match.

**Goal:** [Observable outcome]

**Target scope:** [Exact users, data, environments, deployments, or contracts]

**Fixed constraints:** [Only requirements and accepted decisions]

**Authoritative references:** [Current specs, contracts, evidence, or runbooks]

**Current evidence:** [Verified facts that materially shape the approach]

**Open gates:** [Only load-bearing unknowns; omit when none]
```

Use only the following sections that add value:

```markdown
## Milestone N: [Coherent outcome]

**Status:** Ready | Discovery | Provisional

**Depends on:** [Earlier outcome or evidence gate]

**Scope:** [Verified files/boundaries; label candidates]

**Constraints and interfaces:** [Only fixed or explicitly provisional items]

**Work:** [Enough detail for the current evidence horizon]

**Acceptance:** [Observable result and outcome-proportionate verification]

**Decision gate and fallback:** [Required for Discovery or Provisional status]
```

For multi-session execution, add concise `Progress`, `Decisions`, and
`Discoveries` sections. Record only changes that affect subsequent work. Do not
turn the plan into a terminal log, duplicate runbook, or evidence warehouse.

Include exact verification commands only when verified for the current project
and necessary to prove the outcome. Include commit steps only when governing
policy authorizes milestone commits. Include permanent tests only when they
qualify under governing test policy.

## Explicit Gates, Not Placeholders

These remain plan failures:

- `TODO`, `TBD`, "implement later", or "handle edge cases";
- "write tests" without naming the behavior and oracle;
- an exact-looking file, type, query, schema, value, or command that was not
  verified;
- a provisional choice written as a final instruction;
- downstream detail that assumes an uncleared feasibility or design gate;
- duplicated specifications or operational procedures with another owner.

Replace vague placeholders with an explicit gate:

```markdown
**Discovery:** Determine whether the existing association table preserves the
required literal identity at the captured version.

**Evidence:** Inspect its schema, replacement semantics, and one corrected-row
history; compare against the required identity and snapshot contract.

**Decision:** Reuse it if all fields and as-of reconstruction are sufficient;
otherwise stop and design a new owner before planning downstream queries.
```

The gate is actionable without pretending the result is already known.

## Self-Review

Before saving the plan, perform one inline review:

1. **Outcome coverage:** Does every requirement map to an outcome or acceptance
   check without adding unsupported behavior?
2. **Evidence audit:** Can every load-bearing detail be traced to a requirement,
   verified fact, justified decision, or explicit provisional gate?
3. **Applicability audit:** Is every selected approach's load-bearing prerequisite verified for the exact target scope, with disconfirming evidence checked? Is capability kept separate from coverage?
4. **Interface consistency:** For contracts frozen inside the current planning
   horizon, do producer and consumer milestones use the same names, types,
   formats, method signatures, and ownership? Do not audit provisional later
   interfaces as though they were fixed.
5. **False-precision audit:** Remove or qualify guessed files, schemas,
   interfaces, commands, values, cohorts, benchmark methods, and timings.
6. **Horizon audit:** Is later work less detailed where earlier evidence gates
   can still change it?
7. **Ownership audit:** Does the plan reference rather than duplicate specs,
   runbooks, policy, and evidence?
8. **Execution audit:** Remove mandatory subagent, reviewer, worktree, TDD,
   commit, or release ceremony not required by governing policy or a separately
   matching skill trigger.
9. **Restartability:** Could a fresh executor identify current state, the next
   milestone, and every unresolved gate without relying on session history?

Fix issues inline once. Do not dispatch a reviewer merely because a plan exists.
For an explicit or independently justified high-risk plan review, use
`plan-document-reviewer-prompt.md` and fill `[PLAN_FILE_PATH]`,
`[TARGET_SCOPE]`, and `[AUTHORITATIVE_REFERENCES]` with the plan, exact target
scope, and current sources that can prove or disprove its prerequisites.

## Continue Execution

After saving the plan, continue toward the user's requested outcome under the
governing authority. Detail or revise later milestones only as their gates
clear.

Invoke `superpowers-subagent-driven-development-psilon` only when its own
substantial-task and delegation trigger matches at execution time. Otherwise
execute inline with native plan tracking and proportionate checkpoints. Ask for
direction only when a consequential user choice, external coordination, or
authority boundary cannot be resolved safely.
