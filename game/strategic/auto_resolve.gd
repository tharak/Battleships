extends RefCounted
class_name AutoResolve
## Auto-resolve calculator (issue #14, GDD §5.9): "any battle can be auto-
## resolved with a supply/strength/commander-weighted calculator, tuned
## slightly worse than decent manual play — playing battles should feel
## rewarding, never mandatory." Also used for AI-vs-AI battles between rival
## successor states. Weighs strength, adjusted by the same supply→uptime
## multiplier battle-seeding applies (BattleBridge.tactical_modifiers), so a
## starved fleet auto-resolves worse too, not just in a fought battle — and,
## since issue #25, an optional commander-tactics multiplier too (see
## `tactics` below) — GDD's own "commander-weighted" wording, closing a gap
## this file's docstring used to flag as unbuilt.
##
## Deliberately a simple, hand-tunable model rather than literally re-running a
## fast/headless tactical sim: GDD explicitly wants this to feel worse than
## actually playing (MANUAL_PLAY_ADVANTAGE), which a faithful re-simulation
## wouldn't reliably guarantee on its own.

## The winner's survivors are reduced by this fraction ON TOP OF their natural
## losses — "tuned slightly worse than decent manual play" (GDD §5.9). A human
## fighting the fleet battle out well could reasonably do better than this.
const MANUAL_PLAY_ADVANTAGE := 0.15

## Sentinel default, NOT Roster.BASELINE_TACTICS itself: a cross-class
## constant as a static function's own DEFAULT PARAMETER VALUE has no
## existing precedent in this codebase and is unverified at parse time,
## whereas resolving a sentinel inside the function body is guaranteed safe
## (existing precedent: strategic_sim.gd's `a.get("preset", FleetPresets.
## DEFAULT)` is a runtime default, a different mechanism). Every existing
## call site (strategic_ai.gd's two, every test) omits this param entirely
## and is completely unaffected.
const _NO_TACTICS := -1.0


static func effective_power(strength: int, supply: float, tactics: float = _NO_TACTICS) -> float:
	var tactics_mult := Roster.tactics_uptime_mult(tactics if tactics >= 0.0 else Roster.BASELINE_TACTICS)
	return float(strength) * float(BattleBridge.tactical_modifiers(supply)["uptime_mult"]) * tactics_mult


## Returns {"winner": int (0, 1, or -1 for a perfectly even wipeout), "a_left":
## int, "b_left": int} — survivor strength for each side after an auto-resolved
## engagement between (strength_a, supply_a) and (strength_b, supply_b).
## `tactics_a`/`tactics_b` (issue #25): each side's assigned commander's
## tactics stat, or omitted entirely to preserve every pre-#25 call site's
## exact behavior (defaults to no commander-quality adjustment at all).
static func resolve(strength_a: int, supply_a: float, strength_b: int, supply_b: float,
		tactics_a: float = _NO_TACTICS, tactics_b: float = _NO_TACTICS) -> Dictionary:
	var power_a := effective_power(strength_a, supply_a, tactics_a)
	var power_b := effective_power(strength_b, supply_b, tactics_b)
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
