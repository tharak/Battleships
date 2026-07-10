extends SceneTree
## Headless behavior tests for regime actions: purge, broaden, expand/restrict
## franchise (issue #24, GDD §4.5, docs/prototypes/selectorate-game.md §7).
## Run:
##   godot --headless --path game --script res://tests/test_regime.gd
##
## Layered like the other strategic suites: pure Regime formula/guard tests
## first, then a sim-integration test that plays out the issue's own showable
## outcome -- "a campaign-long project taking a junta to a republic (or
## gutting one) is playable end to end" -- confirming this issue is what
## finally unlocks removal.gd's previously-dead-code election-clock branch
## (see removal.gd's own #23 docstring).

var _failures := 0


func _init() -> void:
	print("test_regime — Godot ", Engine.get_version_info()["string"])

	_test_purge_rejected_at_the_w_floor_leaves_state_untouched()
	_test_purge_rejected_during_an_active_instability_window()
	_test_purge_removes_the_least_satisfied_seat_with_a_stable_tie_break()
	_test_repeated_purges_durably_lower_effective_support_via_coup_insurance_debt()
	_test_loyalty_bonus_is_clamped_so_a_junta_cannot_become_immune_to_removal()

	_test_broaden_rejected_at_the_w_ceiling_leaves_state_untouched()
	_test_broaden_adds_a_seat_at_the_paper_defaults_and_dilutes_existing_seats()
	_test_broaden_seat_kind_follows_the_bloc_count_formula()

	_test_expand_franchise_raises_s_percent_and_relieves_unrest()
	_test_restrict_franchise_lowers_s_percent_and_shocks_unrest()
	_test_franchise_shift_clamps_at_bounds()
	_test_franchise_actions_rejected_during_an_active_instability_window()

	_test_instability_window_blocks_a_new_regime_action_and_expires_on_schedule()
	_test_growing_w_past_the_small_w_threshold_switches_to_the_election_clock()

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


## --- purge -------------------------------------------------------------------------------

func _test_purge_rejected_at_the_w_floor_leaves_state_untouched() -> void:
	var state := StrategicState.new()
	state.politics[0]["seats"] = {
		"a": {"name": "A", "kind": "individual", "satisfaction": 10.0, "weight": 1.0},
		"b": {"name": "B", "kind": "individual", "satisfaction": 60.0, "weight": 1.0},
		"c": {"name": "C", "kind": "bloc", "satisfaction": 60.0, "weight": 1.0},
	}  # W=3, at the floor -- purge must reject rather than dropping below it
	var materiel_before: float = state.materiel[0]
	var instability_before: float = state.politics[0]["instability_ticks_left"]

	_check(not Regime.purge(state, 0), "purge: rejected at W=3 (GDD's stated junta floor)")
	_check(state.politics[0]["seats"].size() == 3, "rejected purge: seat count unchanged")
	_check(is_equal_approx(state.politics[0]["seats"]["a"]["satisfaction"], 10.0), "rejected purge: no seat's satisfaction touched")
	_check(is_equal_approx(state.materiel[0], materiel_before), "rejected purge: no materiel granted")
	_check(is_equal_approx(state.politics[0]["instability_ticks_left"], instability_before), "rejected purge: no instability window opened")
	_check(is_equal_approx(state.politics[0]["coup_insurance_debt"], 0.0), "rejected purge: no coup insurance debt added")


func _test_purge_rejected_during_an_active_instability_window() -> void:
	var state := StrategicState.new()  # default W=6, comfortably above the floor
	state.politics[0]["instability_ticks_left"] = 3.0
	var w_before: int = state.politics[0]["seats"].size()

	_check(not Regime.purge(state, 0), "purge: rejected while an instability window is already active")
	_check(state.politics[0]["seats"].size() == w_before, "rejected purge: seat count unchanged")
	_check(is_equal_approx(state.politics[0]["instability_ticks_left"], 3.0), "rejected purge: the existing window's remaining time is untouched")


