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
	apply_due_commands(stream)
	var events := _advance_fleets()
	_advance_planets()
	_advance_rebellion()
	_advance_supply()
	_advance_economy()
	_advance_removal()
	state.tick += 1
	return events


## Applies whatever commands are due at the CURRENT tick without advancing
## simulated time at all. step() already does exactly this as its first move
## (so factoring it out here is a zero-behavior-change refactor for every
## existing caller — tests, run_stream(), determinism/replay all still see
## identical results) — exposed standalone so a caller can apply a
## freshly-issued order immediately even while time itself isn't advancing.
## strategic_map.gd calls this every frame regardless of pause state, so
## giving an order (set_policy, order_move) while paused takes visible effect
## right away instead of sitting inertly in the stream until the player
## unpauses. Safe to call repeatedly with nothing new recorded:
## StrategicCommandStream.due() is a consuming cursor, never replays the same
## command twice.
func apply_due_commands(stream: StrategicCommandStream) -> void:
	for cmd in stream.due(state.tick):
		_apply(cmd)


## Issue #17: policy drift/growth for every planet, settled BEFORE _advance_economy
## so this tick's taxation/conscription changes are what Shipyard.accrue actually
## reads (same "read the current tick's outcome, not last tick's" ordering already
## used throughout this function).
func _advance_planets() -> void:
	var ids := state.planets.keys()
	ids.sort()
	for id in ids:
		Planet.advance(state, id)


## Issue #18: threshold escalation (strikes/riots/rebellion) and siege/retake,
## settled right after _advance_planets so this tick's freshly-drifted unrest
## (and any fresh rebellion/retake) is what _advance_economy actually reads.
func _advance_rebellion() -> void:
	var ids := state.planets.keys()
	ids.sort()
	for id in ids:
		Rebellion.advance(state, id)


func _advance_supply() -> void:
	var ids := state.fleets.keys()
	ids.sort()
	for id in ids:
		Supply.advance(state, id)


## Issue #22: Shipyard.accrue returns each side's RAW tick revenue (before the
## budget split -- it already only credited state.materiel with the military
## share); Politics.advance is what spends the private/public shares.
## Deliberately driven by state.politics.keys() (a fixed side list), NOT
## revenue.keys() -- accrue()'s returned dict only contains a side that
## currently owns at least one system, so looping over IT would silently
## freeze a fully-conquered realm's seat satisfaction forever instead of
## correctly drifting it toward the (zero-revenue) unhappy target it should
## have. This is the same *shape* of bug issue #16 already taught this
## codebase once (a hardcoded/incomplete side loop starving a 3rd realm of a
## per-tick effect) -- caught by a design review before it shipped this time.
func _advance_economy() -> void:
	var revenue := Shipyard.accrue(state)
	var ids := state.fleets.keys()
	ids.sort()
	for id in ids:
		Shipyard.rebuild(state, id)
	for side in state.politics.keys():
		Politics.advance(state, side, revenue.get(side, 0.0))


## Issue #23: removal-crisis escalation, settled right after _advance_economy
## so this reads that same tick's freshly-drifted Politics.advance output.
## Fixed side list (state.politics.keys()), same #16/#22 lesson already
## learned twice -- a side reduced to zero systems still has politics that
## must keep evolving, not freeze.
func _advance_removal() -> void:
	for side in state.politics.keys():
		Removal.advance(state, side)


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
		"set_policy":
			if state.planets.has(a["system"]):
				var p: Dictionary = state.planets[a["system"]]
				var field: String = a["field"]
				if field == "garrison":
					p["garrison"] = clampf(float(a["value"]), 0.0, p["manpower"])
				else:
					p[field] = String(a["value"])
		"set_budget":
			if state.politics.has(a["side"]):
				var military: float = maxf(0.0, float(a["military"]))
				var private: float = maxf(0.0, float(a["private"]))
				var public: float = maxf(0.0, float(a["public"]))
				var total := military + private + public
				# Issue #22: a design review flagged this exact guard -- three
				# independent floats (unlike set_policy's single enum value)
				# can drift out of summing to 1.0, and dividing by a
				# degenerate all-zero/negative-clamped total would silently
				# produce NaN, which is sticky under addition and would
				# permanently wreck this realm's state.materiel the next time
				# Shipyard.accrue multiplies by it. Reject the command
				# instead (keep the prior split) rather than ever normalize
				# a zero-sum input.
				if total <= 0.0:
					return
				var pol: Dictionary = state.politics[a["side"]]
				pol["budget_military"] = military / total
				pol["budget_private"] = private / total
				pol["budget_public"] = public / total
		"set_regime_action":
			# Issue #24: dispatch to the matching Regime.* function, which owns
			# its own precondition guards (W bounds, instability cooldown) and
			# returns bool -- intentionally discarded here, same "no player-
			# visible rejection feedback" convention every other command already
			# follows (e.g. an out-of-bounds garrison adjustment above).
			var side: int = a["side"]
			match String(a["action"]):
				"purge":
					Regime.purge(state, side)
				"broaden":
					Regime.broaden(state, side)
				"expand_franchise":
					Regime.expand_franchise(state, side)
				"restrict_franchise":
					Regime.restrict_franchise(state, side)


## Pops the next hop off `f["path"]` into `f["dest"]`, resetting progress — or
## clears `dest` (holds position) once the path is exhausted. Static (doesn't
## touch `self.state`) so battle_bridge.gd's post-battle retreat can reuse it
## on a fleet dict without needing a StrategicSim instance.
static func _start_next_hop(f: Dictionary) -> void:
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
##
## Issue #18: a REBEL_SIDE-owned system is deliberately EXCLUDED from this
## peaceful walk-in — without this, any arriving fleet (a final destination OR
## an intermediate hop) would instantly annex it for free, bypassing the whole
## siege mechanic (and could even flicker straight back to REBEL_SIDE the same
## tick once _advance_rebellion runs and still sees unrest >= 90). Retaking a
## rebel system can ONLY happen through Rebellion._advance_siege.
func _try_capture(f: Dictionary, system_id: String) -> void:
	if state.system_owner.get(system_id, -1) == Rebellion.REBEL_SIDE:
		return
	var side: int = f["side"]
	for other_id in state.fleets.keys():
		var other: Dictionary = state.fleets[other_id]
		if other["side"] != side and other["system"] == system_id:
			return
	state.system_owner[system_id] = side
