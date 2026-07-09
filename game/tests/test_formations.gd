extends SceneTree
## Headless tests for formation shape generation (issue #6, GDD §5.4). Run:
##   godot --headless --path game --script res://tests/test_formations.gd
##
## Pure shape-generator tests (no Sim needed — see sim/formations.gd's docstring for
## why formations don't need any new simulation mechanic) plus one integration test
## confirming a formation order actually lands squadrons on their slots via the
## existing order_move/order_face machinery.

const TOL := 0.01

var _failures := 0


func _init() -> void:
	print("test_formations — Godot ", Engine.get_version_info()["string"])

	for name in Formations.NAMES:
		for n in [1, 2, 5, 9, 12]:
			_test_shape_sane(name, n)
	_test_spindle_is_a_wedge()
	_test_echelon_staggers()
	_test_sphere_faces_outward()
	_test_line_is_flat_and_centered()
	_test_formation_order_lands_squadrons()

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


## Properties every formation, at every size, must have: right slot count, a valid
## flag index, and no two squadrons assigned the exact same point (an overlap would
## mean two squadrons trying to occupy one spot).
func _test_shape_sane(name: String, n: int) -> void:
	var f := Formations.generate(name, n)
	var slots: Array = f["slots"]
	_check(slots.size() == n, "%s@%d: generates exactly %d slots" % [name, n, n])
	_check(f["flag"] >= 0 and f["flag"] < n, "%s@%d: flag index is in range" % [name, n])
	var seen: Array[Vector2] = []
	var dup := false
	for s in slots:
		var p := Vector2(s["fwd"], s["lat"])
		for q in seen:
			if p.distance_to(q) < 0.001:
				dup = true
		seen.append(p)
	_check(not dup, "%s@%d: no two slots land on the same point" % [name, n])


func _test_spindle_is_a_wedge() -> void:
	var f := Formations.generate("spindle", 9)
	var slots: Array = f["slots"]
	var max_fwd := -INF
	for s in slots:
		max_fwd = maxf(max_fwd, s["fwd"])
	var tip_count := 0
	for s in slots:
		if s["fwd"] >= max_fwd - TOL:
			tip_count += 1
	_check(tip_count == 1, "spindle: exactly one squadron holds the forwardmost tip")


func _test_echelon_staggers() -> void:
	var f := Formations.generate("echelon", 9)
	var slots: Array = f["slots"]
	# Every slot should differ in both fwd and lat from its neighbors — that's the
	# "staggered diagonal" (a pure line formation would have fwd constant at 0).
	var all_same_fwd := true
	var first_fwd: float = slots[0]["fwd"]
	for s in slots:
		if absf(s["fwd"] - first_fwd) > TOL:
			all_same_fwd = false
	_check(not all_same_fwd, "echelon: fwd varies across the line (it's diagonal, not flat)")


func _test_sphere_faces_outward() -> void:
	var f := Formations.generate("sphere", 9)
	var slots: Array = f["slots"]
	_check(slots[0]["fwd"] == 0.0 and slots[0]["lat"] == 0.0,
		"sphere: the first slot is the protected center")
	_check(slots[0]["face_offset"] == null,
		"sphere: the center slot has no forced facing")
	var all_ring_have_offset := true
	for i in range(1, slots.size()):
		if slots[i]["face_offset"] == null:
			all_ring_have_offset = false
	_check(all_ring_have_offset, "sphere: every ring slot specifies an outward face_offset")
	# The ring unit's face_offset should point AWAY from center, i.e. same direction
	# as its own (fwd, lat) offset from the center.
	var s: Dictionary = slots[1]
	var pos_angle := rad_to_deg(atan2(s["lat"], s["fwd"]))
	_check(absf(Geometry.normalize_angle(s["face_offset"] - pos_angle)) <= TOL,
		"sphere: a ring slot's face_offset matches its own radial direction")


func _test_line_is_flat_and_centered() -> void:
	var f := Formations.generate("line", 9)
	var slots: Array = f["slots"]
	for s in slots:
		_check(s["fwd"] == 0.0, "line: every slot has fwd=0 (a single flat rank)")
	var sum_lat := 0.0
	for s in slots:
		sum_lat += s["lat"]
	_check(absf(sum_lat) <= TOL, "line: slots are laterally centered on 0")


## Integration: applying a formation is just order_move(+face) per squadron — this
## confirms that pipeline actually converges squadrons onto their assigned slots.
func _test_formation_order_lands_squadrons() -> void:
	var stream := CommandStream.new()
	var ids := ["A", "B", "C"]
	for i in range(ids.size()):
		stream.record(Commands.make(0, "spawn", {
			"id": ids[i], "side": 0, "pos": [i * 30.0, 0.0], "facing": 0.0,
			"strength": 4, "flag": i == 0,
		}))
	var f := Formations.generate("line", 3)
	var slots: Array = f["slots"]
	var anchor := Vector2(200, 200)
	var formation_facing := 90.0  # face "south" once assembled
	for i in range(ids.size()):
		var s: Dictionary = slots[i]
		var world := anchor + Vector2(s["fwd"], s["lat"]).rotated(deg_to_rad(formation_facing))
		stream.record(Commands.make(1, "order_move", {
			"id": ids[i], "target": Commands.pos_to_array(world), "face": formation_facing,
		}))
	var sim := Sim.new(1)
	for t in range(2000):
		sim.step(stream)
		var settled := true
		for id in ids:
			var sq: Dictionary = sim.state.squadrons[id]
			if sq["target"] != null or absf(Geometry.normalize_angle(sq["facing"] - formation_facing)) > TOL:
				settled = false
		if settled:
			break
	for id in ids:
		_check(sim.state.squadrons[id]["target"] == null,
			"formation order: %s arrives (target cleared)" % id)
		_check(absf(sim.state.squadrons[id]["facing"] - formation_facing) <= TOL,
			"formation order: %s ends up facing the formation's forward direction" % id)
