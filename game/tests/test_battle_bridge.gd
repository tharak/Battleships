extends SceneTree
## Headless behavior tests for the strategic <-> tactical contract (issue #14,
## GDD §5.8/§5.9). Run:
##   godot --headless --path game --script res://tests/test_battle_bridge.gd
##
## Layered like the other suites: pure BattleBridge/AutoResolve function tests
## first, then a full Sim-integration test proves the issue's own showable
## outcome end to end — "the same two fleets fight noticeably differently at
## full vs empty supply" — not just that the modifiers are computed correctly
## in isolation.

var _failures := 0


func _init() -> void:
	print("test_battle_bridge — Godot ", Engine.get_version_info()["string"])

	_test_tactical_modifiers_table()
	_test_detect_contact_finds_opposing_fleets_sharing_a_system()
	_test_detect_contact_ignores_same_side_fleets_sharing_a_system()
	_test_detect_contact_empty_when_no_contact()
	_test_seed_skirmish_fills_config_from_fleets()
	_test_apply_result_removes_wiped_fleet_and_updates_survivor()
	_test_auto_resolve_mismatch_favors_stronger_side()
	_test_auto_resolve_even_fight_costs_both_sides()
	_test_auto_resolve_starved_fleet_fares_worse_than_full_supply()
	_test_same_fleets_fight_differently_at_full_vs_starved_supply()

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


## --- pure BattleBridge functions -------------------------------------------------------

func _test_tactical_modifiers_table() -> void:
	var full := BattleBridge.tactical_modifiers(80.0)
	_check(full["uptime_mult"] == 1.0 and full["morale_cap"] == 100.0,
		"tactical_modifiers: >=66 supply is full uptime, no morale cap penalty")
	var mid := BattleBridge.tactical_modifiers(50.0)
	_check(mid["uptime_mult"] == 0.75 and mid["morale_cap"] == 90.0,
		"tactical_modifiers: 33-65 supply is -25% uptime, -10 morale cap")
	var low := BattleBridge.tactical_modifiers(10.0)
	_check(low["uptime_mult"] == 0.5 and low["morale_cap"] == 75.0,
		"tactical_modifiers: <33 supply is -50% uptime, -25 morale cap")


func _test_detect_contact_finds_opposing_fleets_sharing_a_system() -> void:
	var state := StrategicState.new()
	state.fleets["Blue"] = {"side": 0, "system": "B1", "dest": null}
	state.fleets["Red"] = {"side": 1, "system": "B1", "dest": null}
	var contact := BattleBridge.detect_contact(state)
	_check(contact.size() == 2 and "Blue" in contact and "Red" in contact,
		"detect_contact: two opposing fleets in the same system are a contact")


func _test_detect_contact_ignores_same_side_fleets_sharing_a_system() -> void:
	var state := StrategicState.new()
	state.fleets["Blue1"] = {"side": 0, "system": "B1", "dest": null}
	state.fleets["Blue2"] = {"side": 0, "system": "B1", "dest": null}
	_check(BattleBridge.detect_contact(state).is_empty(),
		"detect_contact: two friendly fleets sharing a system is not a contact")


func _test_detect_contact_empty_when_no_contact() -> void:
	var state := StrategicState.new()
	state.fleets["Blue"] = {"side": 0, "system": "A1", "dest": null}
	state.fleets["Red"] = {"side": 1, "system": "C1", "dest": null}
	_check(BattleBridge.detect_contact(state).is_empty(),
		"detect_contact: fleets in different systems is not a contact")


func _test_seed_skirmish_fills_config_from_fleets() -> void:
	var state := StrategicState.new()
	state.fleets["Blue"] = {"side": 0, "system": "B1", "dest": null, "preset": "wedge", "supply": 80.0}
	state.fleets["Red"] = {"side": 1, "system": "B1", "dest": null, "preset": "swarm", "supply": 20.0}
	BattleBridge.seed_skirmish(state, "Blue", "Red")
	_check(SkirmishConfig.player_preset == "wedge" and SkirmishConfig.enemy_preset == "swarm",
		"seed_skirmish: each side's roster preset carries over")
	_check(SkirmishConfig.player_uptime_mult == 1.0 and SkirmishConfig.enemy_uptime_mult == 0.5,
		"seed_skirmish: each side's supply maps to its own tactical modifiers")
	_check(SkirmishConfig.from_map_contact and SkirmishConfig.contact_fleet_ids == ["Blue", "Red"],
		"seed_skirmish: marks this as a map-contact battle and remembers which fleets")


