---
name: pareto-design-selection
description: Use when several reasonable strategies could change how a system decides (ordering, selection, allocation, scheduling, retry, throttling, routing), a wrong choice is visible in production, clients, or money, the business owner makes the final call, and the decision can be isolated as a pure function over observed facts. Drives a read-only probe, a calibrated pure simulation, one strategy-by-metric table, and a Pareto set the owner chooses from. Skip when one option is obviously right, reversal is cheap, the design concerns execution, rendering, or UI rather than deciding, or no pure decision core can be extracted; say so and stop.
---

# Pareto Design Selection

Choose a decision strategy by simulation, not by argument. The owner decides
from a Pareto set built on measured production facts; the agent supplies the
facts, the model, the table, and a recommendation.

<HARD-GATE>
Do not design, code, or recommend a strategy before the decision core is
isolated, the production probe is complete, and the current strategy is
calibrated in the model. Numbers without a source query, comparisons before
calibration, and recommendations without the full table are defects, not
shortcuts.
</HARD-GATE>

## 0. Isolate the decision core

State the decision as one pure function: observed facts in, complete decision
out. Name every input fact and the full output (what is chosen, in which order,
with which identities). Execution, side effects, rendering, and persistence
stay outside the core; the skill designs how the system decides, not how it
acts or displays.

If no such function can be isolated, the skill does not apply. Report that and
stop; do not simulate an execution path or a UI.

## 1. Goal and success metric

- Restate the owner's goal as a checkable property that a measurement can
  confirm or refute. A vague adjective is not a goal.
- Record separately the constraints that may not move (caps, excluded
  tenants, contractual limits) and the dimensions the owner does not care
  about.
- Derive 3 to 6 metrics from the goal. Exactly one is primary. The others
  capture side effects the choice can worsen: load on external systems,
  waiting time of small participants, evenness, cost.

## 2. Real parameters before the model

- One read-only production probe collects everything the model needs: data
  shape, capacities, durations as distributions rather than averages,
  throughput, failure frequency, and the current value of the primary metric.
  That current value is the number every strategy must beat.
- Every number carries the query or command that produced it. A number that
  cannot be measured is a gap, never a guess. Each gap becomes an explicit
  assumption and is later varied in the sensitivity run.
- Expect the probe to refute the initial picture. Rebuild the problem
  statement from the data before designing anything; a strategy space built on
  the pre-probe picture is wasted work.

## 3. Strategy space

- At least 3 strategies, preferably 6 to 8. Two members are mandatory:
  - the current behaviour, as the baseline;
  - the cheap extension of the existing mechanism (configuration, a priority,
    an index). It must be refuted by data, never dismissed in advance, and
    if it suffices the answer is to build nothing.
- Cover different principles rather than variations of one: queue,
  round-robin, fair share, recency, lottery, hybrid.
- Each strategy is an exact ordering or selection rule over observable facts.
  "Smart choice" or "adaptive" without a rule is not a strategy.
- Orthogonal switches (random versus pinned member within a group, batch
  size) are a separate axis evaluated across strategies, not new strategies.
- Hand the heavy analysis to the strongest available analyst before
  simulating: the model, the traps, and feasibility in real code. The analyst
  names in advance what breaks each strategy in production, such as window
  truncation in the query, query cost at real volume, or facts that diverge
  between layers. Strategies that cannot survive production are dropped here
  with the reason recorded.

## 4. Pure simulation

- The model is pure functions and a fake clock. No network, no database, no
  wall time. The strategy is injected as the ordering or selection function
  from step 0.
- Inputs come only from the probe: distributions are sampled from measured
  data, and the population shape is loaded from a real production export, not
  synthesised.
- Calibration is mandatory. The current strategy inside the model must
  reproduce the measured production value of the primary metric within a
  tolerance fixed before the run. If it does not, fix the model, never the
  targets. Record every rejected model variant with the reason; that is
  knowledge about the system.
- Run all strategies across all scenarios (current load, minimum and maximum
  capacity, a new large participant, failures) and several seeds, with the
  same seeds for every strategy. Choose a horizon long enough for slow effects
  to surface.
- Sensitivity: vary every assumption that came from a gap. Record whether the
  choice changes. An assumption that can flip the choice must be measured or
  escalated, not left as is.

## 5. Table and Pareto set

- Produce one summary table: strategy by metric, plus a cost-in-production
  row for each strategy (code to change, new indexes or storage, operational
  risk).
- The Pareto set is the strategies that no other strategy beats on every
  metric. Differences below a threshold fixed in advance (default 20%) count
  as ties; otherwise noise decides for the business.
- For each Pareto member, state in plain words what it pays for its
  advantages.
- Give a separate verdict on the cheap extension: why it is insufficient, or
  why it suffices and nothing needs to be built.
- Show the owner the whole table, never only the conclusions.

## 6. Business choice

- The owner chooses from the Pareto set. The agent recommends and explains
  but does not decide for the owner.
- Technical questions that appear on the way (priorities between neighbours,
  the exact definition of a metric) are decided by the agent from the data,
  with the reasoning recorded alongside the table.

## 7. From choice to production

- The design of the chosen strategy receives an independent review before
  any code.
- Fix the cost threshold in advance. Measure it read-only on production in
  the mode the code really runs: real parameters, the real connection pool,
  prepared statements, enough repetitions. A simplified-mode measurement has
  been wrong by an order of magnitude.
- The PR carries the rationale, the table, the Pareto set, the calibration
  result, the assumptions, and a folder with the data and scripts that
  reproduce the simulation with one command.
- Before rollout: capture baseline numbers, define rollback conditions, and
  arm the observation. After rollout: compare production with the
  simulation's prediction. A discrepancy is a model error; find it before
  trusting the next decision.

## Never

- Substitute numbers by eye.
- Compare strategies before calibration.
- Show the owner a recommendation without the table.
- Refine figures that cannot change the choice.
- Leave the cheap extension unrefuted.
- Invent a strategy that is not an exact rule over observable facts.

## Roles

The probe is a read-only production observer; the analysis in step 3 and the
review in step 7 go to the strongest available reviewer model, independent
from the author of the strategies. In Claude Code with the orch plugin these
are `orch:prod-probe` and `orch:reviewer`.
