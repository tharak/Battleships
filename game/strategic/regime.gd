extends RefCounted
class_name Regime
## Regime actions: purge, broaden, expand/restrict franchise (issue #24, GDD
## §4.5's "steering the regime" table). This is the issue that finally lets W
## (seats.size(), strategic/politics.gd) and S (s_percent) actually change
## over a campaign — #22/#23 both shipped with both frozen at the default
## seed, and removal.gd's own docstring documents the loyalty-norm bonus and
## the large-W election-clock branch as PROVABLY INERT until this file ships.
##
## Ports the Phase-0 paper prototype's already-validated design
## (docs/prototypes/selectorate-game.md §7 — built and played by hand across
## 16 human games plus 1000-campaign sim sweeps) rather than re-deriving it:
## action -> immediate effect -> cost -> a shared instability window. Pure-
## function module, same shape as Planet/Rebellion/Politics/Removal/Manpower,
## except each action here returns bool (false if rejected by a guard) — a
## new convention, appropriate because these guards are about the ACTION's
## own precondition (W bounds, cooldown), not command-shape validation (which
## still lives entirely in strategic_sim.gd's _apply(), same as every other
## command kind). On rejection, NO state is mutated at all — every guard is
## checked and returned on before a single field is touched.
##
## Scope line: emergency powers and "constitutional reform" (GDD's other two
## regime-adjacent actions) are deliberately CUT from this issue. Emergency
## powers has zero paper-prototype validation (only these four actions were
## ever playtested) and its GDD description ("council delay on major acts")
## would require editing Politics.advance's own already-shipped target
## formula from outside — a real violation of this codebase's "poke after
## the fact, never rewrite an earlier module's own formula" convention every
## other cross-module effect here (and Rebellion/Manpower before it) follows.
## Constitutional reform has no election-clock/threshold-mutation UI yet for
## it to attach to. Both logged here as a deliberate scope boundary for a
## follow-up issue, not silently dropped — same practice as politics.gd's own
## morale/crew-quality deferral.
##
## The paper prototype's own most important finding, and the one requirement
## this file treats as non-negotiable: "shrinking W looks strong (cheaper
## politics, only instability windows as the price). The full game must make
## coup insurance... cost more, or purge-down becomes the universal opener."
## purge()'s `coup_insurance_debt` (consumed by Removal.effective_support,
## see removal.gd) is the direct, mechanical answer to that watch-item — a
## real, durable (slowly-decaying, not instantly-vanishing) cost that
## compounds with purge frequency, not a one-time flavor penalty.
##
## Probed live (scratchpad/probe_regime.gd), not just via synthetic unit
## tests: purging a well-managed realm (default budget split) all the way
## down to W=3 DOES carry real, measurable risk for the ~60-90 ticks the debt
## takes to decay away, and an actively mismanaged (starved-budget) small
## realm still visibly weakens over time despite the loyalty norm's clamped
## bonus. But a well-fed W=3 junta that survives that window settles into
## near-total long-term stability (support -> 100, "stable" indefinitely) --
## this is NOT a residual bug: it's Politics.advance's own already-shipped
## "small coalitions are cheap to satisfy" formula (issue #22) plus GDD's own
## loyalty-norm philosophy, both working exactly as designed. The paper
## prototype's watch-item is answered for the transient risk of EXECUTING a
## purge-down strategy; a permanent structural cost for the excluded seats'
## former "clients" (GDD mentions this) would need an actual seat-to-planet
## ownership mapping that doesn't exist in this codebase yet -- logged as a
## deliberate scope boundary, same as the client-grievance omission on purge()
## itself above, not silently discovered and ignored.

const PURGE_MIN_W := 3          # GDD's stated junta floor -- purge rejected at or below this
const BROADEN_MAX_W := 12       # GDD's stated republic ceiling -- broaden rejected at or above this
const PURGE_MATERIEL_GAIN := 25.0   # "seize their assets" (GDD) -- scaled from the paper's simpler
                                     # "+2 treasury" into this game's actual materiel units (roughly
                                     # half a Shipyard.MATERIEL_PER_STRENGTH-costed rebuild's worth)
const PURGE_PANIC := 5.0            # every REMAINING seat's satisfaction hit (paper's own number)
const BROADEN_NEW_SEAT_SATISFACTION := 55.0   # paper's own number
const BROADEN_SEAT_WEIGHT := 2.0    # matches the middle of Politics.default_state()'s existing 2.0-3.0 range
const BROADEN_DILUTION_SHOCK := 5.0 # every EXISTING seat's satisfaction hit (paper's own number),
                                     # on top of Politics.advance's own already-automatic
                                     # private_per_seat dilution from the new, larger W denominator
const FRANCHISE_S_PERCENT_SHIFT := 15.0   # paper's own number, "the sharpest knife on the table"
const FRANCHISE_UNREST_RELIEF := 5.0      # expand: "-5, inclusion" (paper)
const FRANCHISE_UNREST_SHOCK := 10.0      # restrict: "+10, permanent resentment" (paper) -- a one-time
                                            # additive push, same honest approximation this codebase
                                            # already uses for Rebellion.SCORCHED_UNREST_FLOOR rather
                                            # than inventing a literal eternal-modifier planet field


## GDD/paper's own bloc-count rule: "Number of blocs = round(W * (W-3) / 9) --
## W=3 is all individuals, W=12 all blocs, the middle is mixed." Used by
## broaden() to decide whether the newly-added seat should be the kind that
## closes the gap between the CURRENT bloc count and the TARGET bloc count at
## the new, larger W -- automatic, matching the paper's own validated design
## (which never let the player choose kind either).
static func _target_bloc_count(w: int) -> int:
	return int(round(float(w) * float(w - 3) / 9.0))


