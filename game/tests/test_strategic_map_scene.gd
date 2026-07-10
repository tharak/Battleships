extends SceneTree
## Headless test that instantiates the real strategic_map.tscn and calls its
## actual methods directly (not a hand-reimplementation of the same logic) —
## same idea as tests/test_main_scene.gd for the battle layer. Specifically
## targets issue #16's contact-routing fix: strategic_map.gd used to assume
## every contact was exactly (side 0, side 1); with a 3rd realm, a side-1-vs-
## side-2 contact would have been mis-assigned by that old logic.
##
##   godot --headless --path game --script res://tests/test_strategic_map_scene.gd

var _failures := 0


func _init() -> void:
	print("test_strategic_map_scene — Godot ", Engine.get_version_info()["string"])
	_test_involves_player_covers_all_three_side_pairs()
	_test_auto_resolve_contact_leaves_no_scene_pending()
	_test_check_campaign_over_detects_elimination()
	_test_inspect_click_selects_and_deselects_an_owned_system()
	_test_inspect_click_ignores_a_system_outside_intel_range()
	_test_policy_keys_are_ignored_on_a_system_the_player_does_not_own()
	_test_policy_cycle_and_garrison_step_emit_real_commands()
	_test_rapid_policy_cycles_before_a_tick_still_advance_each_time()
	_test_draw_does_not_crash_on_a_rebel_owned_system()
	_test_planet_panel_shows_escalation_state_and_siege_progress()
	_test_home_front_warning_surfaces_the_worst_owned_system_unprompted()
	_test_home_front_warning_ignores_calm_and_other_realms_systems()
	_test_policy_change_takes_effect_immediately_while_paused()
	_test_fleet_order_takes_effect_immediately_while_paused()
	_test_shift_budget_moves_the_targeted_share_up_and_others_down()
	_test_rapid_budget_shifts_before_a_tick_still_compound()
	_test_coalition_panel_shows_seats_and_budget_split()
	_test_check_campaign_over_detects_a_political_removal()
	_test_same_tick_removal_is_not_masked_by_a_pending_contact()
	_test_regime_action_key_takes_effect_immediately_while_paused()
	_test_coalition_panel_status_matches_removal_advance_during_instability_window()

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


func _fresh_map() -> Node:
	StrategicSession.sim = null
	var scene: PackedScene = load("res://strategic_map.tscn")
	var map := scene.instantiate()
	get_root().add_child(map)
	map._ready()
	return map


## The actual bug this issue's contact-routing fix targets: a contact between
## the two AI realms (never involving the player) must be recognized as such,
## not silently mis-assigned the way the pre-#16 (side 0, side 1)-only logic
## would have.
func _test_involves_player_covers_all_three_side_pairs() -> void:
	var map := _fresh_map()
	map._sim.state.fleets["X"] = {"side": 0, "system": "B1"}
	map._sim.state.fleets["Y"] = {"side": 1, "system": "B1"}
	map._sim.state.fleets["Z"] = {"side": 2, "system": "B1"}

	_check(map._involves_player(["X", "Y"]), "involves_player: side 0 vs side 1 involves the player")
	_check(map._involves_player(["X", "Z"]), "involves_player: side 0 vs side 2 involves the player")
	_check(not map._involves_player(["Y", "Z"]), "involves_player: side 1 vs side 2 does NOT involve the player")
	map.free()


## An AI-vs-AI contact resolves in place: both fleets get a real outcome
## (survivor strength written back, or removed if wiped) and no scene
## transition happens (SkirmishConfig.from_map_contact stays false, since
## seed_skirmish/main.tscn are never touched for this path).
func _test_auto_resolve_contact_leaves_no_scene_pending() -> void:
	var map := _fresh_map()
	map._sim.state.fleets["Y"] = {"side": 1, "system": "B1", "strength": 150, "supply": 100.0, "preset": "line"}
	map._sim.state.fleets["Z"] = {"side": 2, "system": "B1", "strength": 20, "supply": 100.0, "preset": "line"}
	SkirmishConfig.from_map_contact = false
	map._auto_resolve_contact(["Y", "Z"])
	_check(not SkirmishConfig.from_map_contact,
		"auto_resolve_contact: never touches SkirmishConfig -- no scene transition for an AI-vs-AI fight")
	_check(map._sim.state.fleets.has("Y") and map._sim.state.fleets["Y"]["strength"] > 0,
		"auto_resolve_contact: the stronger side survives with a real, written-back strength value")
	_check(not map._sim.state.fleets.has("Z") or map._sim.state.fleets["Z"]["strength"] < 20,
		"auto_resolve_contact: the weaker side takes a real, written-back loss")
	map.free()