## Tie-break rule (stated explicitly in regime.gd's own docstring): first
## match in dictionary insertion order. "a" and "b" are tied for lowest at
## 10.0 -- "a" was inserted first, so "a" must be the one removed.
func _test_purge_removes_the_least_satisfied_seat_with_a_stable_tie_break() -> void:
	var state := StrategicState.new()
	state.politics[0]["seats"] = {
		"a": {"name": "A", "kind": "individual", "satisfaction": 10.0, "weight": 1.0},
		"b": {"name": "B", "kind": "individual", "satisfaction": 10.0, "weight": 1.0},
		"c": {"name": "C", "kind": "individual", "satisfaction": 50.0, "weight": 1.0},
		"d": {"name": "D", "kind": "bloc", "satisfaction": 50.0, "weight": 1.0},
	}  # W=4 -- purging drops to W=3, still allowed (rejected only BELOW the floor)
	var materiel_before: float = state.materiel[0]

	_check(Regime.purge(state, 0), "purge succeeds from W=4")
	var pol: Dictionary = state.politics[0]
	_check(pol["seats"].size() == 3, "purge: W drops by exactly one")
	_check(not pol["seats"].has("a"), "purge: the first-inserted tied-lowest seat ('a') is the one removed")
	_check(pol["seats"].has("b"), "purge: the tied seat that lost the tie-break ('b') survives")
	_check(is_equal_approx(state.materiel[0], materiel_before + Regime.PURGE_MATERIEL_GAIN), "purge: grants the materiel windfall")
	_check(is_equal_approx(pol["seats"]["b"]["satisfaction"], 10.0 - Regime.PURGE_PANIC), "purge: every remaining seat's satisfaction drops by the panic penalty")
	_check(is_equal_approx(pol["seats"]["c"]["satisfaction"], 50.0 - Regime.PURGE_PANIC), "purge: panic hits every remaining seat, not just the tied ones")
	_check(is_equal_approx(pol["coup_insurance_debt"], 1.0), "purge: increments coup_insurance_debt by one")
	_check(is_equal_approx(pol["instability_ticks_left"], Removal.INSTABILITY_WINDOW_TICKS), "purge: opens a fresh instability window")


## The direct regression for the paper prototype's own watch-item ("the full
## game must make coup insurance... cost more, or purge-down becomes the
## universal opener"): repeated purges leave a realm measurably LESS stable
## than an identical debt-free realm, even after every instability window
## from those purges has fully expired -- not just a temporary window cost.
func _test_repeated_purges_durably_lower_effective_support_via_coup_insurance_debt() -> void:
	var state := StrategicState.new()
	var seats := {}
	for i in range(8):
		seats["s%d" % i] = {"name": "S%d" % i, "kind": "individual", "satisfaction": 80.0, "weight": 1.0}
	state.politics[0]["seats"] = seats
	# Neutralize the loyalty bonus/penalty (replaceability == BASELINE_REPLACEABILITY
	# at every W along the way) so this test is only about coup_insurance_debt.
	state.politics[0]["s_percent"] = Removal.BASELINE_REPLACEABILITY * 8.0

	for i in range(3):
		_check(Regime.purge(state, 0), "purge #%d succeeds while W is still comfortably above the floor" % i)
		for t in range(int(Removal.INSTABILITY_WINDOW_TICKS)):
			Removal.advance(state, 0)

	_check(state.politics[0]["seats"].size() == 5, "test setup: three purges took W from 8 down to 5")
	_check(is_equal_approx(state.politics[0]["instability_ticks_left"], 0.0),
		"test setup: the instability window from the last purge has fully expired")
	_check(state.politics[0]["coup_insurance_debt"] > 0.0,
		"coup insurance: debt is still nonzero well after every instability window has cleared -- not just a temporary window cost")

	var control := StrategicState.new()
	control.politics[0]["seats"] = (state.politics[0]["seats"] as Dictionary).duplicate(true)
	control.politics[0]["s_percent"] = state.politics[0]["s_percent"]
	control.politics[0]["coup_insurance_debt"] = 0.0

	_check(Removal.effective_support(state, 0) < Removal.effective_support(control, 0),
		"coup insurance: a realm with purge debt reads measurably less stable than an identical debt-free realm, even after windows expire")


## Issue #24 design review's own flagged structural risk: without a clamp on
## loyalty_bonus, purging down to W=3 and expanding franchise to s_percent=100
## (both reachable within one campaign once this file exists) pins
## effective_support at 100 forever regardless of actual seat satisfaction.
func _test_loyalty_bonus_is_clamped_so_a_junta_cannot_become_immune_to_removal() -> void:
	var state := StrategicState.new()
	state.politics[0]["seats"] = {
		"a": {"name": "A", "kind": "individual", "satisfaction": 0.0, "weight": 1.0},
		"b": {"name": "B", "kind": "individual", "satisfaction": 0.0, "weight": 1.0},
		"c": {"name": "C", "kind": "bloc", "satisfaction": 0.0, "weight": 1.0},
	}  # W=3, zero raw satisfaction
	state.politics[0]["s_percent"] = 100.0  # replaceability = 100/3 = 33.3 -- an extreme, unclamped case would swing +150

	var support := Removal.effective_support(state, 0)
	_check(support < 99.0,
		"loyalty bonus clamp: a W=3/S=100 realm with zero raw satisfaction is NOT pinned near 100 by an unbounded loyalty bonus (got %.1f)" % support)
	_check(Removal.escalation_state(support) != "stable",
		"loyalty bonus clamp: this realm can still actually reach a real removal-risk classification despite the loyalty norm (got %s)" % Removal.escalation_state(support))