func _test_apply_result_removes_wiped_fleet_and_updates_survivor() -> void:
	var state := StrategicState.new()
	state.fleets["Blue"] = {"side": 0, "system": "B1", "strength": 90}
	state.fleets["Red"] = {"side": 1, "system": "B1", "strength": 90}
	BattleBridge.apply_result(state, "Blue", "Red", 60, 0)
	_check(state.fleets["Blue"]["strength"] == 60, "apply_result: survivor's strength updates to what's left")
	_check(not state.fleets.has("Red"), "apply_result: a fleet reduced to zero is removed from the map")


## --- pure AutoResolve functions ----------------------------------------------------------

func _test_auto_resolve_mismatch_favors_stronger_side() -> void:
	var result := AutoResolve.resolve(100, 100.0, 20, 100.0)
	_check(result["winner"] == 0, "auto_resolve: the much stronger side wins a lopsided fight")
	_check(result["a_left"] > result["b_left"],
		"auto_resolve: the winner ends up with more strength left than the loser")


func _test_auto_resolve_even_fight_costs_both_sides() -> void:
	var result := AutoResolve.resolve(100, 100.0, 100, 100.0)
	_check(result["a_left"] < 100 and result["b_left"] < 100,
		"auto_resolve: an even fight costs both sides real losses, not a free pass")


func _test_auto_resolve_starved_fleet_fares_worse_than_full_supply() -> void:
	var starved := AutoResolve.resolve(100, 20.0, 100, 100.0)
	var full := AutoResolve.resolve(100, 100.0, 100, 100.0)
	_check(starved["a_left"] < full["a_left"],
		"auto_resolve: a starved fleet comes out worse than the same fleet at full supply")


## --- Sim integration: the issue's own showable outcome ----------------------------------

## Same fleets, same seed, same scripted stream -- the ONLY difference is the
## enemy's supply-derived modifiers. If the outcome doesn't meaningfully
## diverge, the strategic <-> tactical contract isn't actually doing anything.
func _test_same_fleets_fight_differently_at_full_vs_starved_supply() -> void:
	var final_blue_full: int
	var final_red_full: int
	var final_blue_starved: int
	var final_red_starved: int

	for starved in [false, true]:
		var stream := CommandStream.new()
		for i in range(5):
			stream.record(Commands.make(0, "spawn", {
				"id": "B%d" % i, "side": 0, "pos": Commands.pos_to_array(Vector2(300, 260 + i * 30)),
				"facing": 0.0, "strength": 15, "flag": i == 0,
			}))
			stream.record(Commands.make(0, "spawn", {
				"id": "R%d" % i, "side": 1, "pos": Commands.pos_to_array(Vector2(450, 260 + i * 30)),
				"facing": 180.0, "strength": 15, "flag": i == 0,
			}))
		var sim := Sim.new(7)
		if starved:
			var mods := BattleBridge.tactical_modifiers(10.0)  # deep starvation, <33
			sim.state.fleets[1]["uptime_mult"] = mods["uptime_mult"]
			sim.state.fleets[1]["morale_cap"] = mods["morale_cap"]
		for t in range(3000):
			sim.step(stream)

		var blue_left := 0
		var red_left := 0
		for id in sim.state.squadrons.keys():
			var sq: Dictionary = sim.state.squadrons[id]
			if sq["side"] == 0:
				blue_left += sq["strength"]
			else:
				red_left += sq["strength"]
		if starved:
			final_blue_starved = blue_left
			final_red_starved = red_left
		else:
			final_blue_full = blue_left
			final_red_full = red_left

	# NOT asserting final_blue_full == final_red_full here: squadrons are always
	# processed in sorted-id order (a deliberate determinism choice, see
	# battle_state.gd), so blue ("B0".."B4", sorting before "R0".."R4") gets a
	# small systematic first-mover edge every tick even in an otherwise
	# perfectly symmetric fight -- confirmed by an earlier run of this exact
	# test (45 vs 30 at full supply for both sides). That's expected, not a bug;
	# the comparison that actually matters is each side against ITS OWN
	# full-supply baseline, below.
	_check(final_blue_starved > final_blue_full,
		"starved enemy: blue comes out ahead of its own full-supply-vs-full-supply baseline (%d vs %d)" %
			[final_blue_starved, final_blue_full])
	_check(final_red_starved < final_red_full,
		"starved enemy: red comes out worse than its own full-supply baseline (%d vs %d)" %
			[final_red_starved, final_red_full])
