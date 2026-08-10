---
name: superpowers-verification-before-completion-psilon
description: Use before claiming completion when work affects production, security, data integrity, concurrency, migrations, external contracts, releases, or broad multi-component behavior, or when the user requests rigorous completion proof. Skip clear low-risk local edits. After the last relevant change, prove the exact outcome, target, and prerequisites with fresh evidence.
---

# Verification Before Completion

> **Codex 5.6 adaptation:** The description is the scope gate. Match fresh evidence to the claim; do not turn this high-risk gate into repeated full-suite ceremony for low-risk or unchanged work.

**Core principle:** Evidence before claims, always. Violating the letter violates the spirit.

## Iron Law

```text
NO COMPLETION CLAIMS WITHOUT FRESH VERIFICATION EVIDENCE
```

No fresh evidence after the last relevant change means no affected success claim.

## Gate

Before any success, satisfaction, commit, push, PR, release, or production-completion claim within the trigger scope:

1. **DEFINE** the exact claim and target.
2. **IDENTIFY** each load-bearing prerequisite, matching proof, and likely disconfirming or limiting evidence.
3. **RUN** the complete command or observation set needed for that claim scope.
4. **READ** relevant full output, exit status, failure counts, and outcome evidence.
5. **VERIFY** exact-target coverage, prerequisites, and disconfirming evidence.
   - False or unproved: report actual status and evidence.
   - Proved: state the claim with evidence.
6. **ONLY THEN** claim success.

Skip a step = lying, not verifying.

## Proof Boundaries

| Claim | Required proof | Not enough |
|---|---|---|
| Tests pass | Named test scope reports zero failures | Old run; “should pass” |
| Lint/build passes | Exact command exits zero | Partial check; another gate |
| Bug fixed | Original symptom passes at the required target; prerequisites hold | Code changed; similar fixture |
| Regression test works | Admitted test distinguishes broken and fixed behavior | One passing run |
| Agent completed | Inspect diff and verify outcome | Agent report |
| Requirements met | Each authoritative requirement has matching target-boundary evidence | Tests or plan checklist alone |

A mechanism-level pass proves only that exercised scope. It does not prove another target has the needed data, configuration, coverage, or deployment state. Plans, prior examples, and agent reports are evidence indexes, not proof.

For a qualifying permanent regression test, capture failure before the fix and pass after it. If failure was not captured, use a safe revert or mutation only when proportionate and safe for user work.

## Stop Signals

Stop before claiming success if you are:

- saying “should,” “probably,” “seems,” “great,” “perfect,” or “done” without proof;
- trusting confidence, a prior run, an agent, or a narrow check;
- tired, rushing, or thinking “just once”;
- extrapolating beyond the verified boundary.

Different wording does not evade the rule. Confidence is not evidence; lint is not build; exhaustion is not an exception.

## Scope

Apply before high-risk or broad completion claims and matching commit, push, PR, release, or production claims. For clear low-risk local edits, run focused verification. Do not repeat unchanged gates between internal steps or before delegation without a relevant change or named new risk.
