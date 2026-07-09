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
