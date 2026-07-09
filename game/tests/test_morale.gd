extends SceneTree
## Headless tests for morale, waver, rout (issue #7, GDD §5.5). Run:
##   godot --headless --path game --script res://tests/test_morale.gd
##
## Layered like the other suites: pure Morale function tests first, then Sim-level
## tests for the emergent behavior the showable outcome asks for — a battle that
## ends with one side breaking and fleeing, not being annihilated.

const TOL := 0.01

var _failures := 0


func _init() -> void:
	print("test_morale — Godot ", Engine.get_version_info()["string"])

	_test_waver_boundary()
	_test_fire_multiplier()
	_test_apply_hit_scales_by_arc()
	_test_apply_hit_ignores_zero_loss()
	_test_regen()
	_test_rout_rally_hysteresis()
	_test_contagion_radius()

	_test_sustained_fire_routs_before_annihilation()
	_test_routed_squadron_flees()
	_test_routed_squadron_can_escape_range()
	_test_routed_squadron_cannot_fire()
	_test_routed_squadron_ignores_orders()
	_test_rally_after_disengaging()
	_test_rout_contagion_hits_nearby_friendlies()

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


func _sq(morale := 100.0, routed := false) -> Dictionary:
	return {"morale": morale, "routed": routed, "target": Vector2(1, 1)}


## --- pure Morale functions ---------------------------------------------------------

func _test_waver_boundary() -> void:
	_check(not Morale.is_wavering(_sq(50.0)), "waver: exactly at the threshold is still steady")
	_check(Morale.is_wavering(_sq(49.9)), "waver: just below the threshold wavers")
	_check(not Morale.is_wavering(_sq(10.0, true)), "waver: a routed squadron is never merely 'wavering'")


func _test_fire_multiplier() -> void:
	_check(Morale.fire_multiplier(_sq(100.0)) == 1.0, "fire_multiplier: steady fires at full strength")
	_check(Morale.fire_multiplier(_sq(30.0)) == Morale.WAVER_FIRE_MULT, "fire_multiplier: wavering is reduced")
	_check(Morale.fire_multiplier(_sq(0.0, true)) == 0.0, "fire_multiplier: routed cannot fire")


func _test_apply_hit_scales_by_arc() -> void:
	var front := _sq(); Morale.apply_hit(front, "front", 1)
	var flank := _sq(); Morale.apply_hit(flank, "flank", 1)
	var rear := _sq(); Morale.apply_hit(rear, "rear", 1)
	_check(front["morale"] < 100.0, "apply_hit: a front-arc loss costs morale")
	_check(flank["morale"] < front["morale"], "apply_hit: a flank loss costs more than front")
	_check(rear["morale"] < flank["morale"], "apply_hit: a rear loss costs the most")
	var two := _sq(); Morale.apply_hit(two, "front", 2)
	var one := _sq(); Morale.apply_hit(one, "front", 1)
	_check(two["morale"] < one["morale"], "apply_hit: losing 2 points costs more than losing 1")


func _test_apply_hit_ignores_zero_loss() -> void:
	var sq := _sq()
	Morale.apply_hit(sq, "rear", 0)
	_check(sq["morale"] == 100.0, "apply_hit: no whole strength lost -> no morale cost, any arc")


func _test_regen() -> void:
	var sq := _sq(50.0)
	Morale.regen(sq, 1.0)
	_check(sq["morale"] > 50.0, "regen: morale increases over time")
	var full := _sq(100.0)
	Morale.regen(full, 10.0)
	_check(full["morale"] == 100.0, "regen: never exceeds 100")


func _test_rout_rally_hysteresis() -> void:
	var sq := _sq(1.0)
	_check(Morale.check_transition(sq) == "", "rout: above the threshold, no transition yet")
	sq["morale"] = 0.0
	_check(Morale.check_transition(sq) == "routed", "rout: hitting 0 triggers a rout")
	_check(sq["routed"] and sq["target"] == null,
		"rout: sets the routed flag and clears any standing order")
	sq["morale"] = 40.0
	_check(Morale.check_transition(sq) == "",
		"rally: recovering to 40 (below RALLY_THRESHOLD) does not yet rally")
	sq["morale"] = 50.0
	_check(Morale.check_transition(sq) == "rallied", "rally: reaching 50 rallies")
	_check(not sq["routed"], "rally: clears the routed flag")


