extends RefCounted
class_name StrategicSession
## Persists the live StrategicSim across scene changes (issue #14: a map
## contact launches main.tscn, destroying strategic_map.tscn's own scene
## instance and everything in it). A static var on a plain class — same
## technique as SkirmishConfig (skirmish_config.gd) — survives that because
## it's process-lifetime state, not anything scene-tree-scoped. strategic_map.gd
## checks this on _ready(): null means a fresh session (spawn the starting
## fleets), non-null means resuming one already in progress.

static var sim: StrategicSim = null
