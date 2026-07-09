extends RefCounted
class_name Intel
## Pickets-based fog of war (issue #12, GDD §4.6): "You see: your systems,
## systems with your fleets, and one lane beyond (pickets)." Pure query against
## a StrategicState, same pure-function pattern as the battle layer's
## Combat/Morale/Terrain — nothing here mutates state, it's read each time the
## UI (or an AI, later) needs to know what a side can currently see.
##
## Listening posts and Serapha-purchased intel (GDD §4.6) extending this range
## are out of scope for issue #12 — no listening-post system exists yet.

## Systems visible to `side`: their own systems, any system one of their fleets
## currently occupies or is en route to, and one lane beyond all of those.
static func visible_systems(state: StrategicState, side: int) -> Dictionary:
	var core := {}
	for id in state.system_owner.keys():
		if state.system_owner[id] == side:
			core[id] = true
	for id in state.fleets.keys():
		var f: Dictionary = state.fleets[id]
		if f["side"] != side:
			continue
		core[f["system"]] = true
		if f["dest"] != null:
			core[f["dest"]] = true

	var visible := core.duplicate()
	for id in core.keys():
		for n in Galaxy.neighbors(id):
			visible[n] = true
	return visible
