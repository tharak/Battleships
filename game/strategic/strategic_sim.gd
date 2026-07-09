extends RefCounted
class_name StrategicSim
## The only mutation path for strategic state (GDD §11, mirrored from sim/sim.gd's
## "plain data + one mutation path" discipline). Ticked-pausable, 1 tick = 1 week
## (GDD §2, OQ4 resolved on issue #12: ticked time, not discrete turns).
##
## Fleet movement (issue #12's showable outcome, "fleets moving on the strategic
## map under time controls"): "travel takes ticks proportional to lane length"
## (GDD §4.1) — UNITS_PER_TICK converts Galaxy's hand-authored pixel-space lane
## lengths into a week count, so a fleet's progress along its current lane
## advances by UNITS_PER_TICK/length each tick, arriving (and starting the next
## queued hop, if any) once progress reaches 1.0.

const UNITS_PER_TICK := 50.0

var state: StrategicState


func _init() -> void:
	state = StrategicState.new()


## Advance exactly one tick: apply due commands, then move fleets, then settle
## supply (issue #13) and the economy/rebuild (issue #15) against wherever
## fleets ended up THIS tick — matches sim/sim.gd's combat-then-morale
## ordering (a later system reads the current tick's outcome from the earlier
## one, not last tick's stale state). Returns this tick's events (currently
## just "arrived") so a caller can react without re-deriving them, same
## convention as sim/sim.gd's step().
func step(stream: StrategicCommandStream) -> Array:
	for cmd in stream.due(state.tick):
		_apply(cmd)
	var events := _advance_fleets()
	_advance_supply()
	_advance_economy()
	state.tick += 1
	return events


func _advance_supply() -> void:
	var ids := state.fleets.keys()
	ids.sort()
	for id in ids:
		Supply.advance(state, id)


func _advance_economy() -> void:
	Shipyard.accrue(state)
	var ids := state.fleets.keys()
	ids.sort()
	for id in ids:
		Shipyard.rebuild(state, id)


func run_stream(stream: StrategicCommandStream, ticks: int) -> void:
	stream.reset_cursor()
	for i in range(ticks):
		step(stream)


func _apply(cmd: Dictionary) -> void:
	var a: Dictionary = cmd["a"]
	match cmd["k"]:
		"spawn_fleet":
			var preset: String = a.get("preset", FleetPresets.DEFAULT)
			state.fleets[a["id"]] = {
				"side": int(a["side"]), "system": String(a["system"]),
				"dest": null, "progress": 0.0, "path": [], "supply": 100.0,
				"preset": preset, "strength": FleetPresets.total_strength(preset),
			}
		"order_move":
			if state.fleets.has(a["id"]):
				var f: Dictionary = state.fleets[a["id"]]
				var path: Array = (a["path"] as Array).duplicate()
				if path.is_empty():
					return
				f["path"] = path
				_start_next_hop(f)


## Pops the next hop off `f["path"]` into `f["dest"]`, resetting progress — or
## clears `dest` (holds position) once the path is exhausted.
func _start_next_hop(f: Dictionary) -> void:
	if f["path"].is_empty():
		f["dest"] = null
		return
	f["dest"] = f["path"].pop_front()
	f["progress"] = 0.0


func _advance_fleets() -> Array:
	var events := []
	var ids := state.fleets.keys()
	ids.sort()
	var arrived_ids: Array[String] = []
	for id in ids:
		var f: Dictionary = state.fleets[id]
		if f["dest"] == null:
			continue
		var length: float = Galaxy.lane_length(f["system"], f["dest"])
		f["progress"] += UNITS_PER_TICK / maxf(length, 1.0)
		if f["progress"] >= 1.0:
			var arrived: String = f["dest"]
			f["system"] = arrived
			f["progress"] = 0.0
			f["dest"] = null
			events.append({"type": "arrived", "id": id, "system": arrived})
			arrived_ids.append(id)
			_start_next_hop(f)
	# Capture is resolved in its OWN pass, only after every fleet's position for
	# THIS tick has already been settled above -- see _try_capture's docstring
	# for why doing it inline (in the same pass that's still moving fleets)
	# would let whichever fleet id sorts first win a race it should instead
	# lose to becoming a contact.
	for id in arrived_ids:
		_try_capture(state.fleets[id], state.fleets[id]["system"])
	return events


## Territory capture (issue #16): arriving at a system with no OPPOSING fleet
## currently there annexes it for the arriving fleet's side — peaceful if it
## was neutral/unowned, or a walk-in if the previous owner's fleet is gone.
## Deliberately checks live fleet PRESENCE, not state.system_owner, and
## deliberately run in its own pass AFTER every fleet's movement for this tick
## has already settled (see _advance_fleets above) — checking presence inline,
## in the same pass that's still processing arrivals in sorted-id order, would
## let whichever fleet id happens to sort first "arrive" and capture before a
## simultaneously-arriving OPPOSING fleet's own position update is even
## visible yet (its "system" field wouldn't be updated until its own turn
## later in that same loop) — a real race, not a hypothetical one, caught by
## tracing this through by hand: without the two-pass split, the
## alphabetically-first fleet id would silently win a capture race that should
## instead become a contact. With every arrival settled first, both fleets
## correctly see each other and neither captures — a same-system contact is
## what BattleBridge.detect_contact picks up right after step() returns.
##
## A multi-hop path's intermediate stops fire "arrived" too, so a fleet
## threading through several undefended systems on its way somewhere else
## auto-annexes all of them along the way — intentional, not an oversight.
func _try_capture(f: Dictionary, system_id: String) -> void:
	var side: int = f["side"]
	for other_id in state.fleets.keys():
		var other: Dictionary = state.fleets[other_id]
		if other["side"] != side and other["system"] == system_id:
			return
	state.system_owner[system_id] = side
