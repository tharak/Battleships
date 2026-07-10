extends SceneTree
## Headless behavior tests for removal crises & the loyalty norm (issue #23,
## GDD §4.5/§7). Run:
##   godot --headless --path game --script res://tests/test_removal.gd
##
## Layered like the other strategic suites: pure Removal formula tests pin
## down the escalation ladder/loyalty math exactly, then Sim-integration
## tests play out the issue's own showable outcome -- "a player who stops
## paying their coalition gets a visible, escalating, survivable-if-
## addressed removal crisis" -- over real ticks.
##
## Two of this file's mechanisms are structurally unreachable via any live
## campaign until issue #24 ships regime actions (purge/broaden/franchise):
## the loyalty-norm bonus/penalty (s_percent/W never change without #24, so
## replaceability == BASELINE_REPLACEABILITY and the bonus is exactly 0 in
## any real game) and the election-clock branch (the #22 default seed's W=6
## always lands on the small-W/continuous-coup-risk side of SMALL_W_THRESHOLD).
## Both are covered here via hand-built synthetic seat dicts instead (same
## technique test_politics.gd's own 12-seat dilution test already uses), a
## design review's explicit recommendation, not a workaround.

var _failures := 0


func _init() -> void:
	print("test_removal — Godot ", Engine.get_version_info()["string"])

	_test_weighted_support_is_a_true_weighted_average()
	_test_loyalty_bonus_favors_high_replaceability_junta_shaped_realms()
	_test_loyalty_penalty_hits_low_replaceability_republic_shaped_realms()
	_test_escalation_state_thresholds_and_tie_breaks()
	_test_escalation_cannot_skip_a_stage_in_one_tick()

	_test_small_w_coup_fires_immediately_any_tick()
	_test_large_w_realm_only_judged_at_a_scheduled_election()
	_test_large_w_realm_survives_if_recovered_by_election_time()

	_test_removal_resets_satisfaction_symmetrically_for_any_side()
	_test_crisis_penalty_is_reversible_not_a_permanent_trap()

	if _failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("%d assertion(s) FAILED" % _failures)
		quit(1)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok: ", label)
	else:
		_failures += 1
		print("  FAIL: ", label)


## --- pure Removal formulas ---------------------------------------------------------------

func _test_weighted_support_is_a_true_weighted_average() -> void:
	var pol := {"seats": {
		"a": {"name": "A", "kind": "individual", "satisfaction": 100.0, "weight": 1.0},
		"b": {"name": "B", "kind": "individual", "satisfaction": 0.0, "weight": 3.0},
	}}
	# (100*1 + 0*3) / 4 == 25 -- NOT a simple mean (which would be 50).
	_check(is_equal_approx(Removal.weighted_support(pol), 25.0),
		"weighted_support: a true weighted average, not a simple mean of satisfaction")


func _test_loyalty_bonus_favors_high_replaceability_junta_shaped_realms() -> void:
	var state := StrategicState.new()
	# W=3 (junta-shaped), s_percent left at the default 20.0 -> replaceability
	# 20/3 = 6.67, well above BASELINE_REPLACEABILITY (20/6 = 3.33) -> a real
	# loyalty bonus. Same raw satisfaction as the baseline default (60 avg).
	state.politics[0]["seats"] = {
		"a": {"name": "A", "kind": "individual", "satisfaction": 60.0, "weight": 1.0},
		"b": {"name": "B", "kind": "individual", "satisfaction": 60.0, "weight": 1.0},
		"c": {"name": "C", "kind": "bloc", "satisfaction": 60.0, "weight": 1.0},
	}
	var raw := Removal.weighted_support(state.politics[0])
	var effective := Removal.effective_support(state, 0)
	_check(effective > raw,
		"loyalty bonus: a high-replaceability (junta-shaped) realm reads MORE stable than its raw satisfaction alone (got %.1f vs raw %.1f)" % [effective, raw])


func _test_loyalty_penalty_hits_low_replaceability_republic_shaped_realms() -> void:
	var state := StrategicState.new()
	# W=12 (republic-shaped), s_percent left at 20.0 -> replaceability
	# 20/12 = 1.67, well below the 3.33 baseline -> a real loyalty PENALTY.
	var seats := {}
	for i in range(12):
		seats["s%d" % i] = {"name": "S%d" % i, "kind": "individual", "satisfaction": 60.0, "weight": 1.0}
	state.politics[0]["seats"] = seats
	var raw := Removal.weighted_support(state.politics[0])
	var effective := Removal.effective_support(state, 0)
	_check(effective < raw,
		"loyalty penalty: a low-replaceability (republic-shaped) realm reads LESS stable than its raw satisfaction alone (got %.1f vs raw %.1f)" % [effective, raw])


