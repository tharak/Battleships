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
##
## Issue #24 update: strategic/regime.gd is what actually moves W/S now (via
## purge/broaden/expand_franchise/restrict_franchise), so the two mechanisms
## above are live from here on. That issue's own design review caught a real
## structural risk this file needed to fix regardless of regime.gd's own
## tuning: `loyalty_bonus` below was UNCLAMPED, and #24 is precisely what
## makes its blowup reachable (purge down to W=3 + expand franchise to
## s_percent=100 -- ~9 actions, comfortably inside a campaign -- pins
## `effective_support` at 100 forever, regardless of actual seat
## satisfaction). Now clamped. `coup_insurance_debt` (regime.gd's purge()) and
## `instability_ticks_left` (every regime action) are consumed here too --
## see effective_support/escalation_state/advance below.

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
## Issue #24 design review: without a clamp, purge-to-W=3 + franchise-to-100
## (both reachable within one campaign once regime.gd exists) pins the raw
## bonus at +150, permanently pinning effective_support at 100 regardless of
## actual seat satisfaction. 25.0 is roughly two threshold-bands wide (e.g.
## PLOT_THRESHOLD - CRISIS_THRESHOLD == 15.0) -- enough for the loyalty norm
## to still meaningfully move a realm's classification, not enough to make it
## immune to one entirely on its own.
const LOYALTY_BONUS_CLAMP := 25.0

## Issue #24 (regime.gd's purge()): the direct fix for the paper prototype's
## own "coup insurance" watch-item -- see regime.gd's docstring. Chosen
## relative to LOYALTY_BONUS_PER_POINT (5.0) so one purge's ongoing cost is
## comparable to, not swamped by or dominant over, a single point of
## replaceability swing. Decays rather than staying permanent -- a truly
## permanent counter would make one early-campaign purge an irreversible
## support ceiling for the rest of a 100+ tick campaign, cutting against
## "steering is a campaign-long project" (GDD §4.5) far more than the
## watch-item asked for; ~20 ticks to fully clear one purge's debt if no
## further purge occurs is long enough to matter, short enough not to trap.
const COUP_INSURANCE_PENALTY := 4.0
const COUP_INSURANCE_DECAY := 0.05

## Issue #24 (regime.gd): every regime action opens this shared window --
## while active, no NEW regime action can be issued (a real cooldown, reusing
## this same timer rather than a second counter) and a crisis is EASIER to
## trigger, by this many points, on all three thresholds below (matches the
## paper prototype's own "+10pp survival threshold" cost -- GDD's prose calls
## the same effect "lowering crisis thresholds", opposite framing of the
## identical mechanic: the numeric threshold CONSTANTS below get RAISED so
## the comparison is easier to satisfy, they are not lowered).
const INSTABILITY_WINDOW_TICKS := 8.0
const INSTABILITY_THRESHOLD_BUMP := 10.0

## Issue #29 (era_events.gd's pretender event): a SECOND, independent
## threshold-bump source, same shape as INSTABILITY_THRESHOLD_BUMP above --
## while a pretender crisis is active, a removal is EASIER to trigger, same
## "an imperial pretender surfaces with a legitimist claim" framing GDD's
## own Act 2 pacing skeleton uses for this event, pulled forward into the
## early campaign window per issue #29's own showable outcome.
const PRETENDER_THRESHOLD_BUMP := 15.0

## Issue #30 design-review-caught bugfix: INSTABILITY_THRESHOLD_BUMP (10.0)
## and PRETENDER_THRESHOLD_BUMP (15.0) can BOTH be active at once (nothing
## gates a pretender crisis on an active instability window), summing to
## 25.0 -- which EXCEEDS both gaps between adjacent thresholds (PLOT_
## THRESHOLD-CRISIS_THRESHOLD = 15, CRISIS_THRESHOLD-REMOVAL_THRESHOLD = 15).
## A realm at support=41 ("stable" at bump 0) would read as "crisis" the
## instant both sources are active, skipping "plotting" entirely in one
## tick -- a real violation of GDD's own "no gotchas, two ticks before it
## bites" design rule that #24/#29 shipped without catching. Fixed with the
## same clamp precedent LOYALTY_BONUS_CLAMP already established elsewhere
## in this file: the combined bump can never exceed one threshold-gap's
## width, so escalation_state can never skip more than one stage per tick
## no matter how many bump sources exist, current or future.
const THRESHOLD_BUMP_CLAMP := 15.0


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
	var loyalty_bonus := clampf((replaceability - BASELINE_REPLACEABILITY) * LOYALTY_BONUS_PER_POINT,
		-LOYALTY_BONUS_CLAMP, LOYALTY_BONUS_CLAMP)
	var coup_insurance_penalty: float = pol.get("coup_insurance_debt", 0.0) * COUP_INSURANCE_PENALTY
	# Issue #25: "a brilliant, unsatisfied, ambitious admiral is the classic
	# coup seed" (GDD §6) -- Roster.ambition_threat_penalty is provably 0.0
	# for the default roster (every character starts at ambition=0.0), so
	# this is a true no-op until a real campaign actually grows one via a
	# won battle (strategic/roster.gd).
	var ambition_penalty := Roster.ambition_threat_penalty(state, side)
	return clampf(weighted_support(pol) + loyalty_bonus - coup_insurance_penalty - ambition_penalty, 0.0, 100.0)


