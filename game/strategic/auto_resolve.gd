extends RefCounted
class_name AutoResolve
## Auto-resolve calculator (issue #14, GDD §5.9): "any battle can be auto-
## resolved with a supply/strength/commander-weighted calculator, tuned
## slightly worse than decent manual play — playing battles should feel
## rewarding, never mandatory." Also used for AI-vs-AI battles between rival
## successor states. No commander-quality stat exists yet (no commander/roster
## system built), so this weighs strength — adjusted by the same supply→uptime
## multiplier battle-seeding applies (BattleBridge.tactical_modifiers), so a
## starved fleet auto-resolves worse too, not just in a fought battle — only.
##
## Deliberately a simple, hand-tunable model rather than literally re-running a
## fast/headless tactical sim: GDD explicitly wants this to feel worse than
## actually playing (MANUAL_PLAY_ADVANTAGE), which a faithful re-simulation
## wouldn't reliably guarantee on its own.

## The winner's survivors are reduced by this fraction ON TOP OF their natural
## losses — "tuned slightly worse than decent manual play" (GDD §5.9). A human
## fighting the fleet battle out well could reasonably do better than this.
const MANUAL_PLAY_ADVANTAGE := 0.15


static func effective_power(strength: int, supply: float) -> float:
	return float(strength) * float(BattleBridge.tactical_modifiers(supply)["uptime_mult"])


## Returns {"winner": int (0, 1, or -1 for a perfectly even wipeout), "a_left":
## int, "b_left": int} — survivor strength for each side after an auto-resolved
## engagement between (strength_a, supply_a) and (strength_b, supply_b).
static func resolve(strength_a: int, supply_a: float, strength_b: int, supply_b: float) -> Dictionary:
	var power_a := effective_power(strength_a, supply_a)
	var power_b := effective_power(strength_b, supply_b)
	if power_a <= 0.0 and power_b <= 0.0:
		return {"winner": -1, "a_left": 0, "b_left": 0}

	var winner := 0 if power_a >= power_b else 1
	var winner_power: float = maxf(power_a, power_b)
	var loser_power: float = minf(power_a, power_b)
	# 0 = a total mismatch, 1 = a perfectly even fight -- how costly this was
	# for the winner, and how much the loser could still salvage.
	var closeness: float = loser_power / winner_power if winner_power > 0.0 else 0.0

	var winner_strength := strength_a if winner == 0 else strength_b
	var loser_strength := strength_b if winner == 0 else strength_a

	# An even fight (closeness=1) costs the loser ~60% of their strength and the
	# winner ~35% (worsened further by the manual-play tax); a total mismatch
	# (closeness=0) costs the loser everything and the winner almost nothing.
	var loser_left := int(round(loser_strength * closeness * 0.4))
	var winner_left := int(round(winner_strength * (1.0 - closeness * 0.35 * (1.0 + MANUAL_PLAY_ADVANTAGE))))

	var a_left := winner_left if winner == 0 else loser_left
	var b_left := loser_left if winner == 0 else winner_left
	return {"winner": winner, "a_left": maxi(a_left, 0), "b_left": maxi(b_left, 0)}
