---
name: superpowers-brainstorming-psilon
description: Use when a non-trivial requested change has unresolved product intent or success criteria that would materially alter architecture, interfaces, persistent state, multi-component behavior, or long-term maintenance, or when coupled subsystems need decomposition before implementation. Clarify consequential uncertainty, compare materially different approaches, and recommend a proportionate design. Do not use for a clear local change, a single small decision, routine configuration, mechanical edits, or when the user has already supplied an adequate design.
---

# Brainstorming Ideas Into Designs

> Forked from `superpowers:brainstorming` v6.2.0. Local changes: narrow activation, proportional exploration, and removal of mandatory specs, approval loops, visual tooling, and `writing-plans` chaining.

## Goal

Turn an ambiguous idea into the smallest coherent design needed for confident implementation. Preserve natural collaborative dialogue without turning design exploration into a mandatory prelude for every change.

## Boundaries

- Stop using this skill when the request and governing contracts already determine the behavior and no material design choice remains.
- Do not create task lists, specifications, plan documents, commits, visual companions, review loops, or approval gates merely because this skill activated.
- Do not invoke another process skill as a mandatory next step.
- Ask the user only when a missing choice would materially change behavior, scope, authority, cost, or risk and cannot be resolved from available evidence.
- When a reversible assumption is sufficient, state it briefly and continue.

## Process

### 1. Understand the context

- Inspect the current project structure, relevant documentation, governing contracts, and recent related changes.
- Keep reconnaissance bounded to evidence that can affect the design.
- Separate explicit requirements from incidental current behavior and implementation detail.

### 2. Assess scope

- Identify the user-visible outcome, constraints, success criteria, and external boundaries.
- If the request contains multiple independently valuable subsystems, explain the decomposition and recommend an implementation order.
- Do not split a cohesive change merely to create more phases or artifacts.

### 3. Resolve consequential uncertainty

- Identify decisions whose answers materially alter the solution.
- Resolve them from the repository, deployed state, authoritative contracts, or reasonable reversible assumptions when possible.
- If user input is genuinely required, ask one focused question at a time and explain the consequence of the choice.
- Do not ask the user to choose implementation details the agent can determine responsibly.

### 4. Explore approaches

- Propose two or three approaches only when they are materially different and the comparison would change the decision.
- Lead with the recommended approach and explain why it best fits the requirements, existing system, cumulative maintenance cost, and risk.
- State important tradeoffs and rejected alternatives concisely.
- Apply YAGNI: remove behavior and machinery not required by the supported outcome.

### 5. Present a proportionate design

Scale the design to the actual uncertainty:

- For a small but ambiguous change, use a few sentences covering the decision and affected boundary.
- For a multi-component or high-risk change, cover architecture, ownership, interfaces, data flow, failure handling, migration or rollout, and verification where applicable.
- Avoid repeating settled requirements or narrating obvious implementation steps.

Ask for approval only when the proposed design introduces a material product choice, new authority, irreversible consequence, or scope expansion not already authorized. Otherwise, continue with the requested implementation once the design is sufficiently clear.

## Design Quality

### Isolation and clarity

- Give each unit one clear responsibility and define how consumers use it and what it depends on.
- Prefer interfaces that allow internals to change without breaking consumers.
- Use existing abstractions where they fit; add a new boundary only when it closes a real contract gap.

### Existing codebases

- Follow established patterns after verifying that they serve the required behavior.
- Include targeted improvement when an existing problem directly obstructs the requested outcome.
- Do not authorize unrelated refactoring through the brainstorming process.

### Self-check

Before leaving the design, check briefly:

1. Are any requirements, assumptions, or boundaries materially ambiguous?
2. Does the recommended approach satisfy the stated outcome without extra behavior?
3. Are ownership and interfaces coherent at the affected boundaries?
4. Is the scope small enough to implement and verify as one cohesive change?

Fix issues inline. Do not create a separate review cycle unless the design's risk independently warrants one.

## Exit

The terminal state is a sufficiently clear, proportionate design. If the user requested implementation and no new authority is needed, proceed directly. If a material user decision or approval is required, present that exact decision and wait.