## "stable" / "plotting" / "crisis" / "removal" -- pure threshold mapping, not
## stored state (derived on demand, same as Rebellion's own escalation_state).
## Ties resolve to the MORE severe stage (<=, not <) -- matches Rebellion.
## escalation_state's own tie convention (unrest==90.0 exactly is already
## "rebellion"). `threshold_bump` (issue #24): added to all three comparisons,
## so a caller mid-instability-window and advance()'s own internal firing
## decision can never disagree -- see strategic_map.gd's _coalition_text,
## which MUST pass the same bump advance() computes below or the player-
## facing status line can silently disagree with what the sim just decided.
## Issue #29 design review: the ONLY place this sum may ever be computed.
## Before this existed, `strategic_map.gd`'s `_coalition_text()` and
## `realm_politics_ai.gd`'s `act()` each independently re-derived
## INSTABILITY_THRESHOLD_BUMP's own contribution by hand -- the exact bug
## class #24's own design review already caught once (a caller silently
## disagreeing with advance()'s actual firing decision). Adding a SECOND
## bump source (pretender_ticks_left) without a single shared helper would
## have reintroduced that same bug the moment a pretender crisis is active
## without an instability window also being active (a realistic,
## independent combination) -- every caller that needs "how much easier is
## a removal right now" must call THIS function, never re-derive it.
static func current_threshold_bump(pol: Dictionary) -> float:
	var bump := 0.0
	if pol.get("instability_ticks_left", 0.0) > 0.0:
		bump += INSTABILITY_THRESHOLD_BUMP
	if pol.get("pretender_ticks_left", 0.0) > 0.0:
		bump += PRETENDER_THRESHOLD_BUMP
	return minf(bump, THRESHOLD_BUMP_CLAMP)


static func escalation_state(support: float, threshold_bump: float = 0.0) -> String:
	if support <= REMOVAL_THRESHOLD + threshold_bump:
		return "removal"
	elif support <= CRISIS_THRESHOLD + threshold_bump:
		return "crisis"
	elif support <= PLOT_THRESHOLD + threshold_bump:
		return "plotting"
	else:
		return "stable"


## One tick's worth of removal-crisis escalation for one realm. Called from
## strategic_sim.gd's _advance_removal(), right after _advance_economy (so
## this reads that same tick's freshly-drifted Politics.advance output).
## Returns an event list (issue #30, same "-> Array" shape Rebellion.advance
## already established) -- a `{"type": "removal_stage_changed", ...}` event
## on any stable/plotting/crisis/removal transition, consumed by strategic_
## map.gd's ticker (ticker.gd). This file stays pure/side-agnostic either
## way -- it only reports what changed, same "interpreting removed_flag...
## is strategic_map.gd's job, not this file's" precedent already established
## for the removal flag itself.
static func advance(state: StrategicState, side: int) -> Array:
	var events := []
	var pol: Dictionary = state.politics[side]
	var w: int = pol["seats"].size()
	var support := effective_support(state, side)
	var threshold_bump := current_threshold_bump(pol)
	var st := escalation_state(support, threshold_bump)

	var last_stage: String = pol.get("last_removal_stage", "stable")
	if st != last_stage:
		events.append({"type": "removal_stage_changed", "side": side, "from": last_stage, "to": st})
		pol["last_removal_stage"] = st

	if st == "crisis" or st == "removal":
		for seat in pol["seats"].values():
			seat["satisfaction"] = maxf(0.0, seat["satisfaction"] - CRISIS_SATISFACTION_PENALTY)

	# Issue #24/#29: decay every regime.gd/era_events.gd-owned counter once
	# per tick, in this same fixed-side-list loop (strategic_sim.gd's
	# _advance_removal already iterates state.politics.keys(), the
	# #16/#22/#23-taught-safe pattern -- no new iteration risk from adding
	# these here).
	if pol.get("instability_ticks_left", 0.0) > 0.0:
		pol["instability_ticks_left"] = maxf(0.0, pol["instability_ticks_left"] - 1.0)
	if pol.get("pretender_ticks_left", 0.0) > 0.0:
		pol["pretender_ticks_left"] = maxf(0.0, pol["pretender_ticks_left"] - 1.0)
	if pol.get("coup_insurance_debt", 0.0) > 0.0:
		pol["coup_insurance_debt"] = maxf(0.0, pol["coup_insurance_debt"] - COUP_INSURANCE_DECAY)

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
	return events


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
