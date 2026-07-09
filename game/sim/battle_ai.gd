extends RefCounted
class_name BattleAI
## Opponent AI (issue #10, GDD §11 risk register: "sub-commander system doubles as
## AI framework"). Not a new Sim mechanic — this is exactly the kind of external
## controller main.gd already is for the human player: it reads live Sim state and
## queues Commands into the stream at its own decision cadence. It never pokes
## squadron state directly (GDD §11's "no direct UI-to-sim pokes" applies to the AI
## exactly as much as to the player) and needs no Sim-side changes at all — call
## `act()` once per tick (same spot main.gd calls _sync_3d_visuals/_update_label),
## right before Sim.step() so a command timestamped at the current tick is picked
## up by that same step() call (CommandStream.due uses "<=", see command_stream.gd).
##
## One fleet-wide posture, re-evaluated every DECISION_PERIOD_TICKS — a commander
## doesn't re-issue orders every 0.1s; this cadence IS the AI's reaction time. Reuses
## the sub-commander order vocabulary (GDD §5.6: hold/screen/pursue) as its own
## action space, read for a single AI fleet with no wings/sub-commanders yet:
##   HOLD     — advance steadily on the enemy's centroid in Line, once outside
##              Combat.RANGE; once engaged, stop reissuing orders and let the guns
##              do the talking instead of fidgeting every decision tick.
##   ADVANCE  — "seeks flanks": a real opening exists (one lateral half of the
##              enemy formation holds meaningfully less strength than the other) —
##              swing into Crescent aimed at that weak side, standing off enough to
##              arrive on their flank/rear rather than walking into their front arc.
##              This is "pursue" a spotted opening.
##   WITHDRAW — "withdraws when losing": own/enemy total strength has dropped below
##              WITHDRAW_RATIO — fall back toward the AI's own edge in Column
##              (travel order). Sticky until strength recovers past RALLY_RATIO
##              (hysteresis — the same "don't flip-flop every decision" reasoning
##              as Morale's ROUT/RALLY threshold gap), i.e. "screen and fall back".
##
## Showable outcome (the issue's own bar): beats a careless player, loses to a good
## flank — tests/test_battle_ai.gd plays out both scenarios against this exact
## policy end to end, not just the individual decision functions in isolation.

const DECISION_PERIOD_TICKS := 30   # ~3 sim-seconds between re-plans
const WITHDRAW_RATIO := 0.5         # own/enemy strength below this -> retreat
const RALLY_RATIO := 0.8            # recovers above this -> stop retreating
const FLANK_STRENGTH_RATIO := 0.75  # weaker-side/stronger-side strength below this
                                     # counts as "a real opening", not sensor noise
const SLOT_SPACING := 30.0          # matches main.gd's player-formation spacing
const HOLD_ADVANCE_STEP := 80.0     # how far to creep forward per Hold re-plan
const WITHDRAW_STEP := 150.0        # how far to fall back per Withdraw re-plan
const FLANK_LATERAL_OFFSET := 120.0 # how far past the enemy's weak edge to aim
const APPROACH_STANDOFF := 60.0     # stand this far short of the enemy's centroid
                                     # along their own forward axis, so the advance
                                     # still reads as an attack run on the flank/
                                     # rear, not a walk straight into their front

var _side: int
var _next_decision_tick := 0
var _posture := "hold"  # sticky between decisions -- see RALLY_RATIO's hysteresis


func _init(side: int) -> void:
	_side = side


func act(state: BattleState, stream: CommandStream) -> void:
	if state.tick < _next_decision_tick:
		return
	_next_decision_tick = state.tick + DECISION_PERIOD_TICKS

	var own := _living(state.squadrons, _side)
	var enemy := _living(state.squadrons, 1 - _side)
	if own.is_empty() or enemy.is_empty():
		return  # nothing left to give orders to, or nothing left to fight

	var own_strength := _total_strength(state.squadrons, own)
	var enemy_strength := _total_strength(state.squadrons, enemy)
	var ratio: float = float(own_strength) / float(enemy_strength) if enemy_strength > 0 else INF

	if ratio < WITHDRAW_RATIO:
		_posture = "withdraw"
	elif _posture == "withdraw" and ratio < RALLY_RATIO:
		pass  # not recovered enough yet -- keep withdrawing (hysteresis)
	else:
		_posture = "advance" if _has_flank_opening(state.squadrons, enemy) else "hold"

	match _posture:
		"withdraw":
			_order_withdraw(state, stream, own, enemy)
		"advance":
			_order_advance(state, stream, own, enemy)
		"hold":
			_order_hold(state, stream, own, enemy)


