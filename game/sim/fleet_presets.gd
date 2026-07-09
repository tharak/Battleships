extends RefCounted
class_name FleetPresets
## Skirmish fleet presets (issue #11). Pure data — the skirmish menu picks a name
## from NAMES to populate its UI, main.gd's _spawn_scene reads PRESETS[name] to
## know how many squadrons to spawn at what strength. Deliberately comparable
## total strength across presets (60-90) so picking one is a real tactical
## choice — more numerous & individually fragile vs. fewer & individually tough —
## not just "which number is biggest."

const PRESETS := {
	"line": {
		"label": "Line Fleet — 5 x 15 strength (balanced)",
		"count": 5, "strength": 15,
	},
	"wedge": {
		"label": "Wedge Fleet — 4 x 18 strength (fewer, tougher)",
		"count": 4, "strength": 18,
	},
	"swarm": {
		"label": "Swarm Fleet — 8 x 9 strength (numerous, fragile)",
		"count": 8, "strength": 9,
	},
}

const NAMES := ["line", "wedge", "swarm"]
const DEFAULT := "line"


static func total_strength(name: String) -> int:
	var p: Dictionary = PRESETS[name]
	return int(p["count"]) * int(p["strength"])
