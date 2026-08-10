---
name: superpowers-receiving-code-review-psilon
description: Use when the user or an external reviewer supplies concrete code-review feedback and asks to assess, respond to, or implement it. Verify each claim against the current code and requirements before changing anything; clarify ambiguous items and push back with evidence when needed. Do not use merely because implementation is complete or to initiate a new review.
---

# Code Review Reception

## Overview

Code review requires technical evaluation, not emotional performance.

**Core principle:** Verify before implementing. Investigate before assuming. Technical correctness over social comfort.

## The Response Pattern

```
WHEN receiving code review feedback:

1. READ: Complete feedback without reacting
2. UNDERSTAND: Separate the requested outcome from the reviewer's diagnosis or proposed mechanism
3. VERIFY: Check every technical claim and load-bearing prerequisite against current evidence for the exact target scope
4. EVALUATE: Technically sound and applicable for THIS codebase and target?
5. RESPOND: Technical acknowledgment or reasoned pushback
6. IMPLEMENT: One item at a time, verify each at the smallest relevant boundary
```

## Forbidden Responses

**NEVER:**
- "You're absolutely right!" (explicit instruction-file violation)
- "Great point!" / "Excellent feedback!" (performative)
- "Let me implement that now" (before verification)

**INSTEAD:**
- Restate the technical requirement
- Ask only for consequential intent, authority, or external evidence that remains unresolved after investigation
- Push back with technical reasoning if wrong
- Just start working (actions > words)

## Handling Unclear Feedback

```
IF any item is unclear:
  Do not implement that item or anything that depends on it
  Investigate available code, requirements, and target evidence first
  Ask only if consequential intent, authority, or unavailable external evidence remains unresolved
  Continue verified independent items only when they cannot constrain the unclear decision

WHY: Partial understanding is unsafe when items are coupled, but an unrelated
clear correction need not wait for a separate unresolved item.
```

**Example:**
```
your human partner: "Fix 1-6"
You understand 1,2,3,6. Unclear on 4,5.

If 1-6 share one interface or decision, resolve 4 and 5 before changing any of
them. If 1,2,3,6 are independently verifiable and cannot constrain 4 or 5,
implement those clear items and report the remaining evidence or decision gap.
```

## Source-Specific Handling

### From your human partner
- **Requirements and authority decisions bind** within the partner's scope
- **Diagnoses, factual claims, and proposed mechanisms still require verification** for the exact target; a supported mechanism does not prove it applies here
- Implement after both the requested outcome and the technical basis are established
- Investigate available evidence first; ask if consequential scope remains unclear
- **No performative agreement**
- **Skip to action** or technical acknowledgment

### From External Reviewers
```
BEFORE implementing:
  1. Check: Technically correct for THIS codebase?
  2. Check: Are its load-bearing prerequisites true for the exact target scope?
  3. Check: Is there current evidence that disproves the claim or limits its coverage?
  4. Check: Breaks existing functionality?
  5. Check: Reason for current implementation?
  6. Check: Works on all required platforms/versions?
  7. Check: Does reviewer understand full context?

IF suggestion seems wrong:
  Push back with technical reasoning

IF can't easily verify:
  Do not implement a load-bearing claim as though it were true. Investigate
  when the evidence is available in scope; ask only when missing intent,
  authority, or external evidence requires the human partner.

IF conflicts with your human partner's prior decisions:
  Stop and discuss with your human partner first
```

**your human partner's rule:** "External feedback - be skeptical, but check carefully"

## YAGNI Check for "Professional" Features

```
IF reviewer suggests "implementing properly":
  grep codebase for actual usage

  IF unused: "This endpoint isn't called. Remove it (YAGNI)?"
  IF used: Then implement properly
```

**your human partner's rule:** "You and reviewer both report to me. If we don't need this feature, don't add it."

## Implementation Order

```
FOR multi-item feedback:
  1. Resolve unclear items before their dependents; do not block independent verified items
  2. Then implement in this order:
     - Blocking issues (breaks, security)
     - Simple fixes (typos, imports)
     - Complex fixes (refactoring, logic)
  3. Verify each fix at its smallest relevant boundary
  4. Run one outcome-proportionate regression pass after the last relevant change
```

## When To Push Back

Push back when:
- Suggestion breaks existing functionality
- Reviewer lacks full context
- Violates YAGNI (unused feature)
- Technically incorrect for this stack
- Legacy/compatibility reasons exist
- Conflicts with your human partner's architectural decisions

**How to push back:**
- Use technical reasoning, not defensiveness
- Ask specific questions
- Reference working tests/code
- Involve your human partner if architectural

**If you're uncomfortable pushing back out loud:** Name that tension, then tell your partner about the issue you've seen. They'll appreciate your honesty.

## Acknowledging Correct Feedback

When feedback IS correct:
```
✅ "Fixed. [Brief description of what changed]"
✅ "Good catch - [specific issue]. Fixed in [location]."
✅ [Just fix it and show in the code]

❌ "You're absolutely right!"
❌ "Great point!"
❌ "Thanks for catching that!"
❌ "Thanks for [anything]"
❌ ANY gratitude expression
```

**Why no thanks:** Actions speak. Just fix it. The code itself shows you heard the feedback.

**If you catch yourself about to write "Thanks":** DELETE IT. State the fix instead.

## Gracefully Correcting Your Pushback

If you pushed back and were wrong:
```
✅ "You were right - I checked [X] and it does [Y]. Implementing now."
✅ "Verified this and you're correct. My initial understanding was wrong because [reason]. Fixing."

❌ Long apology
❌ Defending why you pushed back
❌ Over-explaining
```

State the correction factually and move on.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Performative agreement | State requirement or just act |
| Blind implementation | Verify against codebase first |
| Batch without verification | One at a time, verify each at the relevant boundary |
| Assuming reviewer is right | Check if breaks things |
| Avoiding pushback | Technical correctness > comfort |
| Coupled unclear items | Resolve them before their dependents; continue only verified independent items |
| Can't verify a load-bearing claim, proceed anyway | Investigate or report the evidence gap; do not treat it as true |

## Real Examples

**Performative Agreement (Bad):**
```
Reviewer: "Remove legacy code"
❌ "You're absolutely right! Let me remove that..."
```

**Technical Verification (Good):**
```
Reviewer: "Remove legacy code"
✅ "Checking... build target is 10.15+, this API needs 13+. Need legacy for backward compat. Current impl has wrong bundle ID - fix it or drop pre-13 support?"
```

**YAGNI (Good):**
```
Reviewer: "Implement proper metrics tracking with database, date filters, CSV export"
✅ "Grepped codebase - nothing calls this endpoint. Remove it (YAGNI)? Or is there usage I'm missing?"
```

**Unclear Item (Good):**
```
your human partner: "Fix items 1-6"
You understand 1,2,3,6. Unclear on 4,5.
✅ "I checked the current code and requirements. Items 4 and 5 both change the
shared response contract, but the intended format is not specified. I need that
contract decision before changing 4 or 5. Items 1,2,3,6 are independent and can
proceed."
```

## GitHub Thread Replies

When replying to inline review comments on GitHub, reply in the comment thread (`gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`), not as a top-level PR comment.
