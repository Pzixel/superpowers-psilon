---
name: superpowers-brainstorming-psilon
description: Use before planning a non-trivial change when unresolved product intent or success could materially alter architecture, interfaces, persistent state, multi-component behavior, or long-term maintenance, or coupled subsystems need decomposition. Skip clear local, routine, mechanical, one-small-decision work and adequate designs. Investigate ordinary choices; verify exact-target prerequisites; compare admitted options; recommend or block.
---

# Brainstorming Ideas Into Designs

> **Codex 5.6 adaptation:** The description is the scope gate. Resolve ordinary engineering choices autonomously; scale artifacts and checkpoints to uncertainty, risk, and handoff value.

Turn an idea into a coherent design through project inspection and natural dialogue.

<HARD-GATE>
Do NOT implement, scaffold, invoke an implementation skill, or write code until the design is coherent and consequential product or authority decisions are resolved. User and repository policy—not this skill—define approval gates for reversible engineering choices.
</HARD-GATE>

Every task that truly matches the trigger uses this process. A clear local task does not match; genuine ambiguity or impact cannot be relabeled “simple.”

## Workflow

1. Inspect current files, docs, and recent commits.
2. Assess scope before detailed questions. If several independent subsystems exceed one spec, define their boundaries, links, and build order; brainstorm only the first subproject. Each gets its own design, plan, and implementation cycle.
3. Infer ordinary details from evidence. Ask one concise question at a time only when unresolved intent, authority, or an external contract would materially change the result. Establish purpose, constraints, and success criteria.
4. Admit candidate approaches using the gate below.
5. Compare two or three materially different admitted approaches; if only one is credible, say why. Lead with the recommendation and trade-offs. Remove unneeded features under YAGNI.
6. Present a proportionate design covering architecture, components, data flow, errors, and verification. Ask after a section only for a consequential user-owned choice; otherwise self-check and continue.
7. Persist, review, and transition only as justified below.

The terminal state is a resolved admissible design or `BLOCKED — no current design is implementable` with the evidence needed to clear it.

## Candidate Admission

For each candidate:

- identify every load-bearing prerequisite;
- verify it with current authoritative evidence for the exact target;
- seek evidence that disproves it or limits coverage;
- reject false prerequisites and conflicts with requirements, contracts, or authority;
- keep an unknown prerequisite conditional and exclude that candidate from the current recommendation.

Implementation support, a working example, or an available integration proves capability only—not target data, coverage, compatibility, or applicability.

If no candidate passes, first collect any available evidence or ask one necessary user-owned decision, then rerun admission. If none can clear the gate, lead with the exact blocked status and evidence needed. A future mechanism may remain a labeled conditional option, never the recommended current design or a planning target. Keep rejected candidates internal unless requested or needed to explain the result.

## Design Quality

- Build small units with one purpose and clear interfaces. Each unit must state what it does, how callers use it, and what it needs; consumers should not need its internals.
- Prefer focused files and independently understandable/testable units. Large, tangled files signal weak boundaries.
- In existing code, inspect and follow established structure. Include only targeted cleanup needed by this change; reject unrelated refactors.
- Scale sections from a few sentences to at most 200–300 words for real nuance. Revisit unclear parts.

## After the Design

Write a durable spec only when complexity, cross-session handoff, an approval boundary, or repository policy gives it lasting value. Use the selected location; otherwise the upstream default is `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`. Use `elements-of-style:writing-clearly-and-concisely` if available. Commit only when authorized.

Review once inline and fix:

1. **Applicability:** every recommended prerequisite is proved for the exact target; disconfirming evidence was checked; unknowns stay conditional.
2. **Completeness:** no `TBD`, `TODO`, gap, or vague requirement.
3. **Consistency:** architecture and feature sections do not conflict.
4. **Scope:** one plan can own the design, or it is decomposed.
5. **Ambiguity:** each requirement has one actionable meaning.

Request user review only when the spec freezes a consequential product decision, crosses an approval boundary, or the user requested a checkpoint. Apply requested changes and re-run the inline review. Otherwise proceed autonomously.

Invoke `superpowers-writing-plans-psilon` only when its durable-plan trigger matches; otherwise use the relevant direct implementation workflow.

## Visual Companion

Offer the browser companion only when a real mockup, layout, diagram, or visual comparison would be clearer than text—never merely because the topic is UI. Make the first offer its own message, with no question or summary beside it:

> “This next part might be easier if I show you — I can put together mockups, diagrams, and comparisons in a browser tab as we go. It's still new and can be token-intensive. Want me to? I'll open it for you.”

Wait. On acceptance, start with `--open`; on refusal, continue in text and do not offer again unless the user raises it. Even after acceptance, use the browser only for visual questions and the terminal for requirements, concepts, trade-offs, or text choices. Read [visual-companion.md](visual-companion.md) before first use.
