extends RefCounted
class_name Sim
## The only mutation path for battle state (GDD §11: "all sim mutations flow through
## serialized commands from day one — no direct UI-to-sim pokes"). Fixed-tick, single
## seeded RNG.
##
## Movement & facing (GDD §5.1-5.2, issue #4): a squadron always turns toward its
## `desired_facing` at a limited rate; while it has a move `target`, desired_facing
## tracks the bearing to that target and it advances along its own nose once roughly
## facing it. Cohesion drops while turning hard and regenerates while holding a
## steady course — "formation integrity drops when maneuvering hard" (GDD §5.2).

const TICKS_PER_SEC := 10
const SPEED := 6.0            # plane units / sim-second
const TURN_RATE := 60.0       # degrees / sim-second
const ARRIVE_EPS := 0.05      # snap to target within this distance
const FACE_TOLERANCE := 15.0  # must be within this many degrees of desired_facing to move
const COHESION_TURN_COST := 0.6   # cohesion lost per degree turned
const COHESION_REGEN := 15.0      # cohesion regained per second while not turning

## Map border: a squadron that ends up outside this box escapes the battle
## entirely (see _advance_border). Sized to comfortably contain the demo's
## spawn/engagement geometry (player/enemy anchors ~320 units apart, both well
## inside Combat.RANGE=220 of the box's own margins) while still being
## reachable by a determined retreat in real playtime — the nearest edge from
## the middle of a typical engagement is roughly 300-400 units away, which is
## tens of seconds at a routed squadron's flee speed (SPEED * Morale.
## FLEE_SPEED_MULT ≈ 13.2/sec), not an unreachable horizon.
const BORDER_MIN := Vector2(0.0, 0.0)
const BORDER_MAX := Vector2(1000.0, 640.0)

var state: BattleState


func _init(seed_value: int) -> void:
	state = BattleState.new(seed_value)


## Advance exactly one tick: apply commands due this tick, then kinematics, the
## map border, combat, morale. Never call anything else to mutate state — this
## is the determinism contract. Returns this tick's events (escapes/hits/
## destructions/routs/rallies) so a caller like main.gd can render them without
## re-deriving them; nothing inside Sim itself depends on the return value.
func step(stream: CommandStream) -> Array:
	for cmd in stream.due(state.tick):
		_apply(cmd)
	var dt := 1.0 / TICKS_PER_SEC
	_advance_kinematics(dt)
	var escape_events := _advance_border()
	var combat_events := _advance_combat(dt)
	var morale_events := _advance_morale(dt, combat_events, escape_events)
	state.tick += 1
	return escape_events + combat_events + morale_events


func run_stream(stream: CommandStream, ticks: int) -> void:
	stream.reset_cursor()
	for i in range(ticks):
		step(stream)


func _apply(cmd: Dictionary) -> void:
	var a: Dictionary = cmd["a"]
	match cmd["k"]:
		"spawn":
			# Explicit int()/float()/bool() casts: JSON round-tripping a recorded
			# stream can hand back numbers as a different numeric type than what was
			# recorded — left uncast, that silently changes the canonical hash after
			# a replay (see the test suite's record->replay assertion).
			var facing := float(a["facing"])
			state.squadrons[a["id"]] = {
				"side": int(a["side"]),
				"pos": Commands.array_to_pos(a["pos"]),
				"facing": facing,
				"desired_facing": facing,
				"strength": int(a["strength"]),
				"flag": bool(a["flag"]),
				"target": null,
				"arrive_facing": null,
				"cohesion": 100.0,
				"dmg_accum": 0.0,
				"morale": state.fleets[int(a["side"])]["morale_cap"],
				"routed": false,
			}
		"order_move":
			# Routed squadrons ignore orders entirely (GDD §5.5) — they're fleeing on
			# their own autopilot (see _advance_flee) until they rally.
			if state.squadrons.has(a["id"]) and not state.squadrons[a["id"]]["routed"]:
				var sq: Dictionary = state.squadrons[a["id"]]
				sq["target"] = Commands.array_to_pos(a["target"])
				# Always overwrite (never leave a stale facing goal from an earlier
				# order): absent "face" means "arrive and hold whatever heading
				# travel left you with", same as before this field existed.
				sq["arrive_facing"] = Geometry.normalize_angle(float(a["face"])) if a.has("face") else null
		"order_face":
			if state.squadrons.has(a["id"]) and not state.squadrons[a["id"]]["routed"]:
				var sq: Dictionary = state.squadrons[a["id"]]
				sq["target"] = null
				sq["desired_facing"] = Geometry.normalize_angle(float(a["facing"]))
		"spawn_terrain":
			state.terrain[a["id"]] = {
				"kind": String(a["kind"]),
				"pos": Commands.array_to_pos(a["pos"]),
				"radius": float(a["radius"]),
			}