func _test_contagion_radius() -> void:
	var squadrons := {
		"A": {"side": 0, "pos": Vector2(0, 0), "routed": false},
		"near": {"side": 0, "pos": Vector2(50, 0), "routed": false},
		"far": {"side": 0, "pos": Vector2(500, 0), "routed": false},
		"enemy": {"side": 1, "pos": Vector2(10, 0), "routed": false},
		"already_routed": {"side": 0, "pos": Vector2(20, 0), "routed": true},
	}
	var targets := Morale.contagion_targets(squadrons, 0, Vector2(0, 0), "A")
	_check("near" in targets, "contagion: a nearby friendly is included")
	_check(not ("far" in targets), "contagion: a distant friendly is excluded")
	_check(not ("enemy" in targets), "contagion: the enemy side is excluded")
	_check(not ("already_routed" in targets), "contagion: an already-routed friendly is excluded")
	_check(not ("A" in targets), "contagion: the trigger itself is excluded")


## --- Sim integration -----------------------------------------------------------------

func _spawn(stream: CommandStream, id: String, side: int, pos: Vector2, facing: float, strength := 4) -> void:
	stream.record(Commands.make(0, "spawn", {
		"id": id, "side": side, "pos": Commands.pos_to_array(pos), "facing": facing,
		"strength": strength, "flag": false,
	}))


## A big, sustained mismatch: the showable outcome is a battle that ends in a rout,
## not annihilation — the weaker side should break (rout) before it's wiped out.
func _test_sustained_fire_routs_before_annihilation() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0, 20)     # heavy firepower
	_spawn(stream, "B", 1, Vector2(150, 0), 180.0, 8)  # takes losses steadily
	var sim := Sim.new(1)
	var routed_tick := -1
	var strength_at_rout := -1
	for t in range(3000):
		var events := sim.step(stream)
		if not sim.state.squadrons.has("B"):
			break
		for ev in events:
			if ev["type"] == "routed" and ev["id"] == "B" and routed_tick == -1:
				routed_tick = t
				strength_at_rout = sim.state.squadrons["B"]["strength"]
	_check(routed_tick != -1, "rout before annihilation: B routs at some point")
	_check(strength_at_rout > 0, "rout before annihilation: B still had strength left when it routed")


func _test_routed_squadron_flees() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0, 4)
	# B is given a lot of strength purely so it can't be destroyed by A's rear-arc
	# fire during the test window — real rout is often (correctly) lethal via that
	# exact fire, exercised separately by _test_sustained_fire_routs_before_annihilation;
	# this test isolates the flee *movement* itself.
	_spawn(stream, "B", 1, Vector2(100, 0), 180.0, 40)
	var sim := Sim.new(1)
	sim.step(stream)
	sim.state.squadrons["B"]["morale"] = 0.0
	sim.step(stream)  # this tick's check_transition sees morale<=0 -> routs
	_check(sim.state.squadrons["B"]["routed"], "flee: B is now routed")
	var start_dist: float = (sim.state.squadrons["A"]["pos"] as Vector2).distance_to(sim.state.squadrons["B"]["pos"])
	for t in range(50):
		sim.step(stream)
	_check(sim.state.squadrons.has("B"), "flee: B survives the test window (strength margin was enough)")
	var end_dist: float = (sim.state.squadrons["A"]["pos"] as Vector2).distance_to(sim.state.squadrons["B"]["pos"])
	_check(end_dist > start_dist, "flee: a routed squadron's distance from the enemy increases")


