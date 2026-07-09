extends RefCounted
class_name StrategicAI
## Strategic-level AI for one realm (issue #16) — distinct from the TACTICAL
## `sim/battle_ai.gd`, which only ever runs once inside a single tactical
## battle. This is the map-level decision-maker: where does this realm's one
## fleet go next. Called once per tick from strategic_map.gd for each AI realm
## (sides 1 and 2), mirroring how main.gd calls the tactical AI's `act()` each
## battle tick.
##
## Re-created fresh each time strategic_map.gd's `_ready()` runs — NOT
## persisted across the scene round-trip to main.tscn via StrategicSession,
## unlike the StrategicSim itself. The only visible effect is the decision
## cadence resetting to "decide immediately" right after returning from any
## battle, which is harmless (arguably desirable: react promptly post-battle).
##
## v1 assumes exactly one fleet per realm, matching the demo's actual setup —
## multi-fleet realms and fleet production are out of scope for this issue.
##
## Strict priority order per decision (mirrors battle_ai.gd's posture-priority
## approach, already proven sufficient for a legible, testable AI at this
## project's scope — a global "best target in the whole galaxy" search was
## considered and rejected as adding complexity without enough real benefit at
## this scale: 12 systems, at most 3 fleets total):
##   1. Rebuild: damaged -> sail home if not already docked there, or just stay
##      put if already there (never falls through to attack/expand while still
##      under-strength, even at home).
##   2. Attack: a reachable opposing fleet is winnable with a real margin (not a
##      bare >=, which would read as suicidal in a roughly even fight) -> go
##      fight it.
##   3. Expand: otherwise, head toward the nearest system this realm doesn't
##      already own (peaceful annexation via strategic_sim.gd's arrival capture).
##   4. Hold: nothing worth doing this cycle — stay put, let supply/rebuild recover.

const DECISION_PERIOD_TICKS := 4  # weeks between re-plans -- much coarser than
                                    # the tactical AI's ~3-second cadence, since a
                                    # week is a much bigger unit of time
const REBUILD_THRESHOLD := 0.5     # rebuild once below this fraction of preset max
const WIN_MARGIN := 1.15           # must out-power a target by this much to attack it

var _side: int
var _home_shipyard: String
var _next_decision_tick := 0


func _init(side: int, home_shipyard: String) -> void:
	_side = side
	_home_shipyard = home_shipyard


func act(state: StrategicState, stream: StrategicCommandStream) -> void:
	if state.tick < _next_decision_tick:
		return
	_next_decision_tick = state.tick + DECISION_PERIOD_TICKS

	var fleet_id := _my_fleet(state, _side)
	if fleet_id == "":
		return  # this realm has already been wiped out -- nothing to command
	var f: Dictionary = state.fleets[fleet_id]

	var max_strength := FleetPresets.total_strength(f.get("preset", FleetPresets.DEFAULT))
	if float(f["strength"]) < max_strength * REBUILD_THRESHOLD:
		# Damaged: either sail home, or — if already there — just stay and let
		# Shipyard.rebuild do its job (running automatically every tick
		# regardless of AI decisions). Returning unconditionally here, not just
		# when an order was actually issued, matters: without it, a fleet
		# already docked and still under-strength would fall through to the
		# attack/expand checks below and wander back off before finishing
		# repairs.
		if f["system"] != _home_shipyard:
			_order_to(stream, state, fleet_id, f, _home_shipyard)
		return

	var target_fleet := _winnable_target(state, _side, f)
	if target_fleet != "":
		_order_to(stream, state, fleet_id, f, state.fleets[target_fleet]["system"])
		return

	var expand_to := _nearest_unowned(state, _side, f)
	if expand_to != "":
		_order_to(stream, state, fleet_id, f, expand_to)
		return
	# Hold: nothing worth doing this cycle.


static func _my_fleet(state: StrategicState, side: int) -> String:
	var ids := state.fleets.keys()
	ids.sort()
	for id in ids:
		if state.fleets[id]["side"] == side:
			return id
	return ""


## The nearest opposing fleet this realm could beat with a real margin (not a
## coin-flip win) — ties broken by distance, same "closest legal target"
## precedent as the tactical AI's Combat.pick_target.
static func _winnable_target(state: StrategicState, side: int, f: Dictionary) -> String:
	var my_power := AutoResolve.effective_power(int(f["strength"]), float(f["supply"]))
	var best_id := ""
	var best_dist := INF
	var ids := state.fleets.keys()
	ids.sort()
	for id in ids:
		var other: Dictionary = state.fleets[id]
		if other["side"] == side:
			continue
		var their_power := AutoResolve.effective_power(int(other["strength"]), float(other["supply"]))
		if my_power < their_power * WIN_MARGIN:
			continue
		if f["system"] == other["system"]:
			continue  # an existing contact resolves on its own before the next decision
		var path := Galaxy.shortest_path(f["system"], other["system"])
		if path.is_empty():
			continue  # unreachable
		var dist := _path_length(f["system"], path)
		if dist < best_dist:
			best_dist = dist
			best_id = id
	return best_id


## Nearest system not owned by `side`, reachable at all — the expansion target
## once no fight looks winnable.
static func _nearest_unowned(state: StrategicState, side: int, f: Dictionary) -> String:
	var best_id := ""
	var best_dist := INF
	var ids := state.system_owner.keys()
	ids.sort()
	for id in ids:
		if id == f["system"] or state.system_owner[id] == side:
			continue
		var path := Galaxy.shortest_path(f["system"], id)
		if path.is_empty():
			continue
		var dist := _path_length(f["system"], path)
		if dist < best_dist:
			best_dist = dist
			best_id = id
	return best_id


static func _path_length(from: String, path: Array[String]) -> float:
	var total := 0.0
	var cur := from
	for hop in path:
		total += Galaxy.lane_length(cur, hop)
		cur = hop
	return total


## A real bug this guards against, caught by an actual 3-realm campaign run
## (not assumed): reissuing an identical order_move to a fleet already headed
## there resets `progress` back to 0 (see strategic_sim.gd's _start_next_hop),
## so if DECISION_PERIOD_TICKS is shorter than a single hop's travel time, a
## naive "always issue an order toward the target" would restart the SAME hop
## from scratch every decision cycle, forever, and the fleet would never
## actually arrive anywhere.
static func _order_to(stream: StrategicCommandStream, state: StrategicState, fleet_id: String,
		f: Dictionary, target: String) -> void:
	var final_stop: String = f["system"]
	if not (f["path"] as Array).is_empty():
		final_stop = (f["path"] as Array)[-1]
	elif f["dest"] != null:
		final_stop = f["dest"]
	if final_stop == target:
		return  # already there, or already correctly en route -- don't reset progress
	var path := Galaxy.shortest_path(f["system"], target)
	if path.is_empty():
		return
	stream.record(StrategicCommands.make(state.tick, "order_move", {"id": fleet_id, "path": path}))
