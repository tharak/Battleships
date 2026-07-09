extends SceneTree
## Headless test that instantiates the real main.tscn and calls its actual methods
## directly (not a hand-reimplementation of the same logic) — the Q/E turn-direction
## bug from issue #4 slipped past every other test because it only showed up in the
## real scene's input-adjacent code. This is the same idea applied to _apply_formation
## (issue #6): exercise main.gd itself, not a copy of what it's supposed to do.
##
##   godot --headless --path game --script res://tests/test_main_scene.gd

var _failures := 0


func _init() -> void:
	print("test_main_scene — Godot ", Engine.get_version_info()["string"])
	_test_apply_formation_moves_the_real_scene()

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


func _test_apply_formation_moves_the_real_scene() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var main := scene.instantiate()
	get_root().add_child(main)  # triggers _ready(); call it again to be certain — it's
	main._ready()               # idempotent (fully resets _stream/_sim each time)
	main._sim.step(main._stream)  # apply the tick-0 spawn commands _ready() only *recorded*

	var blue_ids: Array[String] = []
	for id in main._sim.state.squadrons.keys():
		if main._sim.state.squadrons[id]["side"] == main.PLAYER_SIDE:
			blue_ids.append(id)
	_check(blue_ids.size() >= 3, "scene spawns at least 3 blue squadrons by default")

	var before := {}
	for id in blue_ids:
		before[id] = main._sim.state.squadrons[id]["pos"]

	main._selected = blue_ids
	main._apply_formation("spindle")

	# Run the sim forward (mirroring _process's tick loop). Deliberately don't break
	# as soon as everyone arrives: arrival sets desired_facing but turning toward it
	# only starts the *next* tick (test_formations.gd hit this same timing trap), so
	# just run the whole budget — cheap, and guarantees facing has settled too.
	for t in range(3000):
		main._sim.step(main._stream)

	var moved := false
	for id in blue_ids:
		if (main._sim.state.squadrons[id]["pos"] as Vector2).distance_to(before[id]) > 1.0:
			moved = true
	_check(moved, "_apply_formation issued real orders that moved the selected squadrons")

	var facings: Array[float] = []
	for id in blue_ids:
		facings.append(main._sim.state.squadrons[id]["facing"])
	var all_same_facing := true
	for fa in facings:
		if absf(Geometry.normalize_angle(fa - facings[0])) > 0.5:
			all_same_facing = false
	_check(all_same_facing, "spindle formation: every non-sphere slot ends up facing the same way")

	main.free()
