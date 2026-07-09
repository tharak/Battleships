extends RefCounted
class_name Formations
## Fleet formations (issue #6, GDD §5.4): Spindle, Wide Line, Echelon, Crescent,
## Sphere, Column. Pure shape generators, not simulation state or a new command kind
## — GDD §5.4 formations are "only setups: positions and facings", and #4 already
## gives squadrons everything needed to reach a position and hold a facing. Applying
## a formation is just smart order generation on top of the existing order_move
## (with its optional arrival `face`, see commands.gd/sim.gd), which is also why
## "reforming takes time and drops cohesion" needs no new mechanic: it already falls
## out of travel time and the existing turn-cohesion cost (GDD §5.2, issue #4).
##
## Unlike the Phase 0 paper/HTML prototypes' fixed 5/9/12-squadron hex tables, these
## generators take any squadron count N — this is a continuous-plane engine with no
## fixed roster sizes, so the shapes are re-derived from the SAME qualitative
## geometry (deep wedge / broad rank / staggered diagonal / concave arc / defensive
## ring / travel file) rather than transcribed coordinate tables that don't fit this
## coordinate system anyway.
##
## A slot is {"fwd": float, "lat": float, "face_offset": float or null}. "fwd" is
## distance toward the formation's forward direction (the tip of a wedge has the
## largest fwd); "lat" is lateral offset, positive to one side. "face_offset", when
## set, means the slot's facing is measured from the formation's OWN forward axis
## rather than inherited unchanged — Sphere is the only shape that uses this, since
## its units face radially outward rather than all facing the same way.
##
## Returns {"slots": Array[Dictionary], "flag": int}. `flag` is whichever slot sits
## closest to the shape's own centroid — every one of these formations protects its
## command unit near the center of the formation's own bulk, not out on an exposed
## edge, matching the paper prototype's placement (e.g. spindle's flagship sits at
## the diamond's center, not its tip).

const NAMES := ["spindle", "line", "echelon", "crescent", "sphere", "column"]

const SPACING := 1.0        # unit spacing between adjacent slots, before caller scaling
const ECHELON_CLAMP := 6.0  # cap the diagonal's depth so wide echelons don't get absurdly long
const CRESCENT_BOW := 3.0   # how far the wings are pulled forward relative to the center
const SPHERE_RADIUS := 2.2


static func generate(name: String, n: int) -> Dictionary:
	assert(n >= 1, "formation needs at least 1 squadron")
	var slots: Array[Dictionary]
	match name:
		"spindle":
			slots = _spindle(n)
		"line":
			slots = _line(n)
		"echelon":
			slots = _echelon(n)
		"crescent":
			slots = _crescent(n)
		"sphere":
			slots = _sphere(n)
		"column":
			slots = _column(n)
		_:
			assert(false, "unknown formation: %s" % name)
	return {"slots": slots, "flag": _pick_flag_slot(slots)}


static func _pick_flag_slot(slots: Array[Dictionary]) -> int:
	var cx := 0.0
	var cy := 0.0
	for s in slots:
		cx += s["fwd"]; cy += s["lat"]
	cx /= slots.size(); cy /= slots.size()
	var best := 0
	var best_d := INF
	for i in range(slots.size()):
		var d: float = Vector2(slots[i]["fwd"] - cx, slots[i]["lat"] - cy).length_squared()
		if d < best_d:
			best_d = d
			best = i
	return best


static func _line(n: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for i in range(n):
		slots.append({"fwd": 0.0, "lat": (i - (n - 1) / 2.0) * SPACING, "face_offset": null})
	return slots


## Deep, narrow wedge: a single-unit tip at the front, each row back one wider —
## "the breakthrough formation" (GDD §5.4). Front-loaded protection falls out of
## _pick_flag_slot rather than being hardcoded to a particular row.
static func _spindle(n: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var row := 0
	var placed := 0
	while placed < n:
		var row_size := row + 1
		var take: int = min(row_size, n - placed)
		for i in range(take):
			var lat: float = (i - (row_size - 1) / 2.0) * SPACING
			slots.append({"fwd": -row * SPACING, "lat": lat, "face_offset": null})
		placed += take
		row += 1
	return slots


## Staggered diagonal — "the refused flank" (GDD §5.4): each unit further to one side
## sits further back, deflecting a head-on punch into a flank trade.
static func _echelon(n: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for i in range(n):
		var lat: float = (i - (n - 1) / 2.0) * SPACING
		var fwd: float = clampf(-lat, -ECHELON_CLAMP, ECHELON_CLAMP)
		slots.append({"fwd": fwd, "lat": lat, "face_offset": null})
	return slots


## Concave arc, wings advanced and angled inward — wraps a wedge and rakes its
## flanks, at the cost of a thin center (GDD §5.4).
static func _crescent(n: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	var max_lat: float = maxf(1.0, (n - 1) / 2.0 * SPACING)
	for i in range(n):
		var lat: float = (i - (n - 1) / 2.0) * SPACING
		var fwd: float = CRESCENT_BOW * pow(absf(lat) / max_lat, 2.0)
		slots.append({"fwd": fwd, "lat": lat, "face_offset": null})
	return slots


## All-round defensive ring: one unit at the protected center, the rest spaced
## evenly around it facing outward — no flank to find (GDD §5.4).
static func _sphere(n: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = [{"fwd": 0.0, "lat": 0.0, "face_offset": null}]
	var ring := n - 1
	for i in range(ring):
		var ang := TAU * i / ring
		slots.append({
			"fwd": cos(ang) * SPHERE_RADIUS * SPACING,
			"lat": sin(ang) * SPHERE_RADIUS * SPACING,
			"face_offset": rad_to_deg(ang),
		})
	return slots


## Single file, travel order — fast and terrible in combat (GDD §5.4): every unit
## trails the one ahead of it.
static func _column(n: int) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for i in range(n):
		slots.append({"fwd": -i * SPACING, "lat": 0.0, "face_offset": null})
	return slots
