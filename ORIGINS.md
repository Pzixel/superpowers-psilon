# Superpowers psilon provenance and adaptation ledger

## Pinned baseline

- Upstream: <https://github.com/obra/superpowers>
- Release: `v6.2.0`
- Annotated tag object: `0e5cc50e782429b95f933e46443898435b8b37a8`
- Source commit: `3dcbd5c4b48e02263fbf4a3c01e3fe4f81d584d9`
- Fork date: 2026-08-04
- License: MIT; see `LICENSE.superpowers`

The eight directories in this repository are provenance-named personal forks,
not upstream plugin installations. The original plugin remains disabled. Each
fork keeps `superpowers-<upstream-name>-psilon` as both its directory and
frontmatter name so users can identify its lineage.

## Preservation rule

Upstream v6.2.0 is the default authority for bodies, prompts, scripts, examples,
and process knowledge. A local deviation requires at least one of:

1. A direct conflict with higher-priority Codex, user, or repository policy.
2. An upstream dependency or tool that is unavailable in the retained skill set.
3. A measured harmful execution trace.
4. A paired evaluation showing a safer or more efficient result without losing
   the skill's intended capability.

Prefer narrower frontmatter activation, conditional wording, progressive
disclosure, or a native Codex equivalent over deletion. Syntax validation alone
does not prove trigger accuracy or capability preservation.

## Evidence used for adaptations

- The user-provided trivial-filter trace took about 46 minutes and 400,177 goal
  tokens after a one-line `1h` option activated process cascades. This supports
  excluding clear local changes from brainstorming, planning, delegation,
  automatic review, and high-risk verification.
- The user's operating policy requires autonomous resolution of ordinary
  reversible engineering choices, with questions reserved for consequential
  intent or authority boundaries. This supports conditionalizing mandatory
  approval and execution-menu gates.
- The active repository policy explicitly forbids worktrees, authorizes direct
  work on the current branch, admits tests only when they protect required
  observable behavior, and requires outcome-proportionate fresh evidence. This
  supports deferring workspace, branch, test, and verification defaults to the
  governing repository.
- Codex skill metadata is the implicit activation surface; the body loads after
  activation. This supports changing descriptions first and retaining method
  content after the narrower gate.
- Codex collaboration inherits the parent model and reasoning effort by
  default. Model overrides should be exceptional and use supported runtime
  names, so upstream's mandatory generic tier override was conditionalized.
- Retained skills do not include `using-git-worktrees`, `executing-plans`,
  `finishing-a-development-branch`, or `test-driven-development`. References
  that made those unavailable skills mandatory were redirected or made
  conditional.

## Global metadata deviations

Every fork changes only these metadata fields:

- `name` becomes the provenance-preserving `-psilon` name.
- `description` becomes a positive trigger plus explicit negative boundaries.
- `agents/openai.yaml` keeps `policy.allow_implicit_invocation: true` so hard
  tasks activate automatically; users do not need to opt in.

The body repeats a short “Codex 5.6 adaptation” scope note where upstream body
language would otherwise broaden the frontmatter trigger. The note does not
replace the upstream method.

## Clause-level deviations

### `superpowers-brainstorming-psilon`

Retained: project exploration, scope decomposition, one-question discipline when
a question is necessary, approach comparison, YAGNI, design presentation,
isolation and file-boundary guidance, existing-codebase guidance, spec
self-review, visual companion, its reviewer prompt, and all five companion
scripts.

| Upstream clause | Evidence | Ppsilon adaptation |
|---|---|---|
| Use before every creative change, including config and single-function work | Trivial-filter trace; metadata is Codex's activation gate | Trigger only for consequential unresolved design or coupled decomposition; clear local work is excluded |
| No implementation until user approval for every project | Autonomous operating policy | Keep the no-implementation-before-design gate, but require external approval only for consequential user-owned or authority decisions |
| Mandatory nine-item checklist and user approval after each design section | Trivial-filter trace; autonomous operating policy | Preserve the sequence as applicable tasks; investigate and infer first, then ask only consequential questions |
| Always propose 2-3 approaches | No value when only one viable approach survives evidence | Compare 2-3 materially viable approaches; explain when only one is credible |
| A direct plan request could bypass brainstorming despite unresolved architecture | Paired Sol High hard-task run selected writing-plans alone | Explicitly activate brainstorming before planning only when consequential product or architecture choices remain unresolved |
| Always write and commit a design spec | Trace and repository artifact/commit policy | Persist a spec only when complexity, handoff, approval, or repository policy gives it durable value; commit only when authorized |
| Mandatory second user review of the written spec | Autonomous operating policy | External review is conditional on an approval boundary, explicit checkpoint, or consequential product decision |
| Writing-plans is the only terminal state | Retained set and proportional-execution goal | Invoke `superpowers-writing-plans-psilon` only when its own hard-task trigger matches; otherwise implement directly |
| Plugin-root path to the visual guide | Fork is a standalone skill directory | Use the relative `visual-companion.md` path |

