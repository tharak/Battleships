extends RefCounted
class_name Removal
## Removal crises & the loyalty norm (issue #23, GDD §4.5's "staying in
## power"/"the loyalty norm" sections, and §7's primary loss condition: "You
## lose when you fall — not when the state does"). Builds on issue #22's
## seats/satisfaction (strategic/politics.gd) exactly the way rebellion.gd
## builds on planet.gd: watches a continuous score cross fixed thresholds and
## fires discrete, escalating consequences, ending in the ruler's removal
## from power — "a player who stops paying their coalition gets a visible,
## escalating, survivable-if-addressed removal crisis" (the issue's own
## showable outcome).
##
## Resolves two GDD open questions: **OQ6** (hard game over vs. an exile/
## comeback mode) — hard game over, adopting the GDD draft's own stated
## default; no successor/continuation system exists in this codebase to make
## a comeback mode meaningful anyway. **OQ7** (are large-W elections an
## explicit scheduled clock, or continuous checks?) — BOTH, split by regime
## size, read directly from GDD's own differentiated rule-of-thumb table
## (small-W: "Coup risk... the main threat"; large-W: "Removal comes at the
## ballot box instead"), not an arbitrary single choice: small-W realms use
## continuous coup risk (fires the instant support crosses the floor, any
## tick); large-W realms use an explicit election clock (only judged at a
## scheduled interval).
##
## Scope line: regime actions that actually CHANGE W or S (purge/broaden/
## franchise) are #24 — this file only builds the CONSUMER of replaceability
## (S÷W), not the levers that move it. Until #24 ships, every realm's
## `s_percent` (20.0) and W (6, #22's default seed) are identical and never
## change, so the loyalty-norm bonus/penalty below is PROVABLY zero for every
## realm, every tick, in any live campaign — and since the default seed's W=6
## always lands on the small-W side of SMALL_W_THRESHOLD, the election-clock
## branch is genuine DEAD CODE until #24 can produce a >6-seat realm. Both
## mechanisms are real and correctly implemented, covered by dedicated
## synthetic-seat unit tests (mirroring test_politics.gd's own 12-seat
## dilution test technique) — a live probe cannot exercise either one
## pre-#24, and that's stated here plainly rather than implied otherwise.

const SMALL_W_THRESHOLD := 6         # W <= this: continuous coup risk. Above it: the election clock.
                                       # The #22 default seed (W=6, a genuine 50/50 individual/bloc
                                       # hybrid) lands on the small-W side -- a narrative coin-flip,
                                       # not a claim that W=6 is definitively "small."
const ELECTION_PERIOD_TICKS := 52.0  # 1 year (GDD §2: 1 tick = 1 week)

const PLOT_THRESHOLD := 40.0
const CRISIS_THRESHOLD := 25.0
const REMOVAL_THRESHOLD := 10.0
## Extra per-tick satisfaction drain on every seat while in "crisis" or worse --
## self-reinforcing, mirrors Rebellion's riot-contagion shape. Gated on/off by
## the SAME threshold used to classify the stage, using each tick's PRE-penalty
## value, so it can never trap a realm below CRISIS_THRESHOLD permanently --
## the instant a fixed budget's drift target pulls support back over the
## threshold, the penalty deactivates and recovery is unimpeded (confirmed via
## a design review's equilibrium math, not assumed).
const CRISIS_SATISFACTION_PENALTY := 1.0

## Matches Politics.default_state()'s own s_percent/W (20.0/6), so a fresh
## realm's effective support == its raw weighted support (no bonus/penalty at
## the baseline) -- same "defaults reproduce identical behavior" precedent
## used throughout this codebase's tuning.
const BASELINE_REPLACEABILITY := 20.0 / 6.0
const LOYALTY_BONUS_PER_POINT := 5.0


## GDD's own continuous-score philosophy (same as Planet's unrest): a
## weighted AVERAGE of seat satisfaction, not a binary per-seat "satisfied"
## cutoff -- smooth and legible, no discontinuous cliff-edges when a single
## seat crosses some internal threshold.
static func weighted_support(pol: Dictionary) -> float:
	var total_weight := 0.0
	var weighted_sum := 0.0
	for seat in pol["seats"].values():
		total_weight += seat["weight"]
		weighted_sum += seat["weight"] * seat["satisfaction"]
	return weighted_sum / total_weight if total_weight > 0.0 else 0.0


