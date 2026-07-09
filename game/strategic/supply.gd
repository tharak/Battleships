extends RefCounted
class_name Supply
## Fleet supply meters, automated convoys, raiding (issue #13, GDD §4.4 — "the
## heart of the strategic-military game"). Pure functions queried/applied each
## tick by strategic_sim.gd, same pattern as the battle layer's Combat/Morale.
##
## Every fleet has a supply meter (0-100). It refills instantly (fast, toward
## 100) while sitting in a system its own side owns — GDD's "friendly planets/
## fortresses in the same system." Elsewhere, it depends on a CONVOY route
## computed fresh each tick: the fewest-hops path from the nearest system this
## side owns to the fleet, staying entirely within owned territory except at
## the fleet's own (possibly contested/enemy) system itself. Each hop costs 20%
## throughput (GDD: "each lane hop -20%"); an enemy fleet parked at any system
## along that route intercepts a further share of it ("commerce raiding is a
## real strategy"). If no such route exists at all — the chain is broken by
## enemy-held territory somewhere in between — throughput is zero and the fleet
## just drains: "deep offensives therefore starve unless you secure the whole
## chain."
##
## Scope note: every owned system currently grants unconditional full instant
## resupply, which is already exactly what GDD calls "superdepot" behavior —
## there's no depletable local-stockpile resource yet to make an ordinary
## system meaningfully different from a fortress (that needs the materiel/
## shipyard economy, issue #15). A real fortress-vs-ordinary distinction is
## deferred until that groundwork exists, not silently dropped.
##
## Also deliberately NOT modeled as literal traveling convoy objects visible on
## the map (GDD's prose describes them that way) — an abstract per-tick
## throughput calculation produces the same observable rules (falloff, cutoff,
## raiding) without a second simulated-entity type; nothing in the showable
## outcome ("cutting a supply lane visibly starves an advancing fleet") needs
## a convoy sprite crawling along the lane.

const HOP_FALLOFF := 0.8        # -20% throughput per lane hop (GDD §4.4)
const RAIDER_INTERCEPT := 0.5   # further multiplier per enemy fleet parked on the route
const EXISTING_DRAIN := 2.0     # supply/tick lost just from existing
const MOVING_DRAIN := 3.0       # ADDITIONAL supply/tick lost while traveling
const FRIENDLY_REGEN := 20.0    # supply/tick gained in owned territory (fast, "instant")
const CONVOY_REGEN := 10.0      # supply/tick gained at full (undiminished) convoy throughput


## Fewest-hops path from the nearest system `side` owns to `to`, staying within
## owned territory except at `to` itself — multi-source BFS seeded from every
## owned system at once. Returns the hop sequence AFTER the source (matching
## Galaxy.shortest_path's convention), or [] if no such route exists at all.
static func owned_hop_path(state: StrategicState, side: int, to: String) -> Array[String]:
	if state.system_owner.get(to, -1) == side:
		return []
	var dist := {}
	var prev := {}
	var queue: Array[String] = []
	for id in Galaxy.SYSTEMS.keys():
		if state.system_owner.get(id, -1) == side:
			dist[id] = 0
			queue.append(id)
	var qi := 0
	while qi < queue.size():
		var cur: String = queue[qi]
		qi += 1
		if cur == to:
			continue  # don't route a convoy onward past its own destination
		for n in Galaxy.neighbors(cur):
			if dist.has(n):
				continue
			var owner: int = state.system_owner.get(n, -1)
			if n != to and owner != side and owner != -1:
				continue  # blocked only by ENEMY-held territory (GDD's "contested or
				          # rebel systems") -- neutral/unclaimed ground is still a
				          # "friendly lane" a convoy can cross, just not a safe harbor
			dist[n] = dist[cur] + 1
			prev[n] = cur
			queue.append(n)
	if not dist.has(to):
		return []
	var path: Array[String] = []
	var node := to
	while dist[node] > 0:
		path.push_front(node)
		node = prev[node]
	return path


## Fraction (0-1) of full throughput actually reaching `fleet_id` right now.
static func throughput(state: StrategicState, fleet_id: String) -> float:
	var f: Dictionary = state.fleets[fleet_id]
	var side: int = f["side"]
	var here: String = f["system"]
	if state.system_owner.get(here, -1) == side:
		return 1.0
	var path := owned_hop_path(state, side, here)
	if path.is_empty():
		return 0.0
	var t: float = pow(HOP_FALLOFF, path.size())
	for id in path:
		for fid in state.fleets.keys():
			var other: Dictionary = state.fleets[fid]
			if other["side"] != side and other["system"] == id and other["dest"] == null:
				t *= RAIDER_INTERCEPT
	return t


## One tick's worth of drain/regen for one fleet, applied in place.
static func advance(state: StrategicState, fleet_id: String) -> void:
	var f: Dictionary = state.fleets[fleet_id]
	var t := throughput(state, fleet_id)
	var net: float
	if t >= 1.0:
		net = FRIENDLY_REGEN
	else:
		var drain := EXISTING_DRAIN + (MOVING_DRAIN if f["dest"] != null else 0.0)
		net = t * CONVOY_REGEN - drain
	f["supply"] = clampf(f["supply"] + net, 0.0, 100.0)