## Issue #29: a pretender crisis blocks new regime actions the same way an
## active instability window already does -- you can't calmly reshuffle
## your regime while someone is actively contesting your legitimacy. A
## shared helper (not four independent inline checks) so the two windows
## can never drift out of sync the way Removal's own threshold_bump almost
## did (see removal.gd's current_threshold_bump docstring for that exact
## lesson, applied here too).
static func _blocked_by_crisis(pol: Dictionary) -> bool:
	return pol.get("instability_ticks_left", 0.0) > 0.0 or pol.get("pretender_ticks_left", 0.0) > 0.0


## Purge (GDD §4.5, paper §7): removes the realm's least-satisfied seat,
## loots its assets, and panics everyone left. Tie-break for "least
## satisfied": first match in dictionary insertion order (stated explicitly,
## matching this codebase's existing paranoia about non-obvious iteration-
## order bugs -- strategic_sim.gd's _advance_fleets two-pass capture-race
## handling is the precedent for writing this down rather than leaving it
## implicit).
static func purge(state: StrategicState, side: int) -> bool:
	var pol: Dictionary = state.politics[side]
	if pol["seats"].size() <= PURGE_MIN_W or _blocked_by_crisis(pol):
		return false
	var victim_id := ""
	var victim_satisfaction := INF
	for id in pol["seats"].keys():
		var satisfaction: float = pol["seats"][id]["satisfaction"]
		if satisfaction < victim_satisfaction:
			victim_satisfaction = satisfaction
			victim_id = id
	pol["seats"].erase(victim_id)
	state.materiel[side] = state.materiel.get(side, 0.0) + PURGE_MATERIEL_GAIN
	for seat in pol["seats"].values():
		seat["satisfaction"] = maxf(0.0, seat["satisfaction"] - PURGE_PANIC)
	# Issue #25: a roster character (strategic/roster.gd) may be narratively
	# seated in the seat just erased -- clear that dangling link so the
	# roster never claims to hold a seat that no longer exists (which would
	# corrupt assign_command's own seated/unseated snub-poke logic).
	for character in state.roster[side].values():
		if character["seat_id"] == victim_id:
			character["seat_id"] = null
	# The direct, mechanical answer to the paper prototype's "coup insurance"
	# watch-item -- see this file's own docstring. Consumed (and slowly
	# decayed) by Removal.effective_support/advance, not here.
	pol["coup_insurance_debt"] = pol.get("coup_insurance_debt", 0.0) + 1.0
	pol["instability_ticks_left"] = Removal.INSTABILITY_WINDOW_TICKS
	return true


## Broaden (GDD §4.5, paper §7): adds a seat (kind auto-picked via the
## bloc-count formula above), dilutes every existing seat's satisfaction --
## both via the explicit one-time shock below AND, from the very next tick
## onward, Politics.advance's own private_per_seat denominator growing for
## free (no code change needed for that half).
static func broaden(state: StrategicState, side: int) -> bool:
	var pol: Dictionary = state.politics[side]
	var w: int = pol["seats"].size()
	if w >= BROADEN_MAX_W or _blocked_by_crisis(pol):
		return false
	var current_blocs := 0
	for seat in pol["seats"].values():
		if seat["kind"] == "bloc":
			current_blocs += 1
	var kind := "bloc" if _target_bloc_count(w + 1) > current_blocs else "individual"
	for seat in pol["seats"].values():
		seat["satisfaction"] = maxf(0.0, seat["satisfaction"] - BROADEN_DILUTION_SHOCK)
	var next_id: int = pol.get("next_seat_id", 0)
	pol["next_seat_id"] = next_id + 1
	pol["seats"]["broadened_seat_%d" % next_id] = {
		"name": "New Seat %d" % next_id, "kind": kind,
		"satisfaction": BROADEN_NEW_SEAT_SATISFACTION, "weight": BROADEN_SEAT_WEIGHT,
	}
	pol["instability_ticks_left"] = Removal.INSTABILITY_WINDOW_TICKS
	return true


## Expand/restrict franchise (GDD §4.5, paper §7): moves s_percent, and pokes
## every owned planet's unrest once -- same "poke after the fact from
## outside, don't rewrite an earlier module's own formula" precedent
## Rebellion/Manpower/Politics's own _apply_public_goods_to_planets already
## established for planet unrest.
static func expand_franchise(state: StrategicState, side: int) -> bool:
	var pol: Dictionary = state.politics[side]
	if _blocked_by_crisis(pol):
		return false
	pol["s_percent"] = clampf(pol["s_percent"] + FRANCHISE_S_PERCENT_SHIFT, 1.0, 100.0)
	_apply_unrest_shock(state, side, -FRANCHISE_UNREST_RELIEF)
	pol["instability_ticks_left"] = Removal.INSTABILITY_WINDOW_TICKS
	return true


static func restrict_franchise(state: StrategicState, side: int) -> bool:
	var pol: Dictionary = state.politics[side]
	if _blocked_by_crisis(pol):
		return false
	pol["s_percent"] = clampf(pol["s_percent"] - FRANCHISE_S_PERCENT_SHIFT, 1.0, 100.0)
	_apply_unrest_shock(state, side, FRANCHISE_UNREST_SHOCK)
	pol["instability_ticks_left"] = Removal.INSTABILITY_WINDOW_TICKS
	return true


static func _apply_unrest_shock(state: StrategicState, side: int, delta: float) -> void:
	for id in state.system_owner.keys():
		if state.system_owner[id] == side:
			var p: Dictionary = state.planets[id]
			p["unrest"] = clampf(p["unrest"] + delta, 0.0, 100.0)