func _test_escalation_state_thresholds_and_tie_breaks() -> void:
	_check(Removal.escalation_state(100.0) == "stable", "escalation_state: high support is stable")
	_check(Removal.escalation_state(40.01) == "stable", "escalation_state: just above the plot threshold is still stable")
	_check(Removal.escalation_state(40.0) == "plotting", "escalation_state: an exact tie at 40 resolves to the MORE severe stage (plotting), matching Rebellion's own tie convention")
	_check(Removal.escalation_state(25.0) == "crisis", "escalation_state: an exact tie at 25 resolves to crisis")
	_check(Removal.escalation_state(10.0) == "removal", "escalation_state: an exact tie at 10 resolves to removal")
	_check(Removal.escalation_state(0.0) == "removal", "escalation_state: zero support is removal")


## Same structural bound test_home_front_demo.gd's planet-escalation test
## uses, re-derived directly for THIS module's own numbers (not assumed by
## analogy): SATISFACTION_DRIFT_RATE bounds the largest possible single-tick
## move of the weighted-average support, well under the gap between any two
## adjacent thresholds -- a coalition can never skip a warning stage.
func _test_escalation_cannot_skip_a_stage_in_one_tick() -> void:
	var max_single_tick_move: float = 100.0 * Politics.SATISFACTION_DRIFT_RATE
	_check(max_single_tick_move < Removal.PLOT_THRESHOLD - Removal.CRISIS_THRESHOLD,
		"escalation: even the largest possible single-tick support drop can't skip past the plotting warning stage")
	_check(max_single_tick_move < Removal.CRISIS_THRESHOLD - Removal.REMOVAL_THRESHOLD,
		"escalation: even the largest possible single-tick support drop can't skip past the crisis warning stage")

	# Confirmed directly, not just via the bound: starve a realm's budget and
	# check every stage is actually visited in order on the way to removal.
	var state := StrategicState.new()
	state.politics[0]["budget_military"] = 0.9
	state.politics[0]["budget_private"] = 0.05
	state.politics[0]["budget_public"] = 0.05
	# Fully starved (not just heavily skewed) so the drift target is 0 for
	# every seat, well clear of REMOVAL_THRESHOLD rather than asymptotically
	# approaching it from just above without ever crossing.
	state.politics[0]["budget_private"] = 0.0
	state.politics[0]["budget_public"] = 0.0
	var seen: Array[String] = []
	for t in range(400):
		Politics.advance(state, 0, 8.0)
		# The escalation state read AFTER Removal.advance can differ from the
		# state its OWN firing decision used (that decision reads support
		# BEFORE this same tick's crisis penalty is subtracted, so an
		# external re-read afterward can look one step more severe than what
		# actually gated firing that tick) -- capture the removed_flag
		# TRANSITION directly instead of re-deriving the stage from
		# (already-reset, if it just fired) satisfaction.
		var was_removed: bool = state.politics[0]["removed_flag"]
		Removal.advance(state, 0)
		if state.politics[0]["removed_flag"] and not was_removed:
			if seen.is_empty() or seen[-1] != "removal":
				seen.append("removal")
			break
		var st := Removal.escalation_state(Removal.effective_support(state, 0))
		if seen.is_empty() or seen[-1] != st:
			seen.append(st)
	_check(seen == ["stable", "plotting", "crisis", "removal"],
		"escalation: a starved coalition actually passes through every warning stage in order (got %s)" % [seen])


## --- small-W continuous coup risk vs. large-W election clock ----------------------------

func _test_small_w_coup_fires_immediately_any_tick() -> void:
	var state := StrategicState.new()
	state.politics[0]["seats"] = {
		"a": {"name": "A", "kind": "individual", "satisfaction": 0.0, "weight": 1.0},
	}  # W=1, well under SMALL_W_THRESHOLD
	# s_percent left at BASELINE_REPLACEABILITY's own ratio for W=1 (matching
	# the default seed's proportions) so the loyalty bonus/penalty is ~0 and
	# doesn't mask the raw zero satisfaction this test is actually about.
	state.politics[0]["s_percent"] = Removal.BASELINE_REPLACEABILITY * 1.0
	Removal.advance(state, 0)
	_check(state.politics[0]["removed_flag"], "small-W: a coup fires on the very first tick support is critically low, no waiting for a schedule")
	_check(state.politics[0]["removal_reason"] == "coup", "small-W: the removal reason is 'coup'")