func _test_check_campaign_over_detects_elimination() -> void:
	var map := _fresh_map()
	map._sim.state.fleets.clear()
	map._sim.state.fleets["Home"] = {"side": 0, "system": "A1"}
	# No other side has a living fleet -- the player is the last realm standing.
	map._check_campaign_over()
	_check(map._campaign_over, "check_campaign_over: ends the campaign once only one realm has a fleet left")
	_check(map._campaign_result.begins_with("VICTORY"),
		"check_campaign_over: the player being the sole survivor is a victory")
	map.free()


func _test_check_campaign_over_detects_a_political_removal() -> void:
	var map := _fresh_map()
	map._sim.state.politics[map.PLAYER_SIDE]["removed_flag"] = true
	map._sim.state.politics[map.PLAYER_SIDE]["removal_reason"] = "election"
	map._check_campaign_over()
	_check(map._campaign_over, "check_campaign_over: a political removal ends the campaign too, not just fleet elimination")
	_check(map._campaign_result.begins_with("DEFEAT") and map._campaign_result.contains("election"),
		"check_campaign_over: the message reflects the actual removal reason")
	map.free()


## Regression for a design review's finding: a same-tick removal must not be
## masked by an unrelated tactical battle launching first. Without the fix,
## _process()'s contact-detection/_launch_battle path returns BEFORE
## _check_campaign_over() is ever reached this frame (a real scene-change
## attempt via get_tree().change_scene_to_file, which this headless test
## would rather never trigger at all) -- the fix checks removed_flag
## immediately after _sim.step(), ahead of contact detection.
func _test_same_tick_removal_is_not_masked_by_a_pending_contact() -> void:
	var map := _fresh_map()
	map._process(0.0)  # materialize _ready()'s initial spawn_fleet commands
	var player_fleet := ""
	for id in map._sim.state.fleets.keys():
		if map._sim.state.fleets[id]["side"] == map.PLAYER_SIDE:
			player_fleet = id
	# Move an enemy fleet onto the player's fleet's system -- a genuine
	# contact BattleBridge.detect_contact will find and _launch_battle would
	# otherwise act on before _check_campaign_over ever runs.
	for id in map._sim.state.fleets.keys():
		if map._sim.state.fleets[id]["side"] != map.PLAYER_SIDE:
			map._sim.state.fleets[id]["system"] = map._sim.state.fleets[player_fleet]["system"]
			map._sim.state.fleets[id]["dest"] = null
	_check(not BattleBridge.detect_contact(map._sim.state).is_empty(), "test setup: a real contact exists this tick")

	map._sim.state.politics[map.PLAYER_SIDE]["removed_flag"] = true
	map._process(0.6)  # forces at least one _sim.step() to run this frame
	_check(map._campaign_over, "same-tick removal: the campaign ends even though a contact was also pending this same tick")
	map.free()


## Issue #17's planet panel: right-click select/deselect on a system the player
## owns (A1, native and starting territory for side 0).
func _test_inspect_click_selects_and_deselects_an_owned_system() -> void:
	var map := _fresh_map()
	map._handle_system_inspect_click(Galaxy.SYSTEMS["A1"]["pos"])
	_check(map._selected_system == "A1", "inspect click: selects the clicked system")
	map._handle_system_inspect_click(Galaxy.SYSTEMS["A1"]["pos"])
	_check(map._selected_system == "", "inspect click: clicking the same system again deselects it")
	map.free()


## C1 (Sector C's hub) is outside side 0's default intel range -- own systems
## plus one lane beyond never reaches across two full sectors (Intel.visible_systems).
func _test_inspect_click_ignores_a_system_outside_intel_range() -> void:
	var map := _fresh_map()
	_check(not Intel.visible_systems(map._sim.state, map.PLAYER_SIDE).has("C1"),
		"test setup: C1 really is outside the player's starting intel range")
	map._handle_system_inspect_click(Galaxy.SYSTEMS["C1"]["pos"])
	_check(map._selected_system == "", "inspect click: a system outside intel range can't be selected at all")
	map.free()