`visual-companion.md` adds one path-resolution note; all companion code and
the rest of the guide are unchanged from upstream.

### `superpowers-dispatching-parallel-agents-psilon`

Retained: independence analysis, domain grouping, focused prompt structure,
concurrent dispatch, failure examples, integration review, and spot checks.

| Upstream clause | Evidence | Ppsilon adaptation |
|---|---|---|
| Two or three independent items are sufficient regardless of size | Delegation overhead must be outweighed | Require at least two substantial independent deliverables and material wall-time benefit |
| Agents should never inherit session history | Codex supports bounded turn forks rather than a single inheritance mode | Prefer `fork_turns: "none"` or the smallest useful fork; allow full history only when genuinely required |
| “No shared state” framed only as investigation state | Codex agents share a filesystem | Require non-overlapping mutable scopes and primary-agent integration ownership |
| Parallel trigger also matched tasks inside one accepted SDD plan | Two of three Sol High activation trials selected both process skills | Exclude tasks already governed by `superpowers-subagent-driven-development-psilon`; parallel owns separate external workstreams |
| Always run the full suite after integration | Outcome-proportionate verification policy | Run the focused or full integrated checks required by the claim's scope |

### `superpowers-receiving-code-review-psilon`

The upstream body is unchanged. Only the name and trigger description differ.
The technical-verification pattern, skepticism, feedback ordering, pushback
guidance, examples, and GitHub inline-reply guidance are preserved.

### `superpowers-requesting-code-review-psilon`

Retained: independent read-only reviewer, precise context, requirements and git
range, severity calibration, action on findings, reviewer rubric, output format,
and example findings.

| Upstream clause | Evidence | Ppsilon adaptation |
|---|---|---|
| Review after every task, every major feature, and before every merge | Trivial-filter trace; proportional review policy | Trigger one integrated review at explicit high-risk boundaries or user request; repeat only for a named residual risk |
| Review early, review often | Same | Review at meaningful risk boundaries |
| Default `HEAD~1` base | Drops multi-commit coherent changes | Use the recorded change start or repository-authoritative merge base |
| Reviewer may create a temporary git worktree | Governing repositories may prohibit all worktrees | Use read-only git inspection; a temporary archive/clone is conditional on governing policy |
| Never skip review because work is simple | Narrow trigger already excludes low-risk work | Never skip after the high-risk trigger substantively matches |

The complete `code-reviewer.md` prompt is restored; only its worktree fallback
sentence is adapted.

### `superpowers-subagent-driven-development-psilon`

Retained: fresh task briefs, per-plan workspace and recovery ledger, implementer
report contract, preflight contradiction scan, role-aware model reasoning,
sequential implementers, task review rubric, five-round bounded fix loop,
scoped re-review, adjudication ledger, final integrated review, all three prompt
templates, and all three scripts.

| Upstream clause | Evidence | Ppsilon adaptation |
|---|---|---|
| Activate for any plan with independent tasks | Delegation/review overhead must be material | Require at least three substantial tasks or two independently large tasks with non-overlapping ownership |
| Independent tasks also matched the generic parallel skill | Two of three Sol High activation trials selected both process skills | SDD owns a controlled task sequence inside its plan; parallel dispatch is excluded for those tasks |
| Mandatory worktree and prohibition on main/master | Direct repository-policy conflict | Follow governing workspace and branch policy; never create a prohibited worktree; allow current branch when authorized |
| Use unavailable `executing-plans` outside the session | Retained-set boundary | Route to durable handoff or native execution |
| Ask the human to adjudicate every plan conflict | Autonomous operating policy | Resolve from authoritative requirements/policy when one clearly governs; batch only consequential unresolved choices |
| Always specify a generic model tier | Codex inherits the parent model and supports a bounded model set | Inherit by default; override only for a supported, justified role-specific need |
| Use unavailable requesting-review and branch-finishing skill names | Retained-set boundary | Point final review to the psilon reviewer prompt and follow governing integration/handoff policy |
| Delete scratch workspace with a raw `rm -rf` instruction | Destructive-action policy | Validate the exact workspace path and prefer recoverable deletion; never touch sibling workspaces |
| Implementer always asks on uncertainty, always commits, and runs a full suite | Autonomous, git, and verification policy | Resolve ordinary choices autonomously; commit only when authorized; run one outcome-proportionate final pass |