## Hand-built >6-seat realm (W=12) -- the #22 default seed can never reach
## this branch, so this is the only place it's exercised at all pre-#24.
func _test_large_w_realm_only_judged_at_a_scheduled_election() -> void:
	var state := StrategicState.new()
	var seats := {}
	for i in range(12):
		seats["s%d" % i] = {"name": "S%d" % i, "kind": "individual", "satisfaction": 0.0, "weight": 1.0}
	state.politics[0]["seats"] = seats
	state.politics[0]["election_countdown"] = 5.0  # a few ticks before the next election

	for t in range(4):
		Removal.advance(state, 0)
		_check(not state.politics[0]["removed_flag"],
			"large-W: critically low support does NOT remove the ruler outside a scheduled election (tick %d)" % t)
	Removal.advance(state, 0)  # the 5th call -- election_countdown hits 0
	_check(state.politics[0]["removed_flag"], "large-W: removal DOES fire once the scheduled election actually arrives")
	_check(state.politics[0]["removal_reason"] == "election", "large-W: the removal reason is 'election'")


func _test_large_w_realm_survives_if_recovered_by_election_time() -> void:
	var state := StrategicState.new()
	var seats := {}
	for i in range(12):
		seats["s%d" % i] = {"name": "S%d" % i, "kind": "individual", "satisfaction": 0.0, "weight": 1.0}
	state.politics[0]["seats"] = seats
	state.politics[0]["election_countdown"] = 3.0

	for t in range(2):
		Removal.advance(state, 0)  # countdown: 3 -> 2 -> 1, not yet due
	_check(not state.politics[0]["removed_flag"], "large-W: still not judged before the election arrives")

	# Support recovers before the NEXT election.
	for seat in state.politics[0]["seats"].values():
		seat["satisfaction"] = 100.0
	for t in range(52):
		Removal.advance(state, 0)
	_check(not state.politics[0]["removed_flag"],
		"large-W: a realm that recovered by election time survives, even though it was critically low earlier in the same term")


## --- removal consequences ----------------------------------------------------------------

func _test_removal_resets_satisfaction_symmetrically_for_any_side() -> void:
	for side in [0, 1, 2]:
		var state := StrategicState.new()
		for seat in state.politics[side]["seats"].values():
			seat["satisfaction"] = 0.0
		Removal._fire_removal(state, side, "coup")
		for seat in state.politics[side]["seats"].values():
			_check(seat["satisfaction"] == 60.0, "removal: side %d's seats reset to a fresh baseline, no special-casing by side" % side)
		_check(state.politics[side]["removed_flag"], "removal: removed_flag is set for side %d" % side)


## Budget picked (and empirically verified via a probe) to settle in a real,
## self-sustaining "crisis" WITHOUT spiraling into "removal" -- the crisis
## penalty's own equilibrium math means a target too close to REMOVAL_THRESHOLD
## drifts straight through it once the penalty engages (target - PENALTY/
## DRIFT_RATE), so this needs real margin, not just "somewhat harsh."
func _test_crisis_penalty_is_reversible_not_a_permanent_trap() -> void:
	var state := StrategicState.new()
	state.politics[0]["budget_military"] = 0.78
	state.politics[0]["budget_private"] = 0.11
	state.politics[0]["budget_public"] = 0.11
	for t in range(60):
		Politics.advance(state, 0, 8.0)
		Removal.advance(state, 0)
	_check(not state.politics[0]["removed_flag"], "test setup: has NOT yet been removed (still recoverable)")
	var crisis_support := Removal.effective_support(state, 0)
	_check(Removal.escalation_state(crisis_support) != "stable", "test setup: genuinely in a real crisis/plotting state")

	# Fix the budget -- survivable if addressed.
	state.politics[0]["budget_military"] = 0.2
	state.politics[0]["budget_private"] = 0.4
	state.politics[0]["budget_public"] = 0.4
	for t in range(200):
		Politics.advance(state, 0, 8.0)
		Removal.advance(state, 0)
	_check(not state.politics[0]["removed_flag"], "crisis reversible: fixing the budget in time avoids removal entirely")
	_check(Removal.escalation_state(Removal.effective_support(state, 0)) == "stable",
		"crisis reversible: support actually recovers back to stable, not stuck")
