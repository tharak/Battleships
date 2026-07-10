extends SceneTree
## Headless behavior tests for materiel/shipyards/fleet rebuild (issue #15,
## GDD §4.2/§4.4). Run:
##   godot --headless --path game --script res://tests/test_shipyard.gd
##
## Layered like the other strategic suites: pure Shipyard function tests pin
## down the accrue/rebuild rules exactly, then Sim-integration tests play out
## the issue's own showable outcome — "losses matter across battles; a war of
## attrition is possible" — over real ticks.

var _failures := 0


func _init() -> void:
	print("test_shipyard — Godot ", Engine.get_version_info()["string"])

	_test_accrue_scales_with_owned_systems()
	_test_accrue_credits_all_three_realms()
	_test_rebuild_does_nothing_away_from_shipyard()
	_test_rebuild_does_nothing_at_full_strength()
	_test_rebuild_does_nothing_without_materiel()
	_test_rebuild_restores_strength_and_spends_materiel()
	_test_rebuild_never_exceeds_preset_max()
	_test_rebuild_respects_live_ownership_not_just_the_static_table()
	_test_losses_persist_until_rebuilt()
	_test_war_of_attrition_stalls_without_materiel()

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


## --- pure Shipyard functions -----------------------------------------------------------

func _test_accrue_scales_with_owned_systems() -> void:
	var state := StrategicState.new()
	var before: float = state.materiel[0]
	var revenue := Shipyard.accrue(state)
	# Side 0 (player) owns exactly the 4 A-sector systems by default. Issue #17:
	# income is now planet-industry-driven, but a fresh planet at default policy
	# produces exactly Planet.INDUSTRY_BASE (the old flat constant's value).
	_check(is_equal_approx(revenue[0], 4 * Planet.INDUSTRY_BASE),
		"accrue: the RAW revenue returned scales with how many systems a side currently owns")
	# Issue #22: only the military budget share actually lands in state.materiel --
	# the rest funds Politics.advance's seat/planet effects instead.
	var military_frac: float = state.politics[0]["budget_military"]
	_check(is_equal_approx(state.materiel[0], before + 4 * Planet.INDUSTRY_BASE * military_frac),
		"accrue: state.materiel only gets the military budget share of the raw revenue")


## Issue #16: a fixed 2-side loop here would have silently starved the 3rd
## realm of income entirely -- confirmed as a real bug, not hypothetical, by
## the accrue() rewrite that made this pass (it now derives sides from
## state.system_owner instead of hardcoding [0, 1]).
func _test_accrue_credits_all_three_realms() -> void:
	var state := StrategicState.new()
	Shipyard.accrue(state)
	var per_sector: float = 4 * Planet.INDUSTRY_BASE * state.politics[0]["budget_military"]
	_check(state.materiel[0] == per_sector, "accrue: side 0 (player, Sector A) gets its income")
	_check(state.materiel[1] == per_sector, "accrue: side 1 (AI realm, Sector B) also gets its income")
	_check(state.materiel[2] == per_sector, "accrue: side 2 (AI realm, Sector C) also gets its income")


func _test_rebuild_does_nothing_away_from_shipyard() -> void:
	var state := StrategicState.new()
	state.materiel[0] = 1000.0
	state.fleets["F1"] = {"side": 0, "system": "A2", "preset": "line", "strength": 10}
	Shipyard.rebuild(state, "F1")
	_check(state.fleets["F1"]["strength"] == 10,
		"rebuild: a fleet not docked at its own shipyard doesn't repair, however much materiel is available")


func _test_rebuild_does_nothing_at_full_strength() -> void:
	var state := StrategicState.new()
	state.materiel[0] = 1000.0
	var max_strength := FleetPresets.total_strength("line")
	state.fleets["F1"] = {"side": 0, "system": "A1", "preset": "line", "strength": max_strength}
	Shipyard.rebuild(state, "F1")
	_check(state.fleets["F1"]["strength"] == max_strength,
		"rebuild: a fleet already at full strength doesn't over-repair")


func _test_rebuild_does_nothing_without_materiel() -> void:
	var state := StrategicState.new()
	state.materiel[0] = 0.0
	state.fleets["F1"] = {"side": 0, "system": "A1", "preset": "line", "strength": 10}
	Shipyard.rebuild(state, "F1")
	_check(state.fleets["F1"]["strength"] == 10,
		"rebuild: no materiel means no repair, even docked and damaged")