Prompt model fields are optional instead of mandatory. The scripts are byte-for-
byte upstream copies and retain executable mode.

### `superpowers-systematic-debugging-psilon`

Retained: root-cause iron law, four phases, error reading, reproduction,
change analysis, boundary evidence, data-flow tracing, working-reference
comparison, single hypotheses, minimal experiments, fix-at-source discipline,
failed-fix architecture reassessment, rationalization checks, root-cause
tracing, condition-based waiting, polluter script, and pressure examples.

| Upstream clause | Evidence | Ppsilon adaptation |
|---|---|---|
| Activate for every bug, build failure, or obvious mistake | Trivial-work proportionality requirement | Trigger when root cause is uncertain; use bounded confirm-fix-verify for an established direct cause |
| Add diagnostic instrumentation before multi-component fixes | Diagnose requests and production authority may be read-only | Prefer read-only boundary evidence; instrument only when needed and authorized |
| Every fix must add a failing test and invoke universal TDD | Retained set excludes TDD; repository test-admission policy | Require a failing reproduction; add a permanent regression test only when it protects admitted observable behavior |
| Always invoke upstream verification skill | Retained-set boundary and proportional verification | Invoke psilon high-risk verification only when its trigger matches; otherwise use focused verification |
| Discuss architecture with the human after three failures | Autonomous operating policy | Reassess from evidence; ask only for a consequential unresolved product or authority choice |
| Defense-in-depth validates at every layer | Repository validates at independent input boundaries and trusts constructed values | Validate each independently reachable untrusted boundary once; add later containment only for a distinct failure mode |

`defense-in-depth.md` is conditionalized accordingly. All other debugging
resources are unchanged.

### `superpowers-verification-before-completion-psilon`

Retained: evidence-before-claims iron law, identify/run/read/verify gate,
claim-to-evidence table, rationalization checks, test/build/requirement/delegate
examples, and explicit reporting of failed evidence.

| Upstream clause | Evidence | Ppsilon adaptation |
|---|---|---|
| Activate before every positive state statement, internal task transition, or delegation | Trivial-filter trace; frontmatter activation model | Trigger for high-risk/broad completion or explicit rigorous verification; low-risk work uses ordinary focused checks |
| Verification must run “in this message” | Codex work spans commentary and tool events | Evidence must be fresh after the last relevant change |
| Always execute the full command and reject partial checks | Claim scope determines sufficient evidence | Run the complete command or observation set for the stated scope; never extrapolate beyond it |
| Regression proof always uses destructive revert red-green | Test-admission and destructive-action policy | Require before/after distinguishing evidence; use revert/mutation only when safe and proportionate |
| Re-run gates before moving or delegating | Repeated unchanged gates add no evidence | Re-run only after relevant change or for a named new risk |

### `superpowers-writing-plans-psilon`

Retained: scope decomposition, file responsibility mapping, explicit interfaces,
global constraints, exact files and commands, no placeholders, coverage and type
self-review, executable task structure, and the upstream plan-review prompt.

| Upstream clause | Evidence | Ppsilon adaptation |
|---|---|---|
| Activate for any multi-step requirement before code | Trivial-filter trace | Trigger only when a durable plan is justified by stages, cross-component coordination, migration/rollout, handoff, or sequencing risk |
| Writing-plans could activate before unresolved architecture was designed | Paired Sol High hard-task run | Defer to `superpowers-brainstorming-psilon` only for consequential unresolved product or architecture choices, then resume planning |
| Universal TDD, frequent commits, and complete implementation code | Test/commit policy and measured plan bloat | Follow governing policies; include complete code only for fragile exact contracts |
| Every step is a 2-5 minute action | User-provided 46-minute trivial trace and earlier oversized-plan evidence | Use coherent outcome-level tasks; micro-steps only for fragile stateful or safety-critical sequences |
| Every task earns a fresh reviewer gate | Review overhead must be justified | Split at independently ownable, verifiable, or risk-reducing boundaries |
| Mandatory worktree context | Direct repository-policy conflict | Follow governing workspace policy |
| Mandatory psilon SDD or unavailable executing-plans menu | Retained-set and autonomous-execution policy | Invoke psilon SDD only when its trigger matches; otherwise execute natively without a user menu |