func _advance_kinematics(dt: float) -> void:
	var ids := state.squadrons.keys()
	ids.sort()
	for id in ids:
		var sq: Dictionary = state.squadrons[id]
		if sq["routed"]:
			_advance_flee(sq, dt)
			continue

		var target = sq.get("target")

		if target != null:
			sq["desired_facing"] = Geometry.angle_between(sq["pos"], target)

		var before: float = sq["facing"]
		var after: float = Geometry.turn_toward(before, sq["desired_facing"], TURN_RATE * dt)
		var turned: float = abs(Geometry.normalize_angle(after - before))
		sq["facing"] = after

		if turned > 0.0001:
			sq["cohesion"] = maxf(0.0, sq["cohesion"] - COHESION_TURN_COST * turned)
		else:
			sq["cohesion"] = minf(100.0, sq["cohesion"] + COHESION_REGEN * dt)

		if target == null:
			continue

		var to_target: Vector2 = target - sq["pos"]
		var dist: float = to_target.length()
		if dist <= ARRIVE_EPS:
			sq["pos"] = target
			sq["target"] = null
			if sq["arrive_facing"] != null:
				sq["desired_facing"] = sq["arrive_facing"]
			continue

		if Geometry.rel_angle(sq["facing"], sq["pos"], target) <= FACE_TOLERANCE:
			# Move straight toward the target (not strictly along `facing`, which is
			# only guaranteed within FACE_TOLERANCE) so distance-to-target shrinks
			# monotonically every tick and arrival is guaranteed to converge cleanly.
			# Asteroid fields slow movement (issue #9, GDD §5.7) — checked at the
			# squadron's current position, not the target, so a squadron already
			# inside a field is slowed on the way out just as much as on the way in.
			var speed: float = SPEED * Terrain.speed_mult(sq["pos"], state.terrain)
			var step_dist: float = minf(speed * dt, dist)
			sq["pos"] = sq["pos"] + to_target.normalized() * step_dist


## Routed autopilot (issue #7, GDD §5.5): ignores any standing order and runs
## directly away from the nearest enemy — adapted from the paper prototype's "faces
## its own map edge", since this continuous engine has no fixed deployment edge to
## flee toward, and "away from the nearest threat" is the more robust reading of the
## same intent anyway (a fixed edge could point straight at a different enemy).
## Cohesion collapses unconditionally while routed, on top of whatever the turning
## itself already costs — a rout should look and feel like a structural collapse.
## Moves at Morale.FLEE_SPEED_MULT the normal pace ("spend all MP fleeing", paper §6,
## read as an all-out panic run rather than tactical repositioning).
##
## Facing snaps instantly to the flee direction instead of being TURN_RATE-limited
## like every other order — "immediately faces its own map edge" (paper §6) is read
## literally, not as "starts turning toward it". This isn't just flavor: a squadron
## that had just routed while facing its attacker needs close to a full 180° turn,
## which at TURN_RATE takes ~30 ticks — and it spends that whole window still
## showing flank/rear to the enemy that just broke it, unable to take a single step
## in the meantime (movement requires being within FACE_TOLERANCE of the heading).
## Empirically (tested against the real demo scenario, not just isolated scripted
## fights) that reliably killed the squadron before it moved at all, no matter how
## much morale/speed tuning was applied on top — turning "the loser escapes with a
## mauled fleet" (GDD §5.5) into annihilation regardless. A panicked crew doesn't
## execute a smooth helm turn; they scatter and run.
func _advance_flee(sq: Dictionary, dt: float) -> void:
	var nearest = Combat.nearest_enemy_pos(sq, state.squadrons)
	sq["cohesion"] = maxf(0.0, sq["cohesion"] - Morale.ROUT_COHESION_DRAIN * dt)
	if nearest != null:
		sq["desired_facing"] = Geometry.normalize_angle(Geometry.angle_between(nearest, sq["pos"]))
		sq["facing"] = sq["desired_facing"]
	if nearest == null:
		return  # nothing left to flee from — hold position
	# Facing was just snapped exactly to desired_facing above, so there's no
	# FACE_TOLERANCE gate to check here (unlike normal orders) — a routed squadron
	# always moves.
	var heading := deg_to_rad(sq["facing"])
	var speed: float = SPEED * Morale.FLEE_SPEED_MULT * Terrain.speed_mult(sq["pos"], state.terrain)
	sq["pos"] = sq["pos"] + Vector2(cos(heading), sin(heading)) * speed * dt


