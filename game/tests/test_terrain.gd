extends SceneTree
## Headless behavior tests for asteroid field terrain (issue #9, GDD §5.7). Run:
##   godot --headless --path game --script res://tests/test_terrain.gd
##
## Layered like test_combat.gd: pure Terrain function tests pin down the geometry
## exactly, then Sim-level tests check the showable outcome the issue asks for --
## "an ambush from an asteroid field that works": a squadron hidden inside a field
## can hit an enemy that can't see or hit it back, until something gets close enough
## to spot it.

var _failures := 0


func _init() -> void:
	print("test_terrain — Godot ", Engine.get_version_info()["string"])

	_test_in_field()
	_test_speed_mult()
	_test_blocks_line()
	_test_concealment()
	_test_spawn_terrain_command()
	_test_movement_slowed_inside_field()
	_test_ambush_no_return_fire()
	_test_ambush_breaks_when_spotted()
	_test_field_between_blocks_both_sides()

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


func _spawn(stream: CommandStream, id: String, side: int, pos: Vector2, facing: float, strength := 10) -> void:
	stream.record(Commands.make(0, "spawn", {
		"id": id, "side": side, "pos": Commands.pos_to_array(pos), "facing": facing,
		"strength": strength, "flag": false,
	}))


func _spawn_field(stream: CommandStream, id: String, pos: Vector2, radius: float) -> void:
	stream.record(Commands.make(0, "spawn_terrain", {
		"id": id, "kind": "asteroid_field", "pos": Commands.pos_to_array(pos), "radius": radius,
	}))


## --- pure Terrain functions ---------------------------------------------------------

func _test_in_field() -> void:
	var terrain := {"F1": {"kind": "asteroid_field", "pos": Vector2(100, 100), "radius": 40.0}}
	_check(Terrain.in_field(Vector2(110, 100), terrain), "in_field: a point well inside the radius counts")
	_check(Terrain.in_field(Vector2(140, 100), terrain), "in_field: exactly on the radius counts (inclusive)")
	_check(not Terrain.in_field(Vector2(200, 100), terrain), "in_field: a point outside every field is clear space")


func _test_speed_mult() -> void:
	var terrain := {"F1": {"kind": "asteroid_field", "pos": Vector2(100, 100), "radius": 40.0}}
	_check(Terrain.speed_mult(Vector2(100, 100), terrain) == Terrain.ASTEROID_SPEED_MULT,
		"speed_mult: inside a field applies the slow multiplier")
	_check(Terrain.speed_mult(Vector2(500, 500), terrain) == 1.0,
		"speed_mult: clear space is full speed")


func _test_blocks_line() -> void:
	var terrain := {"F1": {"kind": "asteroid_field", "pos": Vector2(100, 100), "radius": 40.0}}
	_check(Terrain.blocks_line(Vector2(0, 100), Vector2(200, 100), terrain),
		"blocks_line: a shot straight through the field's center is blocked")
	_check(not Terrain.blocks_line(Vector2(0, 0), Vector2(200, 0), terrain),
		"blocks_line: a shot well clear of the field (100 units away vs. radius 40) is not blocked")
	_check(not Terrain.blocks_line(Vector2(100, 100), Vector2(300, 100), terrain),
		"blocks_line: a shot fired FROM inside the field is NOT blocked by that same field " +
		"(an ambusher must be able to fire out of its own hiding spot)")


func _test_concealment() -> void:
	var terrain := {"F1": {"kind": "asteroid_field", "pos": Vector2(100, 100), "radius": 40.0}}
	var hidden_pos := Vector2(100, 100)
	_check(Terrain.is_concealed_from(hidden_pos, Vector2(100, 100 + Terrain.ASTEROID_DETECT_RADIUS + 50), terrain),
		"concealment: a squadron in a field is hidden from a distant observer")
	_check(not Terrain.is_concealed_from(hidden_pos, Vector2(100, 100 + 10), terrain),
		"concealment: the same squadron is spotted by an observer within detection range")
	var open_pos := Vector2(1000, 1000)
	_check(not Terrain.is_concealed_from(open_pos, Vector2(5000, 5000), terrain),
		"concealment: open space is never concealed, however far the observer is")


## --- Sim integration -----------------------------------------------------------------

func _test_spawn_terrain_command() -> void:
	var stream := CommandStream.new()
	_spawn_field(stream, "F1", Vector2(300, 400), 55.0)
	var sim := Sim.new(1)
	sim.step(stream)
	_check(sim.state.terrain.has("F1"), "spawn_terrain: field lands in state.terrain")
	var f: Dictionary = sim.state.terrain["F1"]
	_check(f["kind"] == "asteroid_field" and f["pos"] == Vector2(300, 400) and f["radius"] == 55.0,
		"spawn_terrain: kind/pos/radius all round-trip correctly")