`plan-document-reviewer-prompt.md` is fully restored and labeled optional for
an explicit or independently justified high-risk plan review; it is not
dispatched automatically.

## Skills intentionally not migrated

These upstream skills remain disabled because their literal verdict was
“Disable,” not “retain with a narrower trigger”:

- `using-superpowers`
- `executing-plans`
- `test-driven-development`
- `using-git-worktrees`
- `finishing-a-development-branch`
- `writing-skills`

## Validation record

Validation was run on 2026-08-04 with Codex CLI `0.146.0-alpha.9.2`, model
`gpt-5.6-sol`, and `model_reasoning_effort="high"`. Behavioral comparisons used
ephemeral temporary repositories; they did not write to production or a user
working tree.

### Structure and resources

- `quick_validate.py`: all eight skill directories valid.
- Pinned-resource comparison: 25 of 25 companion files present, no mode
  mismatches. Eighteen are byte-for-byte upstream copies. The seven modified
  resources are exactly those identified above: the visual-path guide, review
  prompt, three SDD prompts, defense-in-depth guide, and optional plan reviewer.
- Syntax checks passed for all shell scripts and both JavaScript companions.
- A temporary Git smoke test exercised `sdd-workspace`, `task-brief`, and
  `review-package`: the workspace remained ignored, Task 1 extraction stopped
  at Task 2, and the generated package contained the exact one-commit diff.
- Actionable skill bodies and prompts contain no calls to unavailable upstream
  skills, mandatory generic model overrides, or unconditional worktree/TDD
  cascades. Remaining `full suite` and `2-5 minute` text is explicitly
  conditional or illustrative.

### Activation matrix

Three independent description-level Sol High trials covered ten scenarios.

| Scenario | Ppsilon selection |
|---|---|
| Clear local `1h` filter edit | None |
| Unresolved tenant/billing architecture | Brainstorming |
| Accepted multi-stage migration specification | Writing plans |
| Nondeterministic multi-component failure | Systematic debugging |
| Concrete external review feedback | Receiving code review |
| Completed high-risk authentication and migration change | Requesting review and verification |
| Accepted four-task plan with disjoint ownership | SDD only in the final three-trial rerun |
| Distinct substantial failures | Parallel dispatch |
| Obvious typo with direct cause | None |
| Related uncertain failures | Systematic debugging, not parallel dispatch |

The initial accepted-plan case selected both SDD and generic parallel dispatch
in two of three trials. After making ownership explicit, a focused three-trial
rerun selected only SDD every time. This is the measured basis for that trigger
deviation.

### Paired task behavior

Token counts are Codex-reported usage for one representative run per variant;
wall time is approximate because process startup and result polling were
external to the usage record.

| Task | Variant | Activated process | Input | Output | Reasoning | Approx. wall time |
|---|---|---|---:|---:|---:|---:|
| Add `1h` beside `24h`, `7d`, `30d` and run the focused check | Upstream v6.2.0 | Brainstorming and verification; review prompt also inspected | 207,673 | 2,157 | 836 | 100 s |
| Same trivial edit | Ppsilon | None; direct inspect, edit, check, diff | 131,191 | 883 | 159 | 45 s |
| Design and plan tenant isolation plus a 10M-row migration | Upstream v6.2.0 | Brainstorming and writing plans | 53,248 | 3,142 | 1,563 | Not recorded |
| Same hard design and plan, final trigger revision | Ppsilon | Brainstorming then writing plans | 55,849 | 2,429 | 1,146 | Not recorded |
| Diagnose nondeterministic duplicate processing across queue, workers, leases, and PostgreSQL | Upstream v6.2.0 | Systematic debugging | 68,000 | 1,647 | 837 | Not recorded |
| Same uncertain failure | Ppsilon | Systematic debugging | 33,778 | 1,474 | 823 | Not recorded |

Both hard design runs compared isolation alternatives and produced a coherent
migration plan. Both debugging runs identified lease-expiry overlap as the
leading hypothesis, retained credible alternatives, and proposed a correlated
timeline experiment. The psilon result therefore preserves the relevant hard-
task method rather than merely suppressing activation.

No live multiagent implementation was launched solely for evaluation. Static
inspection confirms that a qualifying four-task SDD plan retains at least four
implementer dispatches, four task-review dispatches, and one final integrated
review before any fix rounds. That cost is intentional behind the substantial-
plan trigger and absent from the trivial-edit path.