## Map border: a squadron whose position ends up outside BORDER_MIN/BORDER_MAX
## after this tick's movement escapes the battle entirely — removed from play,
## its strength (and a unit count, for the HUD) credited to its own side's
## escaped_strength/escaped_count tallies (main.gd reads these back for the
## strategic write-back, or just "how many got away" bookkeeping in a
## standalone skirmish). Checked right after kinematics and BEFORE combat, so
## an escaping squadron doesn't get one last exchange of fire in on its way
## out.
##
## Applies uniformly regardless of routed state or side — a deliberate player
## order past the border is just as valid an escape as a routed squadron's
## autopilot flee carrying it there, and the AI's own WITHDRAW posture
## (battle_ai.gd) can now genuinely walk a losing fleet off the map for real,
## no special-casing needed for either. Deliberately free — no delay, no
## partial-strength cost — a real way to decline or break off a losing fight
## through maneuver, not an oversight to close.
##
## An escaping FLAGSHIP is flagged here; _advance_morale is what actually
## applies the same flagship_lost penalty/shock a destroyed flagship gets
## (just not the nearby-friendlies contagion a kill causes — see its
## docstring). Without that, fleeing the flagship first would be a strictly
## dominant, free tactic: Command.flagship_pos already treats "no living
## squadron with flag=true" as command lost the instant it's gone from
## state.squadrons, escaped or destroyed alike, so skipping the flagship_lost
## fork here would let a losing side dodge the permanent regen penalty and
## one-time shock a real flagship death costs, for free, just by fleeing it
## instead of losing it.
func _advance_border() -> Array:
	var events := []
	var ids := state.squadrons.keys()
	ids.sort()
	for id in ids:
		var sq: Dictionary = state.squadrons[id]
		var pos: Vector2 = sq["pos"]
		if pos.x < BORDER_MIN.x or pos.x > BORDER_MAX.x or pos.y < BORDER_MIN.y or pos.y > BORDER_MAX.y:
			var side: int = sq["side"]
			var was_flag: bool = sq["flag"]
			state.fleets[side]["escaped_strength"] += int(sq["strength"])
			state.fleets[side]["escaped_count"] += 1
			state.squadrons.erase(id)
			events.append({"type": "escaped", "id": id, "side": side, "flag": was_flag, "pos": pos})
	return events


## Beam combat (issue #5): each squadron with a legal target (Combat.pick_target)
## deals continuous damage every tick. Firer and target are both read from live state
## (not a start-of-tick snapshot) — a squadron already hit earlier this same tick by
## another firer is simply weaker for the rest of the tick, which is correct, not a
## bug: within one tick, order is squadron-id order, same as every other pass here.
func _advance_combat(dt: float) -> Array:
	var events := []
	var ids := state.squadrons.keys()
	ids.sort()
	for firer_id in ids:
		if not state.squadrons.has(firer_id):
			continue  # destroyed earlier this same pass
		var firer: Dictionary = state.squadrons[firer_id]
		# Issue #14, GDD §5.8: a starved fleet's weapon uptime is reduced strategic-
		# side, applied here as a flat multiplier on top of the morale-driven one —
		# a wavering AND starving squadron gets both penalties, not just the worse one.
		var fire_mult := Morale.fire_multiplier(firer) * float(state.fleets[firer["side"]]["uptime_mult"])
		if fire_mult <= 0.0:
			continue  # routed: cannot fire at all (GDD §5.5)
		var target_id := Combat.pick_target(firer_id, firer, state.squadrons, state.terrain)
		if target_id == "":
			continue
		var target: Dictionary = state.squadrons[target_id]
		var dmg: float = Combat.damage_this_tick(firer, target, fire_mult, dt)
		var arc := Combat.target_arc(firer["pos"], target)
		target["dmg_accum"] += dmg
		var whole := floori(target["dmg_accum"])
		if whole > 0:
			target["dmg_accum"] -= whole
			target["strength"] = maxi(0, target["strength"] - whole)
		events.append({"type": "hit", "firer": firer_id, "target": target_id, "arc": arc,
			"dmg": dmg, "strength_lost": whole})
		if target["strength"] <= 0:
			var side: int = target["side"]
			var was_flag: bool = target["flag"]
			var pos: Vector2 = target["pos"]
			state.squadrons.erase(target_id)
			events.append({"type": "destroyed", "id": target_id, "side": side, "flag": was_flag, "pos": pos})
	return events