## The real design guarantee: in a fair fight (not a curb-stomp, not point-blank),
## the loser should actually be able to rout and escape with a mauled fleet, not get
## run down. This exact scenario — evenly matched, starting near the edge of
## Combat.RANGE — is what caught the original tuning being wrong: first-pass numbers
## (turn-rate-limited reorientation on rout, weaker LOSS_PENALTY, no flee speed
## bonus) reliably killed the routing squadron a couple of ticks before it reached
## safety, verified empirically against the actual demo scene, not just synthetic
## unit scenarios.
func _test_routed_squadron_can_escape_range() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0, 4)
	_spawn(stream, "B", 1, Vector2(200, 0), 180.0, 4)  # just inside Combat.RANGE (220)
	var sim := Sim.new(1)
	for t in range(3000):
		sim.step(stream)
		if not sim.state.squadrons.has("B") or not sim.state.squadrons.has("A"):
			break
	_check(sim.state.squadrons.has("B"),
		"escape: an evenly-matched squadron routing near the edge of range survives")
	if sim.state.squadrons.has("B") and sim.state.squadrons.has("A"):
		var dist: float = (sim.state.squadrons["A"]["pos"] as Vector2).distance_to(sim.state.squadrons["B"]["pos"])
		_check(dist > Combat.RANGE, "escape: it actually cleared combat range, not just survived by luck")


func _test_routed_squadron_cannot_fire() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0, 4)
	_spawn(stream, "B", 1, Vector2(100, 0), 180.0, 4)  # faces A, in range+arc
	var sim := Sim.new(1)
	sim.step(stream)
	sim.state.squadrons["B"]["morale"] = 0.0
	sim.step(stream)
	_check(sim.state.squadrons["B"]["routed"], "no-fire: B is routed")
	var a_strength_before: int = sim.state.squadrons["A"]["strength"]
	for t in range(50):
		sim.step(stream)
		if not sim.state.squadrons.has("A"):
			break
	_check(sim.state.squadrons.has("A") and sim.state.squadrons["A"]["strength"] == a_strength_before,
		"no-fire: A takes zero damage from the routed B, even though B started in range and arc")


func _test_routed_squadron_ignores_orders() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0, 4)
	var sim := Sim.new(1)
	sim.step(stream)
	# -50, not 0: with no adversary firing this tick, regen (which runs before the
	# rout-transition check within the same _advance_morale call) would otherwise
	# bump an exact 0.0 back above the threshold before the check ever sees it.
	sim.state.squadrons["A"]["morale"] = -50.0
	sim.step(stream)
	_check(sim.state.squadrons["A"]["routed"], "ignores orders: A is routed")
	stream.record(Commands.make(sim.state.tick, "order_move", {"id": "A", "target": [500, 500]}))
	sim.step(stream)
	_check(sim.state.squadrons["A"]["target"] == null,
		"ignores orders: a fresh order_move while routed is dropped, not queued")


func _test_rally_after_disengaging() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0, 4)
	# No enemy at all: nothing to take fire from, so regen is uncontested — the
	# simplest possible "disengaged" scenario to prove rallying actually happens.
	var sim := Sim.new(1)
	sim.step(stream)
	# -50, not 0: see the note in _test_routed_squadron_ignores_orders — regen runs
	# before the transition check, so an exact 0.0 would get bumped up first.
	sim.state.squadrons["A"]["morale"] = -50.0
	sim.step(stream)
	_check(sim.state.squadrons["A"]["routed"], "rally: A starts routed")
	for t in range(200):
		sim.step(stream)
	_check(not sim.state.squadrons["A"]["routed"], "rally: A rallies once morale regenerates")


func _test_rout_contagion_hits_nearby_friendlies() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(0, 0), 0.0, 4)
	_spawn(stream, "Friend", 0, Vector2(40, 0), 0.0, 4)  # within CONTAGION_RADIUS
	var sim := Sim.new(1)
	sim.step(stream)
	var friend_morale_before: float = sim.state.squadrons["Friend"]["morale"]
	# -50, not 0: see the note in _test_routed_squadron_ignores_orders.
	sim.state.squadrons["A"]["morale"] = -50.0
	sim.step(stream)  # A routs this tick -> contagion fires
	_check(sim.state.squadrons["A"]["routed"], "contagion: A routed as expected")
	_check(sim.state.squadrons["Friend"]["morale"] < friend_morale_before,
		"contagion: a nearby friendly's morale drops the instant A routs, with no shots fired at it")