func _test_movement_slowed_inside_field() -> void:
	var stream := CommandStream.new()
	_spawn_field(stream, "F1", Vector2(0, 0), 300.0)  # big field, A starts and stays inside it
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0)         # inside the field the whole trip
	_spawn(stream, "B", 0, Vector2(1000, 0), 0.0)      # in clear space, same-length trip
	stream.record(Commands.make(0, "order_move", {"id": "A", "target": [60, 0]}))
	stream.record(Commands.make(0, "order_move", {"id": "B", "target": [1060, 0]}))
	var sim := Sim.new(1)
	var a_arrival := -1
	var b_arrival := -1
	for t in range(300):
		sim.step(stream)
		if a_arrival == -1 and sim.state.squadrons["A"]["target"] == null:
			a_arrival = t
		if b_arrival == -1 and sim.state.squadrons["B"]["target"] == null:
			b_arrival = t
		if a_arrival != -1 and b_arrival != -1:
			break
	_check(a_arrival != -1 and b_arrival != -1, "movement: both squadrons eventually arrive")
	_check(a_arrival > b_arrival,
		"movement: the same trip takes longer inside an asteroid field (got %d vs %d ticks)" % [a_arrival, b_arrival])


## The issue's showable outcome: a squadron hidden inside an asteroid field can hit
## an enemy that neither sees it coming nor can fire back — distance is chosen
## between Terrain.ASTEROID_DETECT_RADIUS and Combat.RANGE, so the enemy is a legal
## target for the ambusher (not concealed itself) while the ambusher is concealed
## from the enemy's point of view.
func _test_ambush_no_return_fire() -> void:
	var stream := CommandStream.new()
	_spawn_field(stream, "F1", Vector2(0, 0), 40.0)
	_spawn(stream, "Ambusher", 0, Vector2(0, 0), 0.0)     # inside the field
	_spawn(stream, "Target", 1, Vector2(150, 0), 180.0)   # faces the ambusher, in range+arc both ways
	var sim := Sim.new(1)
	for t in range(100):  # a partial hit, not a kill -- this test is about return fire, not TTK
		sim.step(stream)
	_check(sim.state.squadrons.has("Target") and sim.state.squadrons["Target"]["strength"] < 10,
		"ambush: the concealed squadron damaged the enemy")
	_check(sim.state.squadrons["Ambusher"]["strength"] == 10,
		"ambush: the enemy never landed a single hit back — it couldn't see the ambusher")


## Concealment is per-observer, not global: a second enemy squadron that closes to
## within detection range of the ambusher CAN spot and target it, even though the
## first enemy (still far away) still can't.
func _test_ambush_breaks_when_spotted() -> void:
	var stream := CommandStream.new()
	_spawn_field(stream, "F1", Vector2(0, 0), 40.0)
	_spawn(stream, "Ambusher", 0, Vector2(0, 0), 0.0)
	_spawn(stream, "Scout", 1, Vector2(120, 0), 180.0)  # starts beyond detection range (120 > 90)
	stream.record(Commands.make(0, "order_move", {"id": "Scout", "target": [60, 0]}))  # closes to 60 (< 90)
	var sim := Sim.new(1)
	var target_before := ""
	for t in range(150):
		sim.step(stream)
		if t == 0:
			var scout: Dictionary = sim.state.squadrons["Scout"]
			target_before = Combat.pick_target("Scout", scout, sim.state.squadrons, sim.state.terrain)
	_check(target_before == "", "ambush breaks: Scout starts too far away to spot the ambusher")
	var scout_now: Dictionary = sim.state.squadrons["Scout"]
	var dist: float = (scout_now["pos"] as Vector2).distance_to(sim.state.squadrons["Ambusher"]["pos"])
	_check(dist <= Terrain.ASTEROID_DETECT_RADIUS, "ambush breaks: Scout has closed to within detection range")
	var target_after := Combat.pick_target("Scout", scout_now, sim.state.squadrons, sim.state.terrain)
	_check(target_after == "Ambusher", "ambush breaks: once close enough, Scout can now target the ambusher")


## A field sitting directly between two squadrons in open space (neither is inside
## it) still blocks fire both ways -- distinct from concealment, which only hides a
## squadron actually standing inside a field.
func _test_field_between_blocks_both_sides() -> void:
	var stream := CommandStream.new()
	_spawn_field(stream, "F1", Vector2(75, 0), 30.0)
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0)
	_spawn(stream, "B", 1, Vector2(150, 0), 180.0)
	var sim := Sim.new(1)
	for t in range(200):
		sim.step(stream)
	_check(sim.state.squadrons["A"]["strength"] == 10 and sim.state.squadrons["B"]["strength"] == 10,
		"field between: neither side can fire through the asteroid field between them")