## B2 is visible by default (one lane beyond A2, the A-B chokepoint spoke) but
## native/owned by side 1 -- inspectable (read-only) but not editable.
func _test_policy_keys_are_ignored_on_a_system_the_player_does_not_own() -> void:
	var map := _fresh_map()
	map._handle_system_inspect_click(Galaxy.SYSTEMS["B2"]["pos"])
	_check(map._selected_system == "B2", "test setup: B2 selected for inspection")
	_check(not map._can_edit_selected_system(), "ownership gate: a foreign system can't be edited")
	var before: String = map._sim.state.planets["B2"]["taxation"]
	map._cycle_policy("taxation", Planet.TAXATION_LEVELS)
	map._step_garrison(5.0)
	_check(map._sim.state.planets["B2"]["taxation"] == before,
		"policy keys: cycling taxation on a system you don't own is a no-op")
	_check(map._sim.state.planets["B2"]["garrison"] == 0.0,
		"policy keys: stepping garrison on a system you don't own is a no-op")
	map.free()


## The full path: a key handler records a set_policy command (never pokes state
## directly, per this scene's own "no direct UI-to-sim pokes" discipline) -- it
## only takes effect once the sim actually steps and applies it.
func _test_policy_cycle_and_garrison_step_emit_real_commands() -> void:
	var map := _fresh_map()
	map._handle_system_inspect_click(Galaxy.SYSTEMS["A1"]["pos"])
	_check(map._can_edit_selected_system(), "test setup: A1 is owned by the player and selected")
	var before: String = map._sim.state.planets["A1"]["taxation"]
	map._cycle_policy("taxation", Planet.TAXATION_LEVELS)
	map._step_garrison(5.0)
	_check(map._sim.state.planets["A1"]["taxation"] == before,
		"set_policy: recording a command doesn't mutate state directly, only the stream")
	map._sim.step(map._stream)
	_check(map._sim.state.planets["A1"]["taxation"] != before,
		"set_policy: the recorded taxation change actually applies once the sim steps")
	_check(map._sim.state.planets["A1"]["garrison"] == 5.0,
		"set_policy: the recorded garrison step actually applies once the sim steps")
	map.free()


## Two T presses in a row (e.g. while paused, before the sim has applied the
## first one yet) must advance the level twice, not emit the same "next" value
## twice because both reads saw the same stale current state.
func _test_rapid_policy_cycles_before_a_tick_still_advance_each_time() -> void:
	var map := _fresh_map()
	map._handle_system_inspect_click(Galaxy.SYSTEMS["A1"]["pos"])
	_check(map._sim.state.planets["A1"]["taxation"] == "moderate", "test setup: starts at moderate")
	map._cycle_policy("taxation", Planet.TAXATION_LEVELS)  # moderate -> heavy
	map._cycle_policy("taxation", Planet.TAXATION_LEVELS)  # heavy -> punitive (must NOT re-request heavy)
	map._sim.step(map._stream)
	_check(map._sim.state.planets["A1"]["taxation"] == "punitive",
		"rapid cycle: two presses before any tick still land two levels up, not one")
	map.free()


## Issue #18: SIDE_COLOR must have an entry for Rebellion.REBEL_SIDE, or
## _draw()'s SIDE_COLOR[owner] lookup would crash the instant any system
## rebels (checked directly rather than by calling _draw() itself, which
## Godot's CanvasItem only permits inside a real NOTIFICATION_DRAW pass --
## calling it manually in a headless test logs "Drawing is only allowed..."
## engine errors for every draw call even when nothing is actually wrong).
func _test_draw_does_not_crash_on_a_rebel_owned_system() -> void:
	_check(map_side_color_has_key(Rebellion.REBEL_SIDE),
		"SIDE_COLOR: has an entry for REBEL_SIDE, so _draw()'s lookup won't crash once a system rebels")


func map_side_color_has_key(key: int) -> bool:
	var scene: PackedScene = load("res://strategic_map.tscn")
	var map := scene.instantiate()
	var has_key: bool = (map.SIDE_COLOR as Dictionary).has(key)
	map.free()
	return has_key


