extends RefCounted
class_name Command
## Flagship command radius (issue #8, GDD §5.6): units inside get a morale bonus and
## respond to orders immediately; outside, orders "take seconds to arrive" (order
## delay is implemented entirely in main.gd — see its _command_tick — by scheduling
## the recorded command a few ticks into the future when the squadron is out of
## command, which needs no Sim-side mechanic at all, the same trick issue #6 used for
## formation facing). If the flagship is destroyed, the fleet loses the morale bonus
## permanently (a harsher regen penalty, not a one-time hit) on top of the immediate
## fleet-wide shock every surviving squadron takes.
##
## Pure functions; Sim/main.gd own when to call them.

const COMMAND_RADIUS := 260.0
const IN_COMMAND_MORALE_BONUS := 3.0   # extra regen/sec while within radius of a living flagship
const FLAGSHIP_LOST_SHOCK := 30.0      # one-time morale hit, every surviving squadron, on flagship death
const FLAGSHIP_LOST_REGEN_PENALTY := 4.0  # permanent regen reduction for the rest of the battle
const ORDER_DELAY_TICKS := 20          # ~2s: "orders take seconds to arrive" outside command radius


## Position of `side`'s living flagship, or null if it has none (never spawned one,
## or it's been destroyed).
static func flagship_pos(side: int, squadrons: Dictionary):
	var ids := squadrons.keys()
	ids.sort()
	for id in ids:
		var sq: Dictionary = squadrons[id]
		if sq["side"] == side and sq["flag"]:
			return sq["pos"]
	return null


static func is_in_command(sq_pos: Vector2, flagship: Variant) -> bool:
	if flagship == null:
		return false
	return sq_pos.distance_to(flagship) <= COMMAND_RADIUS


## Morale regen rate for this tick: base rate, +bonus in command, -penalty if the
## fleet's flagship is gone — floored so it never goes negative.
static func regen_rate(base: float, in_command: bool, flagship_lost: bool) -> float:
	var rate := base
	if in_command:
		rate += IN_COMMAND_MORALE_BONUS
	if flagship_lost:
		rate -= FLAGSHIP_LOST_REGEN_PENALTY
	return maxf(0.0, rate)