## GDD's loyalty norm, read via its OWN worked example, not a naive literal
## reading of "willingness scales with replaceability": "a large selectorate
## with a tiny coalition... makes every essential terrified of losing their
## seat -- MAXIMUM LOYALTY" and "a small selectorate with a large coalition...
## makes essentials BOLD." High S/W -> high loyalty -> LOW plot willingness;
## low S/W -> LOW loyalty -> HIGH plot willingness -- replaceability and
## defection-willingness are INVERSELY related. Folded in as a bonus/penalty
## on the EFFECTIVE support score fed to escalation_state, not the raw
## weighted_support number -- Politics.gd's own satisfaction math stays
## untouched, same "poke after the fact" precedent Rebellion/Manpower already
## established for planet unrest.
static func effective_support(state: StrategicState, side: int) -> float:
	var pol: Dictionary = state.politics[side]
	var w: int = pol["seats"].size()
	var replaceability: float = pol["s_percent"] / maxf(1.0, float(w))
	var loyalty_bonus := (replaceability - BASELINE_REPLACEABILITY) * LOYALTY_BONUS_PER_POINT
	return clampf(weighted_support(pol) + loyalty_bonus, 0.0, 100.0)


## "stable" / "plotting" / "crisis" / "removal" -- pure threshold mapping, not
## stored state (derived on demand, same as Rebellion's own escalation_state).
## Ties resolve to the MORE severe stage (<=, not <) -- matches Rebellion.
## escalation_state's own tie convention (unrest==90.0 exactly is already
## "rebellion").
static func escalation_state(support: float) -> String:
	if support <= REMOVAL_THRESHOLD:
		return "removal"
	elif support <= CRISIS_THRESHOLD:
		return "crisis"
	elif support <= PLOT_THRESHOLD:
		return "plotting"
	else:
		return "stable"


## One tick's worth of removal-crisis escalation for one realm. Called from
## strategic_sim.gd's _advance_removal(), right after _advance_economy (so
## this reads that same tick's freshly-drifted Politics.advance output).
static func advance(state: StrategicState, side: int) -> void:
	var pol: Dictionary = state.politics[side]
	var w: int = pol["seats"].size()
	var support := effective_support(state, side)
	var st := escalation_state(support)

	if st == "crisis" or st == "removal":
		for seat in pol["seats"].values():
			seat["satisfaction"] = maxf(0.0, seat["satisfaction"] - CRISIS_SATISFACTION_PENALTY)

	if w <= SMALL_W_THRESHOLD:
		# Continuous coup risk: fires the instant support crosses the floor, any tick.
		if st == "removal":
			_fire_removal(state, side, "coup")
	else:
		# Explicit election clock: only judged at a scheduled interval -- a
		# mid-cycle dip that recovers before the next election never fires.
		pol["election_countdown"] = pol.get("election_countdown", ELECTION_PERIOD_TICKS) - 1.0
		if pol["election_countdown"] <= 0.0:
			pol["election_countdown"] = ELECTION_PERIOD_TICKS
			if st == "removal":
				_fire_removal(state, side, "election")


## Symmetric for EVERY side (player and AI alike) -- deliberately does NOT
## special-case "side 0 is the player" (every existing strategic/*.gd module
## is side-agnostic; confirmed by grep before writing this, not assumed --
## this file isn't the first exception). A removal is a political transition,
## not a military one (GDD: "your state may outlive you") -- the realm's
## fleets/territory/W/S are untouched, only satisfaction resets to a fresh
## baseline. Interpreting removed_flag as an actual GAME OVER is
## strategic_map.gd's job (it already does the same "check a state flag,
## decide what it means for the player" pattern for fleet-elimination), not
## this file's.
static func _fire_removal(state: StrategicState, side: int, reason: String) -> void:
	var pol: Dictionary = state.politics[side]
	pol["removed_flag"] = true
	pol["removal_reason"] = reason
	for seat in pol["seats"].values():
		seat["satisfaction"] = 60.0
