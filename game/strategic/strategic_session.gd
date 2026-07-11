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

## Issue #30: the guided-opening budget callout's own dismissal flag -- a
## pure UI/tutorial concern, deliberately NOT on StrategicState (this
## scene's own "no direct UI-to-sim pokes" architecture rule would be
## broken by a cosmetic flag with no simulation meaning living there).
## Lives here instead, alongside `sim`, for the SAME reason `sim` does:
## process-lifetime state that must survive the battle-scene round-trip.
## Reset to false by strategic_map.gd's own KEY_R restart handler
## (alongside `sim = null`) so a genuinely new campaign shows it again.
static var tutorial_budget_shown := false