func _test_planet_panel_shows_escalation_state_and_siege_progress() -> void:
	var map := _fresh_map()
	map._sim.state.planets["A1"]["unrest"] = 80.0  # riots
	map._handle_system_inspect_click(Galaxy.SYSTEMS["A1"]["pos"])
	var text: String = map._planet_panel_text()
	_check(text.contains("RIOTS"), "planet panel: shows the escalation state, not just a raw unrest number")

	map._sim.state.system_owner["A2"] = Rebellion.REBEL_SIDE
	map._sim.state.planets["A2"]["siege_progress"] = 7.0
	map._sim.state.planets["A2"]["siege_side"] = 0
	map._handle_system_inspect_click(Galaxy.SYSTEMS["A1"]["pos"])  # deselect A1 first
	map._handle_system_inspect_click(Galaxy.SYSTEMS["A2"]["pos"])
	var rebel_text: String = map._planet_panel_text()
	_check(rebel_text.contains("REBELLION"), "planet panel: a rebel-held system reads as such")
	_check(rebel_text.contains("7") and rebel_text.contains(str(int(Rebellion.SIEGE_TICKS))),
		"planet panel: shows the current siege progress against its target")
	map.free()


## Issue #21's showable outcome ("a build where the loudest threat is behind
## your lines") needs this to be visible WITHOUT the player having selected
## anything -- unlike the planet panel, which only shows once you've already
## right-clicked the exact system in trouble.
func _test_home_front_warning_surfaces_the_worst_owned_system_unprompted() -> void:
	var map := _fresh_map()
	_check(map._selected_system == "", "test setup: nothing is selected")
	map._sim.state.planets["A2"]["unrest"] = 65.0  # strikes
	map._sim.state.planets["A3"]["unrest"] = 80.0  # riots -- the worse one
	var text: String = map._home_front_warning_text()
	_check(text.contains("A3") and text.contains("RIOTS"),
		"home front warning: surfaces whichever owned system is worst, unprompted")
	_check(not text.contains("A2"), "home front warning: only shows the single worst system, not every troubled one")
	map.free()


func _test_home_front_warning_ignores_calm_and_other_realms_systems() -> void:
	var map := _fresh_map()
	_check(map._home_front_warning_text() == "", "home front warning: silent when every owned system is calm")
	map._sim.state.planets["B1"]["unrest"] = 95.0  # a rival realm's own system, not the player's
	_check(map._home_front_warning_text() == "", "home front warning: never surfaces another realm's troubles as your own")
	map.free()


## The actual bug report: pressing T/C/[/]/O (or clicking to move a fleet)
## while paused used to sit inertly in the command stream -- step() is what
## applies commands, and _process() only called it while NOT paused. Exercises
## the real scene's _process(), not a reimplementation.
func _test_policy_change_takes_effect_immediately_while_paused() -> void:
	var map := _fresh_map()
	map._paused = true
	map._handle_system_inspect_click(Galaxy.SYSTEMS["A1"]["pos"])
	_check(map._sim.state.planets["A1"]["taxation"] == "moderate", "test setup: starts at moderate")
	var tick_before: int = map._sim.state.tick

	map._cycle_policy("taxation", Planet.TAXATION_LEVELS)
	map._process(0.016)  # one frame, still paused

	_check(map._sim.state.planets["A1"]["taxation"] == "heavy",
		"paused: a policy change takes effect on the very next frame, not after unpausing")
	_check(map._sim.state.tick == tick_before, "paused: simulated time genuinely did not advance")
	map.free()


func _test_fleet_order_takes_effect_immediately_while_paused() -> void:
	var map := _fresh_map()
	map._paused = true
	map._process(0.0)  # apply_due_commands() materializes _ready()'s initial spawn_fleet commands
	var blue_id := ""
	for id in map._sim.state.fleets.keys():
		if map._sim.state.fleets[id]["side"] == map.PLAYER_SIDE:
			blue_id = id
			break
	_check(blue_id != "", "test setup: the player has a fleet")
	map._selected_fleet = blue_id
	_check(map._sim.state.fleets[blue_id]["dest"] == null, "test setup: the fleet starts with no destination")
	var tick_before: int = map._sim.state.tick

	map._handle_click(Galaxy.SYSTEMS["A2"]["pos"])
	map._process(0.016)  # one frame, still paused

	_check(map._sim.state.fleets[blue_id]["dest"] != null,
		"paused: a fleet move order takes effect on the very next frame, not after unpausing")
	_check(map._sim.state.tick == tick_before, "paused: simulated time genuinely did not advance")
	map.free()