## --- broaden -----------------------------------------------------------------------------

func _test_broaden_rejected_at_the_w_ceiling_leaves_state_untouched() -> void:
	var state := StrategicState.new()
	var seats := {}
	for i in range(12):
		seats["s%d" % i] = {"name": "S%d" % i, "kind": "individual", "satisfaction": 60.0, "weight": 1.0}
	state.politics[0]["seats"] = seats
	var materiel_before: float = state.materiel[0]

	_check(not Regime.broaden(state, 0), "broaden: rejected at W=12 (GDD's stated republic ceiling)")
	_check(state.politics[0]["seats"].size() == 12, "rejected broaden: seat count unchanged")
	_check(is_equal_approx(state.materiel[0], materiel_before), "rejected broaden: no materiel touched")
	_check(is_equal_approx(state.politics[0]["instability_ticks_left"], 0.0), "rejected broaden: no instability window opened")


func _test_broaden_adds_a_seat_at_the_paper_defaults_and_dilutes_existing_seats() -> void:
	var state := StrategicState.new()
	var before: Dictionary = (state.politics[0]["seats"] as Dictionary).duplicate(true)  # the default 6-seat seed
	var w_before: int = before.size()

	_check(Regime.broaden(state, 0), "broaden succeeds from the default 6-seat seed")
	var pol: Dictionary = state.politics[0]
	_check(pol["seats"].size() == w_before + 1, "broaden: W grows by exactly one seat")

	var new_id := ""
	for id in pol["seats"].keys():
		if not before.has(id):
			new_id = id
	_check(new_id != "", "test setup: found the newly-added seat")
	var new_seat: Dictionary = pol["seats"][new_id]
	_check(is_equal_approx(new_seat["satisfaction"], Regime.BROADEN_NEW_SEAT_SATISFACTION), "broaden: new seat starts at the paper's own satisfaction (55)")
	_check(is_equal_approx(new_seat["weight"], Regime.BROADEN_SEAT_WEIGHT), "broaden: new seat gets the standard weight")

	for id in before.keys():
		var expected: float = before[id]["satisfaction"] - Regime.BROADEN_DILUTION_SHOCK
		_check(is_equal_approx(pol["seats"][id]["satisfaction"], expected),
			"broaden: existing seat %s's satisfaction drops by exactly the dilution shock" % id)


## GDD/paper's own formula: "Number of blocs = round(W*(W-3)/9)". Starting all-
## individual at W=3 (the formula's own anchor point), broadening to W=4 stays
## at 0 target blocs (still individual); broadening again to W=5 crosses to 1
## target bloc, so that seat must be a bloc.
func _test_broaden_seat_kind_follows_the_bloc_count_formula() -> void:
	var state := StrategicState.new()
	state.politics[0]["seats"] = {
		"a": {"name": "A", "kind": "individual", "satisfaction": 60.0, "weight": 1.0},
		"b": {"name": "B", "kind": "individual", "satisfaction": 60.0, "weight": 1.0},
		"c": {"name": "C", "kind": "individual", "satisfaction": 60.0, "weight": 1.0},
	}
	state.politics[0]["next_seat_id"] = 0

	_check(Regime.broaden(state, 0), "broaden #1 succeeds (W: 3 -> 4)")
	_check(state.politics[0]["seats"]["broadened_seat_0"]["kind"] == "individual",
		"broaden: W=3->4 still adds an individual seat (target bloc count stays at 0)")

	state.politics[0]["instability_ticks_left"] = 0.0  # clear the cooldown for this formula-only test
	_check(Regime.broaden(state, 0), "broaden #2 succeeds (W: 4 -> 5)")
	_check(state.politics[0]["seats"]["broadened_seat_1"]["kind"] == "bloc",
		"broaden: W=4->5 adds a BLOC seat once the target bloc count rises to 1")


## --- franchise ---------------------------------------------------------------------------

func _test_expand_franchise_raises_s_percent_and_relieves_unrest() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = 50.0
	var s_before: float = state.politics[0]["s_percent"]

	_check(Regime.expand_franchise(state, 0), "expand_franchise succeeds")
	_check(is_equal_approx(state.politics[0]["s_percent"], s_before + Regime.FRANCHISE_S_PERCENT_SHIFT), "expand franchise: s_percent rises by exactly the paper's shift")
	_check(is_equal_approx(state.planets["A1"]["unrest"], 50.0 - Regime.FRANCHISE_UNREST_RELIEF), "expand franchise: relieves unrest on every owned planet")