## Morale, waver, rout (issue #7): damage from this tick's combat drains morale
## (with a flank/rear surcharge); everyone else not hit this tick regenerates —
## that's the whole of "recovers when disengaged". Rout/rally transitions are
## checked after damage+regen settle, and a fresh rout fires contagion to nearby
## friendlies; a friendly's destruction this same tick does too, using the position
## the combat pass captured before erasing it. An escape (map border) does NOT
## trigger that contagion — "it got away" reads as better news than "it died",
## and a routing squadron already drained nearby allies' morale (NEARBY_ROUT_
## PENALTY) at the moment it routed, independent of what happens to it after —
## but an escaping FLAGSHIP still costs the fleet the same flagship_lost
## penalty/shock a destroyed one would (see _apply_flagship_lost and
## _advance_border's docstring for why).
## Command radius (issue #8): regen is boosted for squadrons within COMMAND_RADIUS of
## their side's living flagship, and permanently reduced fleet-wide once it's gone —
## on top of the immediate fleet-wide shock every survivor takes the instant it dies.
## Squadrons freshly hit by that shock have their rout transition checked next tick,
## not this one (transitions are checked once, earlier in this same function) — a
## one-tick (0.1s) detection delay on a shock-induced rout, not a correctness bug.
func _advance_morale(dt: float, combat_events: Array, escape_events: Array) -> Array:
	var events := []
	var hit_ids := {}
	for ev in combat_events:
		if ev["type"] == "hit" and state.squadrons.has(ev["target"]):
			Morale.apply_hit(state.squadrons[ev["target"]], ev["arc"], ev["strength_lost"])
			hit_ids[ev["target"]] = true

	var flagship_pos := [Command.flagship_pos(0, state.squadrons), Command.flagship_pos(1, state.squadrons)]

	var ids := state.squadrons.keys()
	ids.sort()
	for id in ids:
		if not hit_ids.has(id):
			var sq: Dictionary = state.squadrons[id]
			var in_command := Command.is_in_command(sq["pos"], flagship_pos[sq["side"]])
			var rate := Command.regen_rate(Morale.MORALE_REGEN, in_command, state.fleets[sq["side"]]["flagship_lost"])
			Morale.regen(sq, dt, rate, state.fleets[sq["side"]]["morale_cap"])

	for id in ids:
		if not state.squadrons.has(id):
			continue
		var sq: Dictionary = state.squadrons[id]
		var transition := Morale.check_transition(sq)
		if transition == "routed":
			events.append({"type": "routed", "id": id, "side": sq["side"]})
			for fid in Morale.contagion_targets(state.squadrons, sq["side"], sq["pos"], id):
				var f: Dictionary = state.squadrons[fid]
				f["morale"] = maxf(0.0, f["morale"] - Morale.NEARBY_ROUT_PENALTY)
		elif transition == "rallied":
			events.append({"type": "rallied", "id": id, "side": sq["side"]})

	for ev in combat_events:
		if ev["type"] != "destroyed":
			continue
		for fid in Morale.contagion_targets(state.squadrons, ev["side"], ev["pos"], ev["id"]):
			var f: Dictionary = state.squadrons[fid]
			f["morale"] = maxf(0.0, f["morale"] - Morale.NEARBY_DEATH_PENALTY)
		if ev["flag"]:
			events.append(_apply_flagship_lost(ev["side"]))

	for ev in escape_events:
		if ev["flag"]:
			events.append(_apply_flagship_lost(ev["side"]))

	return events


## Shared by a destroyed flagship (issue #8) and an escaped one (map border
## feature) — same permanent penalty and one-time shock either way, since
## Command.flagship_pos can't tell "dead" from "gone" apart and losing command
## costs the same regardless. Callers decide separately whether to ALSO run
## nearby-friendlies contagion (a kill does, an escape deliberately doesn't).
func _apply_flagship_lost(side: int) -> Dictionary:
	state.fleets[side]["flagship_lost"] = true
	for sid in state.squadrons.keys():
		var s: Dictionary = state.squadrons[sid]
		if s["side"] == side:
			s["morale"] = maxf(0.0, s["morale"] - Command.FLAGSHIP_LOST_SHOCK)
	return {"type": "flagship_lost", "side": side}
