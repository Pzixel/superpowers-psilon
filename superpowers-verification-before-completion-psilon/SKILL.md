---
name: superpowers-verification-before-completion-psilon
description: Use before claiming completion when work affects production, security, data integrity, concurrency, migrations, external contracts, releases, or broad multi-component behavior, or when the user explicitly requests rigorous verification. Collect fresh outcome-specific evidence after the last relevant change and verify that it covers the exact target scope and load-bearing prerequisites of the claim. Do not use for clear low-risk local edits; perform ordinary focused verification instead.
---

# Verification Before Completion

> **Codex 5.6 adaptation:** The frontmatter description is the scope gate. Match the breadth of fresh evidence to the completion claim after the last relevant change; do not turn this high-risk gate into repeated full-suite ceremony for low-risk or unchanged work.

## Overview

**Core principle:** Evidence before claims, always.

**Violating the letter of this rule is violating the spirit of this rule.**

## The Iron Law

```
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

If you have not gathered fresh evidence after the last relevant change, you cannot claim the affected outcome passes.

## The Gate Function

```
BEFORE claiming any status or expressing satisfaction:

1. DEFINE: State the exact claim and target scope
2. IDENTIFY: Name every load-bearing prerequisite, the command or observation that can prove it at that scope, and where disconfirming or limiting evidence may exist
3. RUN: Execute the command or observation set sufficient for the claim's scope (fresh, complete for that scope)
4. READ: Relevant full output, check exit code, count failures, and inspect outcome evidence
5. VERIFY: Does the evidence cover the exact target, survive the disconfirming-evidence search, and confirm the claim and its prerequisites?
   - If NO or a prerequisite is false: State actual status with evidence
   - If YES: State claim WITH evidence
6. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | The test scope named in the claim reports 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Original symptom passes at the required target boundary and applicable prerequisites are verified | Code changed, a similar fixture passes |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Authoritative requirement-by-requirement evidence at matching target boundaries | Tests passing, plan checklist alone |

## Red Flags - STOP

- Using "should", "probably", "seems to"
- Expressing satisfaction before verification ("Great!", "Perfect!", "Done!", etc.)
- About to commit/push/PR without verification
- Trusting agent success reports
- Extrapolating beyond the scope actually verified
- Thinking "just this once"
- Tired and wanting work over
- **ANY wording implying success without having run verification**

## Rationalization Prevention

| Excuse | Reality |
|--------|---------|
| "Should work now" | RUN the verification |
| "I'm confident" | Confidence ≠ evidence |
| "Just this once" | No exceptions |
| "Linter passed" | Linter ≠ compiler |
| "Agent said success" | Verify independently |
| "I'm tired" | Exhaustion ≠ excuse |
| "This narrow check proves the whole system" | Evidence supports only the boundary and scope it exercised |
| "Different words so rule doesn't apply" | Spirit over letter |

## Key Patterns

**Tests:**
```
✅ [Run test command] [See: 34/34 pass] "All tests pass"
❌ "Should pass now" / "Looks correct"
```

**Regression tests when a permanent test qualifies:**
```
✅ Observe failure before the fix → apply fix → run the admitted regression test (pass)
✅ If the initial failure was not captured, use a safe revert or mutation check only when it is proportionate and does not risk user work
❌ "I've written a regression test" without evidence that it distinguishes the broken behavior
```

**Build:**
```
✅ [Run build] [See: exit 0] "Build passes"
❌ "Linter passed" (linter doesn't check compilation)
```

**Requirements:**
```
✅ Re-read authoritative requirements and target scope → Create checklist → Verify each at its matching boundary → Report gaps or completion
❌ "Tests pass, phase complete"
```

**Agent delegation:**
```
✅ Agent reports success → Check VCS diff → Verify changes → Report actual state
❌ Trust agent report
```

## When To Apply

Apply this skill when its frontmatter trigger matches, before:
- A high-risk success or completion claim
- Commit, push, pull-request, release, or production-completion claims within that risk scope
- Declaring a broad multi-component requirement satisfied

For clear low-risk local edits, run ordinary focused verification instead. Do not re-run unchanged gates before moving between internal steps or before delegation unless new evidence or a named risk requires it.

The evidence rule applies to exact claims, paraphrases, and implications of correctness within the verified scope.

A passing mechanism-level check proves that the mechanism can work in the
exercised scope. It does not prove that required data, configuration, coverage,
or deployment state exists in another target. Treat plans, agent reports, and
prior successful examples as evidence indexes, not proof of current
applicability.