func _test_rebuild_restores_strength_and_spends_materiel() -> void:
	var state := StrategicState.new()
	state.materiel[0] = 1000.0
	state.fleets["F1"] = {"side": 0, "system": "A1", "preset": "line", "strength": 10}
	Shipyard.rebuild(state, "F1")
	_check(state.fleets["F1"]["strength"] == 10 + Shipyard.REBUILD_RATE,
		"rebuild: a docked, damaged, well-funded fleet repairs by REBUILD_RATE this tick")
	_check(state.materiel[0] == 1000.0 - Shipyard.REBUILD_RATE * Shipyard.MATERIEL_PER_STRENGTH,
		"rebuild: repairing costs materiel proportional to strength restored")


func _test_rebuild_never_exceeds_preset_max() -> void:
	var state := StrategicState.new()
	state.materiel[0] = 1000.0
	var max_strength := FleetPresets.total_strength("line")
	state.fleets["F1"] = {"side": 0, "system": "A1", "preset": "line", "strength": max_strength - 1}
	Shipyard.rebuild(state, "F1")
	_check(state.fleets["F1"]["strength"] == max_strength,
		"rebuild: tops out exactly at the preset's original max, not a strength point over")


## Issue #16: territory capture means a shipyard's OWNER can change, but the
## static SHIPYARDS table (whose realm originally built the hub) never does --
## rebuild must check live state.system_owner too, or a captured shipyard
## would silently keep rebuilding ships for its former owner forever.
func _test_rebuild_respects_live_ownership_not_just_the_static_table() -> void:
	var state := StrategicState.new()
	state.materiel[0] = 1000.0  # plenty of materiel -- ownership is the ONLY thing under test
	state.fleets["F1"] = {"side": 0, "system": "A1", "preset": "line", "strength": 10}
	state.system_owner["A1"] = 1  # captured by a rival -- Shipyard.SHIPYARDS still says "A1: 0"
	Shipyard.rebuild(state, "F1")
	_check(state.fleets["F1"]["strength"] == 10,
		"rebuild: a captured shipyard stops rebuilding for its former owner, even with materiel to spare")


## --- Sim integration: the issue's own showable outcome ----------------------------------

## Losses from a fought battle stay lost until a fleet actually gets home and
## spends the time+materiel to rebuild -- this is what makes losses matter
## ACROSS battles, not just within one.
func _test_losses_persist_until_rebuilt() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	var max_strength := FleetPresets.total_strength("line")
	_check(sim.state.fleets["F1"]["strength"] == max_strength, "setup: fleet spawns at full preset strength")

	# A battle happened and this fleet took real losses (simulating
	# BattleBridge.apply_result's write-back, issue #14).
	sim.state.fleets["F1"]["strength"] = max_strength / 2

	# Time passes while the fleet sits at A1 (its own shipyard) -- it should
	# recover, since A1 both owns materiel income and is the rebuild dock.
	for t in range(30):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["strength"] > max_strength / 2,
		"losses persist: docked at the shipyard with materiel flowing, strength actually recovers over time")


## The other half of the showable outcome: attrition has teeth. A fleet
## damaged in enemy territory, with its own side's economy providing no
## materiel at all (e.g. every owned system lost), cannot out-rebuild its
## losses even sitting right at the shipyard -- the war of attrition is real,
## not just flavor text.
func _test_war_of_attrition_stalls_without_materiel() -> void:
	var stream := StrategicCommandStream.new()
	stream.record(StrategicCommands.make(0, "spawn_fleet", {"id": "F1", "side": 0, "system": "A1", "preset": "line"}))
	var sim := StrategicSim.new()
	sim.step(stream)
	var max_strength := FleetPresets.total_strength("line")
	sim.state.fleets["F1"]["strength"] = max_strength / 2
	sim.state.materiel[0] = 0.0

	# Strip every system this side owns (as if a losing war had cost them their
	# whole home sector) -- no more income, ever.
	for id in sim.state.system_owner.keys():
		if sim.state.system_owner[id] == 0:
			sim.state.system_owner[id] = -1
	# A1 is still where the fleet is docked, but Shipyard.rebuild checks OWNERSHIP
	# at the system, not just presence -- with A1 no longer owned by side 0, it
	# isn't a functioning shipyard for them anymore either.

	for t in range(50):
		sim.step(stream)
	_check(sim.state.fleets["F1"]["strength"] == max_strength / 2,
		"attrition: with no income and no owned shipyard, a damaged fleet simply cannot recover, however long it waits")
