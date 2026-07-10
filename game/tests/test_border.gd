extends SceneTree
## Headless behavior tests for the map border/escape mechanic. Run:
##   godot --headless --path game --script res://tests/test_border.gd
##
## A squadron that crosses Sim.BORDER_MIN/BORDER_MAX escapes the battle entirely
## (sim/sim.gd's _advance_border): removed from state.squadrons, its strength and a
## count credited to state.fleets[side]["escaped_strength"/"escaped_count"] instead
## of being treated as a loss. Deliberately free/no-friction (direct user decision) —
## these tests pin down the mechanics, not add friction the design doesn't want.

var _failures := 0


func _init() -> void:
	print("test_border — Godot ", Engine.get_version_info()["string"])

	_test_squadron_outside_border_escapes()
	_test_squadron_just_inside_is_unaffected()
	_test_escape_does_not_trigger_contagion()
	_test_escaping_flagship_triggers_flagship_lost_without_contagion()
	_test_routed_squadron_can_flee_across_border()

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


func _spawn(stream: CommandStream, id: String, side: int, pos: Vector2, facing: float, strength := 10, flag := false) -> void:
	stream.record(Commands.make(0, "spawn", {
		"id": id, "side": side, "pos": Commands.pos_to_array(pos), "facing": facing,
		"strength": strength, "flag": flag,
	}))


## A squadron whose position ends up outside the border is removed from play and
## its strength/count credited to its side's escaped tallies instead of vanishing.
func _test_squadron_outside_border_escapes() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(500, 300), 0.0, 7)
	var sim := Sim.new(1)
	sim.step(stream)
	sim.state.squadrons["A"]["pos"] = Vector2(Sim.BORDER_MAX.x + 50.0, 300)
	sim.step(stream)
	_check(not sim.state.squadrons.has("A"), "escape: a squadron past the border is removed from play")
	_check(sim.state.fleets[0]["escaped_strength"] == 7, "escape: its strength is credited to escaped_strength")
	_check(sim.state.fleets[0]["escaped_count"] == 1, "escape: its count is credited to escaped_count")


## A squadron sitting exactly on the inside edge of the border is untouched.
func _test_squadron_just_inside_is_unaffected() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "A", 0, Vector2(Sim.BORDER_MAX.x - 1.0, 300), 0.0, 7)
	var sim := Sim.new(1)
	sim.step(stream)
	_check(sim.state.squadrons.has("A"), "no escape: a squadron just inside the border stays in play")
	_check(sim.state.fleets[0]["escaped_strength"] == 0, "no escape: nothing credited to escaped_strength")


## Unlike a destruction, an escape must NOT drain nearby friendlies' morale — "it got
## away" reads as better news than "it died" (sim.gd's _advance_morale docstring).
func _test_escape_does_not_trigger_contagion() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "Leaving", 0, Vector2(500, 300), 0.0, 7)
	_spawn(stream, "Nearby", 0, Vector2(520, 300), 0.0, 7)   # well within Morale.CONTAGION_RADIUS
	var sim := Sim.new(1)
	sim.step(stream)
	var morale_before: float = sim.state.squadrons["Nearby"]["morale"]
	sim.state.squadrons["Leaving"]["pos"] = Vector2(Sim.BORDER_MAX.x + 50.0, 300)
	sim.step(stream)
	_check(sim.state.squadrons["Nearby"]["morale"] == morale_before,
		"no contagion: a nearby friendly's morale is untouched by an ally escaping")


## An escaping flagship still costs its fleet the same flagship_lost penalty/shock a
## destroyed one would (Command.flagship_pos can't tell "gone" from "dead" apart) —
## but without the nearby-friendlies contagion a kill causes.
func _test_escaping_flagship_triggers_flagship_lost_without_contagion() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "Flag", 0, Vector2(500, 300), 0.0, 7, true)
	_spawn(stream, "Nearby", 0, Vector2(520, 300), 0.0, 7)
	var sim := Sim.new(1)
	sim.step(stream)
	var morale_before: float = sim.state.squadrons["Nearby"]["morale"]
	sim.state.squadrons["Flag"]["pos"] = Vector2(Sim.BORDER_MAX.x + 50.0, 300)
	sim.step(stream)
	_check(sim.state.fleets[0]["flagship_lost"], "flagship escape: flagship_lost is set, same as a destroyed flagship")
	_check(sim.state.squadrons["Nearby"]["morale"] == morale_before - Command.FLAGSHIP_LOST_SHOCK,
		"flagship escape: the fleet-wide one-time shock applies")
	_check(sim.state.squadrons["Nearby"]["morale"] > morale_before - Command.FLAGSHIP_LOST_SHOCK - Morale.NEARBY_DEATH_PENALTY,
		"flagship escape: no additional nearby-death contagion is stacked on top")


## A routed squadron's autopilot flee (away from the nearest enemy, at
## Morale.FLEE_SPEED_MULT) can carry it across the border and off the battle for
## real — placed close to an edge so this resolves in a bounded tick budget.
func _test_routed_squadron_can_flee_across_border() -> void:
	var stream := CommandStream.new()
	_spawn(stream, "Enemy", 1, Vector2(Sim.BORDER_MAX.x - 200.0, 300), 180.0)
	var sim := Sim.new(1)
	sim.step(stream)
	sim.state.squadrons["Fleeing"] = {
		"side": 0, "pos": Vector2(Sim.BORDER_MAX.x - 20.0, 300), "facing": 180.0,
		"desired_facing": 180.0, "strength": 10, "flag": false, "target": null,
		"arrive_facing": null, "cohesion": 100.0, "dmg_accum": 0.0, "morale": 0.0, "routed": true,
	}
	var escaped := false
	for t in range(300):
		sim.step(stream)
		if not sim.state.squadrons.has("Fleeing"):
			escaped = true
			break
	_check(escaped, "routed flee: a routed squadron placed near the border escapes within the tick budget")
	_check(sim.state.fleets[0]["escaped_strength"] == 10,
		"routed flee: its strength is credited to escaped_strength, not lost")
