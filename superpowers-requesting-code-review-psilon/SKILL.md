---
name: superpowers-requesting-code-review-psilon
description: Use after a coherent implementation when the integrated diff affects security, data integrity, concurrency, migrations, external contracts, production-critical behavior, or several runtime components, or when the user explicitly requests independent review. Run one evidence-based read-only integration review before release or completion. Do not use after every task, for clear low-risk or mechanical changes, merely because implementation is complete, or when review cannot materially reduce remaining risk.
---

# Requesting Code Review

> **Codex 5.6 adaptation:** The frontmatter description is the scope gate. Review one coherent integrated change at a risk boundary; add earlier or repeated review only when distinct evidence shows that it will materially reduce risk.

Dispatch a code reviewer subagent to catch issues before they cascade. The reviewer gets precisely crafted context for evaluation — never your session's history.

**Core principle:** Review at meaningful risk boundaries with precise, independent context.

## When to Request Review

**Use when the trigger matches:**
- After a coherent high-risk integrated implementation
- Before release or merge when the diff crosses a listed risk boundary
- When the user explicitly requests independent review

**Optional only with a concrete reason:**
- When stuck and an independent perspective can test a named uncertainty
- Before a risky refactor when a baseline review materially reduces risk
- After a complex fix whose integrated effects remain uncertain

## How to Request

**1. Get git SHAs:**
```bash
BASE_SHA=$(git merge-base HEAD origin/main)  # or the recorded start of the coherent change
HEAD_SHA=$(git rev-parse HEAD)
```

**2. Dispatch code reviewer subagent:**

Dispatch a read-only reviewer subagent with isolated or minimally forked context, filling the template at [code-reviewer.md](code-reviewer.md).

**Placeholders:**
- `{DESCRIPTION}` - Brief summary of what you built
- `{PLAN_OR_REQUIREMENTS}` - What it should do
- `{BASE_SHA}` - Starting commit
- `{HEAD_SHA}` - Ending commit

**3. Act on feedback:**
- Fix Critical issues immediately
- Fix Important issues before proceeding
- Note Minor issues for later
- Push back if reviewer is wrong (with reasoning)

## Example

```
[Completed a coherent high-risk feature spanning verification and repair behavior]

You: Let me request one integration review before completion.

BASE_SHA=$(git merge-base HEAD origin/main)
HEAD_SHA=$(git rev-parse HEAD)

[Dispatch code reviewer subagent]
  DESCRIPTION: Added verifyIndex() and repairIndex() with 4 issue types
  PLAN_OR_REQUIREMENTS: Task 2 from docs/superpowers/plans/deployment-plan.md
  BASE_SHA: a7981ec
  HEAD_SHA: 3df7661

[Subagent returns]:
  Strengths: Clean architecture, real tests
  Issues:
    Important: Missing progress indicators
    Minor: Magic number (100) for reporting interval
  Assessment: Ready to proceed

You: [Verify the finding, fix the progress indicators, and run focused verification]
```

## Common Rationalizations

| Excuse | Reality |
|--------|---------|
| "I'll just review this qualifying high-risk diff myself" | Independent review is valuable specifically because the change crossed the trigger's risk boundary. Dispatch a reviewer with the diff and requirements; only findings return to the coordinating context. |
| "The reviewer needs my whole session history to understand the change" | Hand it precisely crafted context, never your session's history. That keeps the reviewer on the work product, not your thought process. |

## Red Flags

**Never:**
- Skip review after the trigger's risk conditions have substantively matched
- Ignore Critical issues
- Proceed with unfixed Important issues
- Argue with valid technical feedback

**If reviewer wrong:**
- Push back with technical reasoning
- Show code/tests that prove it works
- Request clarification

See template at: [code-reviewer.md](code-reviewer.md)
