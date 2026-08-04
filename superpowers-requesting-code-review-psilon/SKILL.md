---
name: superpowers-requesting-code-review-psilon
description: Use after a coherent implementation when the integrated diff affects security, data integrity, concurrency, migrations, external contracts, production-critical behavior, or several runtime components, or when the user explicitly requests independent review. Run one evidence-based read-only integration review before release or completion. Do not use after every task, for clear low-risk or mechanical changes, merely because implementation is complete, or when review cannot materially reduce remaining risk.
---

# Requesting Code Review

> Forked from `superpowers:requesting-code-review` v6.2.0. Local changes: one high-risk integration review instead of automatic per-task review and fix loops.

## Goal

Obtain an independent challenge to a coherent high-risk change at the point where cross-component defects are visible and findings can still be fixed.

## Prepare the review

Establish:

- the exact requirements and supported outcomes;
- the diff or artifact range under review;
- governing repository rules and external contracts;
- material risks the change can introduce;
- verification already performed and genuine remaining gaps.

Pass source artifacts and requirements, not the implementer's conclusions or a coached severity judgment. Keep the reviewer read-only.

## Review request

Ask one capable reviewer to examine:

1. requirement and contract compliance;
2. cross-component integration and lifecycle behavior;
3. security, data integrity, concurrency, migration, rollback, and operational risks that apply;
4. plausible regressions not covered by current evidence;
5. unnecessary behavior or complexity introduced by the change.

Require actionable findings with severity, evidence, a tight location, impact, and the smallest safe correction. Require the reviewer to say when a claim cannot be verified from the supplied artifacts.

## Handle findings

- Verify every finding against the code, contracts, and runtime reality before changing anything.
- Fix valid release-blocking findings and rerun the affected verification.
- Push back with evidence when a finding is wrong or outside the supported contract.
- Use at most one scoped re-review when material fixes changed the risk surface.
- Do not create open-ended reviewer/fixer loops or treat minor preferences as blockers.

If no independent reviewer is available, perform the same contract/risk pass inline and disclose the lack of independence when it is material.

The terminal state is a reviewed integrated change with material findings resolved or explicitly reported—not another review because a workflow demands one.