static func _living(squadrons: Dictionary, side: int) -> Array[String]:
	var out: Array[String] = []
	var ids := squadrons.keys()
	ids.sort()
	for id in ids:
		if squadrons[id]["side"] == side:
			out.append(id)
	return out


static func _total_strength(squadrons: Dictionary, ids: Array[String]) -> int:
	var total := 0
	for id in ids:
		total += int(squadrons[id]["strength"])
	return total


static func _centroid(squadrons: Dictionary, ids: Array[String]) -> Vector2:
	var c := Vector2.ZERO
	for id in ids:
		c += squadrons[id]["pos"]
	return c / ids.size()


## Circular mean of facings -- same technique main.gd's _apply_formation uses.
static func _mean_facing(squadrons: Dictionary, ids: Array[String]) -> float:
	var sum := Vector2.ZERO
	for id in ids:
		sum += Vector2.RIGHT.rotated(deg_to_rad(float(squadrons[id]["facing"])))
	return rad_to_deg(sum.angle())


## Splits a fleet's total strength into "left"/"right" of its own forward axis —
## the fleet's own mean facing is what defines its flanks in the first place.
static func _flank_split(squadrons: Dictionary, ids: Array[String]) -> Dictionary:
	var centroid := _centroid(squadrons, ids)
	var fwd := Vector2.RIGHT.rotated(deg_to_rad(_mean_facing(squadrons, ids)))
	var lateral := fwd.rotated(PI / 2.0)
	var left := 0
	var right := 0
	for id in ids:
		var rel: Vector2 = (squadrons[id]["pos"] as Vector2) - centroid
		if rel.dot(lateral) < 0.0:
			left += int(squadrons[id]["strength"])
		else:
			right += int(squadrons[id]["strength"])
	return {"left": left, "right": right}


## "Seeks flanks": only commit to a flank attack when there's an actual meaningful
## opening, not on every single decision tick regardless of the enemy's shape.
static func _has_flank_opening(squadrons: Dictionary, enemy: Array[String]) -> bool:
	var split := _flank_split(squadrons, enemy)
	var weak: int = mini(split["left"], split["right"])
	var strong: int = maxi(split["left"], split["right"])
	return strong > 0 and float(weak) / float(strong) < FLANK_STRENGTH_RATIO


static func _issue_formation(state: BattleState, stream: CommandStream, ids: Array[String],
		name: String, anchor: Vector2, facing_deg: float) -> void:
	var orders := Formations.assign_orders(state.squadrons, ids, name, anchor, facing_deg, SLOT_SPACING)
	for id in ids:
		var o: Dictionary = orders[id]
		stream.record(Commands.make(state.tick, "order_move", {
			"id": id, "target": Commands.pos_to_array(o["target"]), "face": o["face"],
		}))


static func _order_hold(state: BattleState, stream: CommandStream, own: Array[String], enemy: Array[String]) -> void:
	var own_c := _centroid(state.squadrons, own)
	var enemy_c := _centroid(state.squadrons, enemy)
	if own_c.distance_to(enemy_c) <= Combat.RANGE:
		return  # already engaged -- let the guns do the talking, don't fidget
	var toward: Vector2 = (enemy_c - own_c).normalized()
	var anchor := own_c + toward * HOLD_ADVANCE_STEP
	_issue_formation(state, stream, own, "line", anchor, rad_to_deg(toward.angle()))


static func _order_advance(state: BattleState, stream: CommandStream, own: Array[String], enemy: Array[String]) -> void:
	var enemy_c := _centroid(state.squadrons, enemy)
	var fwd := Vector2.RIGHT.rotated(deg_to_rad(_mean_facing(state.squadrons, enemy)))
	var lateral := fwd.rotated(PI / 2.0)
	var split := _flank_split(state.squadrons, enemy)
	var weak_side: float = -1.0 if split["left"] < split["right"] else 1.0
	var anchor := enemy_c + lateral * weak_side * FLANK_LATERAL_OFFSET - fwd * APPROACH_STANDOFF
	var facing := (enemy_c - anchor).angle()
	_issue_formation(state, stream, own, "crescent", anchor, rad_to_deg(facing))


static func _order_withdraw(state: BattleState, stream: CommandStream, own: Array[String], enemy: Array[String]) -> void:
	var own_c := _centroid(state.squadrons, own)
	var enemy_c := _centroid(state.squadrons, enemy)
	var away: Vector2 = (own_c - enemy_c)
	away = away.normalized() if away.length() > 1.0 else Vector2.RIGHT
	var anchor := own_c + away * WITHDRAW_STEP
	_issue_formation(state, stream, own, "column", anchor, rad_to_deg(away.angle()))