func _test_restrict_franchise_lowers_s_percent_and_shocks_unrest() -> void:
	var state := StrategicState.new()
	state.planets["A1"]["unrest"] = 50.0
	var s_before: float = state.politics[0]["s_percent"]

	_check(Regime.restrict_franchise(state, 0), "restrict_franchise succeeds")
	_check(is_equal_approx(state.politics[0]["s_percent"], s_before - Regime.FRANCHISE_S_PERCENT_SHIFT), "restrict franchise: s_percent falls by exactly the paper's shift")
	_check(is_equal_approx(state.planets["A1"]["unrest"], 50.0 + Regime.FRANCHISE_UNREST_SHOCK), "restrict franchise: shocks unrest on every owned planet")


func _test_franchise_shift_clamps_at_bounds() -> void:
	var state := StrategicState.new()
	state.politics[0]["s_percent"] = 95.0
	Regime.expand_franchise(state, 0)
	_check(state.politics[0]["s_percent"] <= 100.0, "expand franchise: s_percent never exceeds 100")

	state.politics[0]["instability_ticks_left"] = 0.0
	state.politics[0]["s_percent"] = 10.0
	Regime.restrict_franchise(state, 0)
	_check(state.politics[0]["s_percent"] >= 1.0, "restrict franchise: s_percent never drops below 1")


func _test_franchise_actions_rejected_during_an_active_instability_window() -> void:
	var state := StrategicState.new()
	state.politics[0]["instability_ticks_left"] = 2.0
	var s_before: float = state.politics[0]["s_percent"]

	_check(not Regime.expand_franchise(state, 0), "expand_franchise: rejected while an instability window is active")
	_check(not Regime.restrict_franchise(state, 0), "restrict_franchise: rejected while an instability window is active")
	_check(is_equal_approx(state.politics[0]["s_percent"], s_before), "rejected franchise actions: s_percent untouched")


## --- shared instability window ------------------------------------------------------------

func _test_instability_window_blocks_a_new_regime_action_and_expires_on_schedule() -> void:
	var state := StrategicState.new()  # default W=6
	_check(Regime.purge(state, 0), "purge #1 succeeds")
	var w_after_first: int = state.politics[0]["seats"].size()

	_check(not Regime.purge(state, 0), "a second purge is rejected while the instability window is still active")
	_check(state.politics[0]["seats"].size() == w_after_first, "rejected purge leaves W unchanged")

	for t in range(int(Removal.INSTABILITY_WINDOW_TICKS) - 1):
		Removal.advance(state, 0)
	_check(state.politics[0]["instability_ticks_left"] > 0.0, "instability window: still active just before it should expire")
	Removal.advance(state, 0)
	_check(is_equal_approx(state.politics[0]["instability_ticks_left"], 0.0), "instability window: fully expired on schedule")
	_check(Regime.purge(state, 0), "a purge succeeds again once the instability window has expired")


## --- sim-integration: the campaign-long "junta to republic" unlock -----------------------

## Issue #23 shipped with the large-W election-clock branch as genuine dead
## code (the #22 default seed's W=6 always lands on the small-W/continuous-
## coup-risk side of SMALL_W_THRESHOLD, and could never change). This is the
## concrete confirmation that #24 unlocks it for real, via actual regime
## actions -- not just a synthetic seat dict asserting the formula in
## isolation (test_removal.gd already covers that).
func _test_growing_w_past_the_small_w_threshold_switches_to_the_election_clock() -> void:
	var state := StrategicState.new()
	_check(state.politics[0]["seats"].size() == Removal.SMALL_W_THRESHOLD,
		"test setup: the default seed starts exactly at SMALL_W_THRESHOLD (the small-W side)")

	while state.politics[0]["seats"].size() <= Removal.SMALL_W_THRESHOLD:
		_check(Regime.broaden(state, 0), "broaden succeeds while growing the realm past the threshold")
		for t in range(int(Removal.INSTABILITY_WINDOW_TICKS)):
			Removal.advance(state, 0)
	_check(state.politics[0]["seats"].size() > Removal.SMALL_W_THRESHOLD, "test setup: W is now on the large-W side of the threshold")

	# Starve every seat to a genuine removal-level score, then confirm it does
	# NOT fire immediately (the small-W continuous-coup-risk behavior) -- only
	# the election clock governs removal now.
	for seat in state.politics[0]["seats"].values():
		seat["satisfaction"] = 0.0
	state.politics[0]["election_countdown"] = 10.0
	for t in range(5):
		Removal.advance(state, 0)
		_check(not state.politics[0]["removed_flag"],
			"large-W (post-#24 growth): critically low support does NOT remove the ruler outside a scheduled election")
	for t in range(5):
		Removal.advance(state, 0)
	_check(state.politics[0]["removed_flag"], "large-W (post-#24 growth): removal DOES fire once the scheduled election actually arrives")
	_check(state.politics[0]["removal_reason"] == "election",
		"the concrete unlock of #23's previously-dead-code election-clock branch, now reachable via real regime actions")
