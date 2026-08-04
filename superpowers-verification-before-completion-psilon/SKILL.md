---
name: superpowers-verification-before-completion-psilon
description: Use before claiming completion when work affects production, security, data integrity, concurrency, migrations, external contracts, releases, or broad multi-component behavior, or when the user explicitly requests rigorous verification. Collect fresh outcome-specific evidence after the last relevant change. Do not use for clear low-risk local edits; perform ordinary focused verification instead.
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

1. IDENTIFY: What command proves this claim?
2. RUN: Execute the command or observation set sufficient for the claim's scope (fresh, complete for that scope)
3. READ: Relevant full output, check exit code, count failures, and inspect outcome evidence
4. VERIFY: Does output confirm the claim?
   - If NO: State actual status with evidence
   - If YES: State claim WITH evidence
5. ONLY THEN: Make the claim

Skip any step = lying, not verifying
```

## Common Failures

| Claim | Requires | Not Sufficient |
|-------|----------|----------------|
| Tests pass | The test scope named in the claim reports 0 failures | Previous run, "should pass" |
| Linter clean | Linter output: 0 errors | Partial check, extrapolation |
| Build succeeds | Build command: exit 0 | Linter passing, logs look good |
| Bug fixed | Test original symptom: passes | Code changed, assumed fixed |
| Regression test works | Red-green cycle verified | Test passes once |
| Agent completed | VCS diff shows changes | Agent reports "success" |
| Requirements met | Requirement-by-requirement evidence at matching boundaries | Tests passing |

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
✅ Re-read plan → Create checklist → Verify each → Report gaps or completion
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
