extends RefCounted
class_name Galaxy
## Hand-authored MVP galaxy (issue #12, GDD §4.1): "~40-60 star systems... MVP: ~12
## systems, 3 sectors" — no procedural generation yet (a later-phase concern; a
## fixed, legible map is enough to prove fleets moving under time controls).
## Pure data: SYSTEMS (id -> {pos, sector, owner}) and LANES (undirected pairs)
## describing the node graph fleets move over (strategic_sim.gd). Each sector is a
## hub-and-spoke cluster of 4 systems; sectors connect to each other through a
## single lane each — "funneling through fortress chokepoints" (GDD §4.1), though
## the fortress mechanic itself is a later issue (GDD §5.7).
##
## Sector A (west) is the player's realm (side 0), Sector B (center) and Sector C
## (east) are two independent AI realms (sides 1 and 2 — issue #16, GDD's Phase 2
## spec: "3 sectors (player + 2 dumb AI realms)"). Only two inter-sector lanes exist
## (A-B, B-C — no direct A-C lane), so Sector B is structurally the only realm
## bordering both others, a "squeezed middle power" that falls out of the existing
## topology for free rather than needing a bespoke map redesign.

const SYSTEMS := {
	"A1": {"pos": Vector2(120, 300), "sector": "A", "owner": 0},
	"A2": {"pos": Vector2(230, 190), "sector": "A", "owner": 0},
	"A3": {"pos": Vector2(230, 410), "sector": "A", "owner": 0},
	"A4": {"pos": Vector2(40, 430), "sector": "A", "owner": 0},
	"B1": {"pos": Vector2(500, 300), "sector": "B", "owner": 1},
	"B2": {"pos": Vector2(400, 180), "sector": "B", "owner": 1},
	"B3": {"pos": Vector2(600, 180), "sector": "B", "owner": 1},
	"B4": {"pos": Vector2(500, 460), "sector": "B", "owner": 1},
	"C1": {"pos": Vector2(880, 300), "sector": "C", "owner": 2},
	"C2": {"pos": Vector2(770, 190), "sector": "C", "owner": 2},
	"C3": {"pos": Vector2(770, 410), "sector": "C", "owner": 2},
	"C4": {"pos": Vector2(960, 430), "sector": "C", "owner": 2},
}

const LANES := [
	["A1", "A2"], ["A1", "A3"], ["A1", "A4"],
	["B1", "B2"], ["B1", "B3"], ["B1", "B4"],
	["C1", "C2"], ["C1", "C3"], ["C1", "C4"],
	["A2", "B2"],  # A-B chokepoint
	["B3", "C3"],  # B-C chokepoint
]


static func lane_length(a: String, b: String) -> float:
	return (SYSTEMS[a]["pos"] as Vector2).distance_to(SYSTEMS[b]["pos"])


## Whether a direct lane connects `a` and `b` (order-independent).
static func is_lane(a: String, b: String) -> bool:
	for lane in LANES:
		if (lane[0] == a and lane[1] == b) or (lane[0] == b and lane[1] == a):
			return true
	return false


static func neighbors(id: String) -> Array[String]:
	var out: Array[String] = []
	for lane in LANES:
		if lane[0] == id:
			out.append(lane[1])
		elif lane[1] == id:
			out.append(lane[0])
	return out


## Dijkstra over the lane graph, weighted by lane_length — a small (~12 node)
## graph, so the simplest correct shortest-path is plenty. Returns the hop
## sequence AFTER `from` (i.e. doesn't include the start system itself, matching
## what StrategicCommands' order_move "path" expects) or [] if no path/self-path.
static func shortest_path(from: String, to: String) -> Array[String]:
	if from == to:
		return []
	var dist := {}
	var prev := {}
	var unvisited := {}
	for id in SYSTEMS.keys():
		dist[id] = INF
		unvisited[id] = true
	dist[from] = 0.0

	while not unvisited.is_empty():
		var current := ""
		var best := INF
		for id in unvisited.keys():
			if dist[id] < best:
				best = dist[id]
				current = id
		if current == "" or current == to:
			break
		unvisited.erase(current)
		for n in neighbors(current):
			if not unvisited.has(n):
				continue
			var alt: float = dist[current] + lane_length(current, n)
			if alt < dist[n]:
				dist[n] = alt
				prev[n] = current

	if not prev.has(to) and from != to:
		return []
	var path: Array[String] = []
	var node := to
	while node != from:
		path.push_front(node)
		if not prev.has(node):
			return []  # unreachable
		node = prev[node]
	return path
