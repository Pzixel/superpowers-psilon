---
name: superpowers-writing-plans-psilon
description: Use when implementation needs a durable plan because it spans three or more coherent stages, multiple components with dependency or interface coordination, a migration or rollout, cross-session handoff, or high-risk sequencing where ordering and recovery matter, or when the user explicitly requests a written plan. Produce outcome-level tasks with exact constraints, dependencies, verification, and recovery where applicable. Do not use as the first process while consequential product or architecture choices remain unresolved; apply superpowers-brainstorming-psilon first, then return to planning. Do not use for a clear local change, routine work, or a task the current agent can implement directly in one session without coordination risk.
---

# Writing Plans

> **Codex 5.6 adaptation:** The frontmatter description is the scope gate. Preserve executor-ready constraints and interfaces, but size tasks around coherent outcomes rather than mandatory 2-5 minute ceremony; follow governing test, commit, workspace, and artifact policy.

## Overview

Write comprehensive implementation plans assuming the engineer has zero session context for the codebase. Document what they cannot safely rediscover: exact constraints, owned files, interfaces, dependencies, authoritative references, verification, rollout, and recovery. Use complete code only where an exact fragile implementation or contract must be transferred. DRY. YAGNI. Follow the governing test and commit policies.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the superpowers-writing-plans-psilon skill to create the implementation plan."

**Context:** Follow the governing repository and user workspace policy. Do not create or depend on a worktree where it is prohibited.

**Save plans to:** `docs/superpowers/plans/YYYY-MM-DD-<feature-name>.md`
- (User preferences for plan location override this default)

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

If consequential product semantics, architecture, persistent ownership, or
success criteria remain unresolved, stop plan drafting and apply
`superpowers-brainstorming-psilon` first. Return here after the design is
coherent. Do not use this precedence rule for ordinary implementation details.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure - but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Task Right-Sizing

A task is the smallest coherent outcome that can be implemented, verified, and accepted independently. Fold setup, configuration, scaffolding, and documentation into the task whose deliverable needs them. Split only where a later executor can own a distinct boundary or where ordering, recovery, or review materially benefits. Each task ends with an independently verifiable deliverable.

## Outcome-Level Granularity

Use the least detail that still lets a fresh executor act without rediscovering consequential decisions:
- Name the concrete outcome, exact files or boundaries, and dependencies
- Include exact signatures, schemas, commands, and values when they are contractual or fragile
- Include a failing-test sequence only when a permanent test qualifies under governing policy
- Include one final task-scoped verification after the last relevant change
- Include commit steps only when governing policy authorizes task-level commits

Use 2-5 minute micro-steps only for fragile, stateful, or safety-critical sequences where missing an operation would plausibly cause failure. Do not copy complete routine implementation code into the plan merely to make it longer.

## Plan Document Header

**Every plan MUST start with this header:**

```markdown
# [Feature Name] Implementation Plan

> **For agentic workers:** Use `superpowers-subagent-driven-development-psilon` only when its substantial-task and delegation trigger matches; otherwise execute with native planning in the current session. Steps use checkbox (`- [ ]`) syntax when a durable checklist is useful.

**Goal:** [One sentence describing what this builds]

**Architecture:** [2-3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

## Global Constraints

[The spec's project-wide requirements — version floors, dependency limits,
naming and copy rules, platform requirements — one line each, with exact
values copied verbatim from the spec. Every task's requirements implicitly
include this section.]

---
```

## Task Structure

The template below illustrates a task where a permanent regression test and a
task-level commit are both admitted. Omit those steps when governing policy does
not admit them; retain the exact observable behavior and verification contract.

````markdown
### Task N: [Component Name]

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

**Interfaces:**
- Consumes: [what this task uses from earlier tasks — exact signatures]
- Produces: [what later tasks rely on — exact function names, parameter
  and return types. A task's implementer sees only their own task; this
  block is how they learn the names and types neighboring tasks use.]

- [ ] **Step 1: Establish the required observable behavior**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Capture the before-change failure when a qualifying regression test or reproduction exists**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Implement the coherent change**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run outcome-proportionate verification after the last relevant change**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit if governing policy authorizes it**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:
- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that omit exact contractual details or leave consequential design choices to the executor; use code blocks only where exact code is the clearest non-redundant contract
- References to types, functions, or methods not defined in any task

## Self-Review

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

**1. Spec coverage:** Skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.

**2. Placeholder scan:** Search your plan for red flags — any of the patterns from the "No Placeholders" section above. Fix them.

**3. Type consistency:** Do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in Task 3 but `clearFullLayers()` in Task 7 is a bug.

If you find issues, fix them inline. No need to re-review — just fix and move on. If you find a spec requirement with no task, add the task.

## Execution Handoff

After saving the plan, continue autonomously under the user's requested outcome and governing authority:

- Invoke `superpowers-subagent-driven-development-psilon` only when its trigger substantively matches the accepted plan and delegation overhead is justified
- Otherwise execute inline using native plan tracking and proportionate checkpoints
- Ask for a handoff choice only when session ownership, external coordination, or a consequential authority boundary cannot be inferred safely
- Do not invoke unavailable upstream execution or branch-finishing skills
