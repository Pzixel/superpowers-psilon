---
name: superpowers-systematic-debugging-psilon
description: Use for an observed technical failure with uncertain root cause, especially recurrence, nondeterminism, concurrency, performance regression, production incident, multi-component failure, or a failed prior fix. Skip feature work, known one-line mistakes, and established direct causes.
---

# Systematic Debugging

> **Codex 5.6 adaptation:** The description is the scope gate. Preserve root-cause-first investigation for uncertainty; use bounded confirm-fix-verify for a known direct cause. Follow governing authority and test-admission policy.

**Core principle:** ALWAYS establish root cause before a fix. Symptom fixes fail. Violating the letter violates the spirit.

## Iron Law

```text
NO FIXES WITHOUT ROOT-CAUSE INVESTIGATION FIRST
```

No completed Phase 1 means no proposed fix.

Use this especially under time pressure, after failed fixes, when a “quick fix” looks obvious, or when you do not understand the issue. Do not skip because the symptom looks simple or someone wants speed. For a proved direct mistake, confirm, make the smallest coherent fix, and verify; do not inflate it into this workflow.

## Four Ordered Phases

You MUST complete each phase before the next.

### 1. Root Cause

Before any fix:

1. **Read errors:** inspect full messages, warnings, stacks, paths, lines, and codes.
2. **Reproduce:** record exact steps and consistency. If it will not reproduce, gather data; never guess.
3. **Check change:** inspect diffs, commits, dependencies, configuration, and environment.
4. **Locate the failing boundary:** in multi-component flows, observe inputs, outputs, state, and config at each boundary. Prefer read-only evidence; instrument only when needed and authorized. Use the smallest safe observation that isolates the failing component, then investigate it.
5. **Trace data:** for a deep symptom, trace the bad value and callers backward to its source. Fix the source, not the visible sink. See [root-cause-tracing.md](root-cause-tracing.md).

### 2. Pattern

1. Find similar working code in the same repository.
2. Read any reference implementation completely; partial understanding causes bugs.
3. List every difference, however small.
4. Map required components, settings, environment, state, and assumptions.
5. For each reference pattern, identify load-bearing prerequisites; verify them for the exact failing target and seek missing dependency, config, state, coverage, or contract. A working example proves capability only. Unknown applicability remains a conditional hypothesis, never a proposed fix.

### 3. Hypothesis

1. State one specific theory: “X is the root cause because Y,” including target scope and verified prerequisites.
2. Test one variable with the smallest possible change; never bundle fixes.
3. If confirmed, continue. If not, form a new hypothesis—do not stack another fix.
4. If unknown, say exactly what is unknown and investigate. Ask only when consequential intent, authority, or unavailable external evidence blocks progress.

### 4. Fix

1. Capture the simplest independent failing reproduction. Record pre-fix evidence when feasible. Add a permanent regression test only when governing policy admits it; otherwise use and remove a focused temporary check.
2. Make one root-cause fix. No “while here” work or bundled refactor.
3. Re-run the reproduction and admitted related checks. Confirm the issue is gone. Use `superpowers-verification-before-completion-psilon` only when its high-risk trigger matches; otherwise verify directly.
4. If it fails, STOP and count attempts. Below three, return to Phase 1 with the new evidence. At three or more, do not attempt fix four before reassessing architecture and shared assumptions.

Three failed fixes suggest—not prove—a bad model or architecture. Look for new coupling at each attempt, massive required refactors, or new symptoms elsewhere. Return to requirements and boundary evidence. Resolve from evidence when possible; ask only for an unresolved consequential product or authority choice.

## Stop Signals

Return to Phase 1 if you think:

- “quick fix now, investigate later,” “probably X,” or “just try it”;
- “change several things and run tests”;
- “skip the failing reproduction”;
- “I do not understand, but this might work”;
- “the reference is long; I will adapt it”;
- “one more attempt” after two failures;
- or you list fixes before tracing data.

Also reset when the user asks “is that not happening?”, “will it show us...?”, says “stop guessing,” questions whether you are stuck, or asks for deeper thought. Those signals mean your evidence or model is weak.

Common excuses do not change the rule: emergencies make systematic work more valuable; confidence is not root cause; parallel fixes hide causality; a symptom is not its source; and three failed attempts require model review, not persistence.

## If No Repository Root Cause Exists

Only after boundary evidence excludes supported repository-owned causes may you classify the issue as environmental, timing-based, or external. Document the search; verify that required behavior and authority permit handling; add the smallest applicable retry, timeout, or accurate error only when its exact-target prerequisites hold. Add telemetry only when authorized and able to distinguish remaining modes.

Failure to find an internal cause does not prove an external one. Unknown remains unknown.

## Supporting Techniques

- [root-cause-tracing.md](root-cause-tracing.md) — trace backward to the trigger
- [defense-in-depth.md](defense-in-depth.md) — guard only evidenced independent boundaries after root cause
- [condition-based-waiting.md](condition-based-waiting.md) — replace arbitrary delays with condition polling
