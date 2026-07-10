extends RefCounted
class_name StrategicState
## Plain-data strategic-layer state (GDD §11 architecture, mirrored from the
## battle layer's sim/battle_state.gd — same "plain data, one mutation path"
## discipline, a separate state/sim/command trio because the two layers are
## separate systems that feed each other via defined contracts, GDD §5.8, not
## shared internals).
##
## `tick` is in WEEKS (GDD §2: "1 turn-tick = 1 week"), ticked-pausable per GDD
## Open Question 4's resolution (issue #12: continuous ticked time, not discrete
## turns — matches the battle layer's existing real-time-with-pause UX).
##
## Fleet fields: side (int), system (String, current/last-departed system id),
## dest (String or null — null means holding at `system`, not traveling),
## progress (float 0-1, fraction of the current lane covered), path
## (Array[String], remaining hops queued after `dest` — consumed one at a time
## as each hop completes, see strategic_sim.gd's _start_next_hop), supply
## (float 0-100 — issue #13, GDD §4.4, drained/regenerated each tick by
## strategic/supply.gd), preset (String, a FleetPresets name — issue #14's
## battle-seeding roster, see strategic/battle_bridge.gd), strength (int, this
## fleet's current total combat strength — starts at FleetPresets.
## total_strength(preset), updated by battle_bridge.gd's apply_result once a
## fought battle concludes; a full squadron-by-squadron roster only exists
## inside a tactical battle, not on the map).
##
## `system_owner`: id -> side (-1 = neutral/contested, or Rebellion.REBEL_SIDE
## == -2 once a planet actually rebels — issue #18), seeded from Galaxy's
## static data and (in a later issue) mutated by battle outcomes/invasions —
## issue #12 itself never changes ownership, just seeds and reads it for intel.
##
## `materiel`: side (int) -> float stockpile (issue #15, GDD §4.2/§4.4) — accrues
## passively per owned system (strategic/shipyard.gd's accrue) and is spent
## rebuilding docked fleets' lost strength (shipyard.gd's rebuild).
##
## `planets`: system id -> Dictionary (issue #17, GDD §4.2 — see strategic/
## planet.gd for the full field list/formulas). One planet per system (MVP
## simplification), seeded for every Galaxy.SYSTEMS id regardless of ownership —
## a planet's stats persist through conquest (Planet.advance just reads whichever
## side currently owns it), and an unowned/neutral system's planet simply doesn't
## evolve (Planet.advance's owner==-1 early-out) until someone claims it.
##
## `politics`: side (int) -> Dictionary (issue #22, GDD §4.5 — see strategic/
## politics.gd for the full field list/formulas). Seeded for sides 0/1/2
## alongside `materiel`, same one-default-per-realm precedent as `planets`.
##
## `roster`: side (int) -> Dictionary of character_id -> Dictionary (issue
## #25, GDD §6 — see strategic/roster.gd for the full field list/formulas).
## Seeded for sides 0/1/2 the same way, one call alongside `politics`.

var tick: int = 0  # weeks
var fleets: Dictionary = {}  # id -> Dictionary
var system_owner: Dictionary = {}  # id (String) -> int side
var materiel: Dictionary = {0: 0.0, 1: 0.0, 2: 0.0}  # side -> stockpile (issue #16: 3 realms)
var planets: Dictionary = {}  # id (String) -> Dictionary
var politics: Dictionary = {}  # side (int) -> Dictionary
var roster: Dictionary = {}  # side (int) -> Dictionary


func _init() -> void:
	for id in Galaxy.SYSTEMS.keys():
		system_owner[id] = Galaxy.SYSTEMS[id]["owner"]
		planets[id] = Planet.default_state()
	for side in [0, 1, 2]:
		politics[side] = Politics.default_state()
		roster[side] = Roster.default_state()
