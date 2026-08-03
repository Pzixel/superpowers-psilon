---
name: superpowers-systematic-debugging-psilon
description: Use when diagnosing an observed technical failure whose root cause is uncertain, especially recurring failures, nondeterminism, concurrency, performance regressions, production incidents, multi-component issues, or after a prior fix failed. Do not use for ordinary feature implementation, known one-line mistakes, or failures with an already-established direct cause.
---

# Systematic Debugging

> Forked from `superpowers:systematic-debugging` v6.2.0. Local changes: narrowed activation, proportional depth, and removal of mandatory cross-skill and universal-test chaining.

## Overview

**Core principle:** Establish the root cause before committing to a fix. Do not mistake a plausible symptom treatment for a diagnosis.

## Proportionality

Use the smallest investigation that can establish cause with evidence. The phases below are reasoning gates, not mandatory documents, task lists, or pauses. If an error message and a bounded source inspection directly establish the cause, proceed without expanding the process. Deepen the investigation only while material uncertainty remains.

## Phase 1: Root Cause Investigation

Before proposing a fix:

1. **Read the evidence carefully**
   - Read the relevant error, warning, stack trace, line number, path, and error code.
   - Distinguish observed facts from assumptions.

2. **Reproduce when feasible**
   - Determine whether the failure is consistent and record the smallest reproduction.
   - If it is not reproducible, gather discriminating evidence instead of guessing.

3. **Check relevant changes and state**
   - Inspect the current diff, recent relevant commits, dependency or configuration changes, and environment differences.
   - Keep the search bounded to plausible causal paths.

4. **Gather boundary evidence for multi-component systems**

   When a system crosses boundaries such as CI → build → signing or API → service → database, determine what enters and exits each relevant component. Verify configuration propagation and state at each layer. Prefer existing logs, metrics, traces, and read-only inspection. Add temporary diagnostic instrumentation only when authorized and when existing evidence cannot distinguish the competing causes.

5. **Trace data flow backward**
   - Identify where the bad value or state is first observed.
   - Find the caller or producer that supplied it.
   - Continue until reaching the earliest supported boundary that introduced the invalid state.
   - Fix at that boundary rather than masking a downstream symptom.

## Phase 2: Pattern Analysis

Before fixing:

1. Find a relevant working example in the same codebase or authoritative reference.
2. Compare the working and failing paths at the decision-owning boundary.
3. Identify differences that could explain the observation.
4. Understand required configuration, state, dependencies, and supported modes.

Read only as much reference material as needed to understand the governing pattern completely. Do not expand into unrelated architecture review.

## Phase 3: Hypothesis and Testing

1. State one falsifiable hypothesis: "I think X is the cause because evidence Y distinguishes it from alternatives."
2. Choose the smallest observation or reversible change that tests that hypothesis.
3. Change one causal variable at a time.
4. If the hypothesis fails, incorporate the evidence and form a new one rather than stacking speculative fixes.
5. If evidence cannot distinguish the remaining causes, say what is unknown and what observation would resolve it.

## Phase 4: Implementation

1. **Select an independent regression check when justified**
   - Add a permanent test only when it protects required observable behavior and could fail under a plausible production regression.
   - Otherwise use the strongest focused build, lint, reproduction, runtime observation, or temporary diagnostic appropriate to the failure.

2. **Implement one root-cause fix**
   - Address the established cause.
   - Avoid unrelated refactoring and "while I'm here" improvements.

3. **Verify the outcome proportionately**
   - Re-run the original reproduction or observe the original failing boundary.
   - Run the focused checks affected by the change.
   - Inspect broader behavior only when the change's reach or risk warrants it.

4. **If the fix does not work**
   - Stop and use the new result as evidence.
   - Return to the earliest invalidated assumption.
   - Do not layer another speculative fix on top.

5. **After three failed fix attempts, question the architecture**

   Three failed fixes can indicate that the model of the system is wrong rather than that one more patch is needed. Stop and discuss the coupling, state ownership, or architectural premise with the user before attempting a fourth materially different fix.

## Red Flags

Stop and return to evidence gathering when you notice:

- "Quick fix now, investigate later."
- "Just change X and see what happens" without a discriminating hypothesis.
- Multiple speculative changes before observation.
- A solution proposed before tracing the relevant data or state.
- An arbitrary retry, timeout, tolerance, or fallback without measured evidence.
- A test-shaped production branch or magic constant.
- Another fix added on top of an unverified failed fix.
- Confidence being used as a substitute for reproduction or runtime evidence.

## Quick Reference

| Phase | Key activity | Exit condition |
|---|---|---|
| Root cause | Read, reproduce, inspect changes, trace boundaries | Cause is supported by evidence |
| Pattern | Compare with working and authoritative behavior | Relevant difference is identified |
| Hypothesis | Test one explanation minimally | Hypothesis is confirmed or rejected |
| Implementation | Make one direct fix and verify | Original failure is resolved at its boundary |

## Environmental or External Causes

If the evidence establishes that the cause is environmental, timing-dependent, or external:

1. State the established cause and remaining uncertainty.
2. Implement handling such as a retry, timeout, diagnostic, or error message only when the supported contract calls for it.
3. Derive parameters from protocol guarantees or measured behavior rather than arbitrary constants.
4. Add monitoring only when it will distinguish recurrence or guide an operational response.
