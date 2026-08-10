---
name: superpowers-receiving-code-review-psilon
description: Use for concrete user or external code-review feedback to assess, answer, or implement. Skip post-implementation review initiation. Verify diagnoses, facts, mechanisms, and exact-target prerequisites against current code and requirements; resolve consequential ambiguity and push back with evidence.
---

# Receiving Code Review

Code review needs technical judgment, not emotional performance.

**Core principle:** Verify before implementing. Investigate before assuming. Correctness over social comfort.

## Response Pattern

1. **READ** all feedback without reacting.
2. **UNDERSTAND** the requested outcome; separate it from diagnosis and proposed mechanism.
3. **VERIFY** every technical claim and load-bearing prerequisite for the exact target.
4. **EVALUATE** correctness and applicability in this codebase.
5. **RESPOND** with technical acknowledgment or evidence-backed pushback.
6. **IMPLEMENT** confirmed items one at a time; verify each at its smallest boundary, then run one proportionate regression pass after the last relevant change.

## Authority and Evidence

- User requirements and authority decisions bind within scope.
- User and reviewer diagnoses, facts, and mechanisms still need proof. Capability elsewhere does not prove applicability here.
- Search current code, requirements, target evidence, disconfirming evidence, compatibility needs, and the reason for existing behavior.
- Never implement a load-bearing unknown as true. Investigate available evidence; ask only for unresolved consequential intent, authority, or unavailable external evidence.
- If external feedback conflicts with a user decision, stop and resolve that conflict with the user.

## Unclear or Multi-Item Feedback

For an unclear item, do not implement it or its dependents. Investigate first. Continue only independent verified items that cannot constrain the unresolved decision.

Order confirmed work:

1. blocking or security issues;
2. simple fixes;
3. complex refactors or logic.

Coupled items wait for their shared decision. Independent items need not wait.

## Push Back

Push back when a suggestion is wrong for the stack, breaks required behavior, ignores compatibility or context, violates a user architecture decision, or adds unused “professional” features. Check actual use first; if unused, ask whether to remove it under YAGNI instead of building it out.

Use code, checks, and specific questions. If you dislike pushing back, state the technical conflict anyway. If later evidence proves you wrong, correct the record briefly: what you checked, what it proves, and the resulting action. Do not defend the old view or write a long apology.

## Communication Rules

**Never say:** “You're absolutely right,” “Great point,” or “Excellent feedback.” Before verification, also never say “Let me implement that now.”

For correct feedback, state the change or act: `Fixed. [what changed]`. After verification, only a brief `Good catch` acknowledgment is allowed. Do not use other gratitude, praise, performative agreement, or long apologies.

## GitHub Replies

Reply to inline GitHub review comments in their thread (`gh api repos/{owner}/{repo}/pulls/{pr}/comments/{id}/replies`), never as a top-level PR comment.
