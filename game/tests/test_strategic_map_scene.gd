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
