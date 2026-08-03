---
name: superpowers-verification-before-completion-psilon
description: Use before claiming completion when work affects production, security, data integrity, concurrency, migrations, external contracts, releases, or broad multi-component behavior, or when the user explicitly requests rigorous verification. Collect fresh outcome-specific evidence after the last relevant change. Do not use for clear low-risk local edits; perform ordinary focused verification instead.
---

# Verification Before Completion

> Forked from `superpowers:verification-before-completion` v6.2.0. Local changes: high-risk activation and outcome-proportionate verification instead of universal ceremony.

## Overview

**Core principle:** Evidence before claims.

Do not claim a high-risk outcome is complete, fixed, deployed, or passing without fresh evidence sufficient for that exact claim.

## The Gate

Before making a completion claim in this skill's trigger scope:

1. **Identify** the observable outcome and the evidence that would prove it.
2. **Run or inspect** the strongest proportionate verification after the last relevant change.
3. **Read** the complete relevant output, exit status, failure count, runtime state, logs, or metrics.
4. **Compare** the evidence with the claim and governing requirements.
5. **Report** the supported status and every material gap. Claim completion only when no required gap remains.

Verification should be complete for the claim, not mechanically exhaustive. Do not run unrelated suites, recreate already-fresh evidence, or add process artifacts that cannot affect the conclusion.

## Claim-to-Evidence Mapping

| Claim | Evidence normally required | Not sufficient |
|---|---|---|
| Focused tests pass | Fresh targeted test output with zero failures | An earlier run or "should pass" |
| Full suite passes | Fresh full-suite output with zero failures | A targeted subset |
| Build succeeds | Fresh build output with exit status 0 | Linter output |
| Bug is fixed | Original symptom or authoritative observable boundary now succeeds | Code changed or a nearby unit test passes |
| Regression test is meaningful | Test fails without the fix and passes with it, when that red-green check is safe and warranted | Test passes once |
| Requirements are met | Each applicable requirement is tied to code or observed behavior | Tests alone when requirements exceed them |
| Production change is complete | Intended state is active across target scope, durably converged, and observed for regressions | CI success or deployment start |
| Delegated work is complete | Primary inspection of the resulting diff and relevant verification | Agent success report |

## Proportional Verification

Choose evidence by blast radius and uncertainty:

- **Focused code change:** run the affected formatter, compiler, lint, or focused test that can falsify the change.
- **Cross-boundary behavior:** exercise the real boundary or the smallest integration surface that owns the decision.
- **Data or migration change:** verify reachable old and new states, invariants, and recovery behavior.
- **Production behavior:** verify rollout state, live behavior, relevant logs and metrics, durable convergence, and a task-appropriate observation window.
- **Security or destructive behavior:** verify exact scope, authorization, safeguards, outcome, and rollback or recovery evidence.

If the strongest required evidence is unavailable, report the task as incomplete and name the missing evidence. Do not substitute confidence or adjacent checks.

## Regression Tests

Use a red-green check only when a permanent regression test is independently justified and temporarily reverting or toggling the fix is safe. Do not manufacture a test merely to satisfy this skill. Repository test policy and observable contract determine whether the test belongs.

## Requirements and Plans

If an authoritative specification or accepted plan exists, verify its applicable outcomes. Do not create or re-read a plan solely because this skill activated. Examples and implementation steps are not additional requirements unless the user or governing contract made them so.

## Red Flags

- Saying "should", "probably", or "seems" while implying success.
- Relying on verification that predates the last relevant change.
- Treating lint as compilation, compilation as tests, or CI as production verification.
- Trusting a subagent or tool summary without inspecting the material result.
- Running a broad suite when a focused check proves the claim, or a focused check when the claim is broad.
- Hiding a missing live, integration, migration, or recovery check behind lower-authority evidence.

## Reporting

Lead with the actual outcome. Include the decisive verification performed and any remaining gap. Avoid celebratory language that implies more certainty than the evidence supports.