func _test_shift_budget_moves_the_targeted_share_up_and_others_down() -> void:
	var map := _fresh_map()
	var before: Dictionary = map._sim.state.politics[map.PLAYER_SIDE].duplicate(true)
	map._shift_budget("budget_private")
	map._process(0.0)
	var pol: Dictionary = map._sim.state.politics[map.PLAYER_SIDE]
	_check(pol["budget_private"] > before["budget_private"],
		"shift_budget: the targeted share increases")
	_check(pol["budget_military"] < before["budget_military"] and pol["budget_public"] < before["budget_public"],
		"shift_budget: the other two shares decrease proportionally")
	var total: float = pol["budget_military"] + pol["budget_private"] + pol["budget_public"]
	_check(is_equal_approx(total, 1.0), "shift_budget: the split always still sums to 1.0")


func _test_rapid_budget_shifts_before_a_tick_still_compound() -> void:
	var map := _fresh_map()
	map._shift_budget("budget_private")
	map._shift_budget("budget_private")  # must build on the pending value, not the stale committed one
	map._process(0.0)
	var pol: Dictionary = map._sim.state.politics[map.PLAYER_SIDE]
	_check(pol["budget_private"] > Politics.default_state()["budget_private"] + Politics.BUDGET_STEP * 1.5,
		"rapid budget shifts: two presses before a tick compound, not both landing the same single step")


func _test_coalition_panel_shows_seats_and_budget_split() -> void:
	var map := _fresh_map()
	var text: String = map._coalition_text()
	_check(text.contains("Fleet Commander"), "coalition panel: lists the player's own seats")
	_check(text.contains("individual") and text.contains("bloc"), "coalition panel: shows each seat's kind")
	_check(text.contains("military") and text.contains("private") and text.contains("public"),
		"coalition panel: shows the current budget split")


## Issue #24: same "takes effect immediately while paused" precedent as
## policy/fleet-order/budget commands above -- _emit_regime_action goes
## through apply_due_commands() every frame regardless of pause state.
func _test_regime_action_key_takes_effect_immediately_while_paused() -> void:
	var map := _fresh_map()
	map._paused = true
	var w_before: int = map._sim.state.politics[map.PLAYER_SIDE]["seats"].size()

	map._emit_regime_action("broaden")
	map._process(0.016)

	_check(map._sim.state.politics[map.PLAYER_SIDE]["seats"].size() == w_before + 1,
		"paused: a regime action (broaden) takes effect on the very next frame, not after unpausing")
	map.free()


## Issue #24 design review's own flagged risk: _coalition_text()'s status
## line MUST pass the same instability-window threshold_bump Removal.advance
## uses internally, or the panel can read "stable" the same tick the sim is
## actually treating the realm as "crisis". Built so it genuinely only
## crosses into "crisis" once the bump is applied (32.0 sits strictly between
## CRISIS_THRESHOLD=25 and PLOT_THRESHOLD=40 unbumped, but at/under
## CRISIS_THRESHOLD+10=35 once bumped) -- a real regression test for the gap,
## not just re-asserting the formula.
func _test_coalition_panel_status_matches_removal_advance_during_instability_window() -> void:
	var map := _fresh_map()
	var pol: Dictionary = map._sim.state.politics[map.PLAYER_SIDE]
	for seat in pol["seats"].values():
		seat["satisfaction"] = 32.0
	pol["instability_ticks_left"] = 5.0

	var bumped_status := Removal.escalation_state(
		Removal.effective_support(map._sim.state, map.PLAYER_SIDE), Removal.INSTABILITY_THRESHOLD_BUMP)
	_check(bumped_status == "crisis",
		"test setup: this scenario only crosses into crisis once the instability bump is applied")

	var text: String = map._coalition_text()
	_check(text.contains("CRISIS"),
		"coalition panel: status line reflects the SAME instability-bumped threshold Removal.advance itself uses")
	map.free()
