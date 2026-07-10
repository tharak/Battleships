extends RefCounted
class_name Starts
## Six hand-balanced fixed campaign starts (issue #27, GDD §8). GDD's own
## full spec is a procedural generator with randomized regime/coalition/
## sector/military draws, a Start Power Index scoring function, and a
## headless-batch regression-tuning loop — this ships GDD's OWN pre-decided
## cut-line instead ("Start generator → ship with 6 hand-balanced fixed
## starts instead", §12 Cut-lines #3), by explicit user direction (asked
## directly given the scale difference between the two).
##
## Each recipe is a self-contained trade-off package — GDD §8's own
## "compensation, not homogenization" principle: never just scaling one
## number up. "Confederacy" is defined to EXACTLY match the pre-existing
## hardcoded defaults (Politics.default_state()/Roster.default_state()/
## Planet.default_state()/"line" preset/0 materiel) — this is what makes the
## whole feature backward-compatible: any code path that never touches
## CampaignConfig sees ZERO behavior change, same "defaults reproduce
## identical behavior" rule this codebase has followed for every prior
## issue.
##
## Steerability guarantee (GDD §8): no recipe sets instability_ticks_left at
## all, so every start implicitly begins at 0.0 (apply() only overwrites the
## specific fields listed below, leaving Politics.default_state()'s own
## instability_ticks_left/coup_insurance_debt/removed_flag untouched at
## their seeded zero/false values) — never inside an instability window.
## Every recipe's W is strictly below Regime.BROADEN_MAX_W (12), so broaden
## is always available; Junta's W=3 sits exactly at Regime.PURGE_MIN_W (3),
## meaning purge alone is unavailable at the exact starting moment ("W=3 is
## already the junta floor," the intended flavor, confirmed against
## regime.gd's own `seats.size() <= PURGE_MIN_W` guard) -- not a structural
## lock in GDD's sense (permanently foreclosing a regime pole): broaden
## remains available from W=3, so every other regime shape stays reachable.
##
## CRITICAL implementation detail: GDScript `const` Dictionaries are a
## SINGLE shared object, not re-literalized on each read (unlike Politics.
## default_state()/Roster.default_state(), which build a fresh dict from a
## literal expression every call). apply() below always `.duplicate(true)`s
## every nested dict pulled out of RECIPES before assigning it into `state`
## — without this, every side (and every campaign, and every test run
## within one process) that picks the same start_id would share the exact
## same seats/roster Dictionary object, and mutating one realm's seat
## satisfaction would silently corrupt every other realm using that recipe.

const IDS := ["confederacy", "junta", "republic", "oligarchy", "garrison_state", "trade_federation"]

const RECIPES := {
	"confederacy": {
		"label": "The Confederacy — a balanced, unremarkable inheritance",
		"seats": {
			"fleet_commander": {"name": "Fleet Commander", "kind": "individual", "satisfaction": 60.0, "weight": 3.0},
			"interior_minister": {"name": "Interior Minister", "kind": "individual", "satisfaction": 60.0, "weight": 2.0},
			"treasury_minister": {"name": "Treasury Minister", "kind": "individual", "satisfaction": 60.0, "weight": 2.0},
			"veterans_league": {"name": "Veterans' League", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"industrial_bloc": {"name": "Industrial Bloc", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"colonial_assembly": {"name": "Colonial Assembly", "kind": "bloc", "satisfaction": 60.0, "weight": 3.0},
		},
		"roster": {
			"fleet_commander": {"name": "Adm. Kestrel", "tactics": 50.0, "logistics": 50.0, "charisma": 55.0, "ambition": 0.0, "alive": true, "seat_id": "fleet_commander"},
			"interior_minister": {"name": "Min. Osric Vale", "tactics": 30.0, "logistics": 55.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": "interior_minister"},
			"treasury_minister": {"name": "Min. Dessa Faron", "tactics": 35.0, "logistics": 70.0, "charisma": 40.0, "ambition": 0.0, "alive": true, "seat_id": "treasury_minister"},
			"genius_officer": {"name": "Cdr. Ilyana Rook", "tactics": 80.0, "logistics": 45.0, "charisma": 30.0, "ambition": 0.0, "alive": true, "seat_id": null},
			"average_officer": {"name": "Cdr. Petra Yun", "tactics": 50.0, "logistics": 50.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": null},
			"junior_officer": {"name": "Cdr. Tomas Reyes", "tactics": 60.0, "logistics": 60.0, "charisma": 45.0, "ambition": 0.0, "alive": true, "seat_id": null},
		},
		"s_percent": 20.0, "budget": {"military": 0.4, "private": 0.3, "public": 0.3},
		"election_countdown": 52.0, "materiel": 0.0, "fleet_preset": "line",
		"planet_overrides": {},
	},
	"junta": {
		"label": "The Junta — W=3, veteran wedge fleet, deep stockpiles; grieved planets, a coup-risk floor",
		"seats": {
			"fleet_commander": {"name": "Fleet Commander", "kind": "individual", "satisfaction": 45.0, "weight": 3.0},
			"interior_minister": {"name": "Interior Minister", "kind": "individual", "satisfaction": 45.0, "weight": 3.0},
			"treasury_minister": {"name": "Treasury Minister", "kind": "individual", "satisfaction": 45.0, "weight": 3.0},
		},
		"roster": {
			"fleet_commander": {"name": "Adm. Draven Kessler", "tactics": 65.0, "logistics": 55.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": "fleet_commander"},
			"interior_minister": {"name": "Min. Halric Toth", "tactics": 40.0, "logistics": 50.0, "charisma": 45.0, "ambition": 0.0, "alive": true, "seat_id": "interior_minister"},
			"treasury_minister": {"name": "Min. Corvin Aske", "tactics": 35.0, "logistics": 60.0, "charisma": 40.0, "ambition": 0.0, "alive": true, "seat_id": "treasury_minister"},
			"veteran_officer": {"name": "Cdr. Rasha Voss", "tactics": 70.0, "logistics": 50.0, "charisma": 35.0, "ambition": 0.0, "alive": true, "seat_id": null},
		},
		"s_percent": 15.0, "budget": {"military": 0.6, "private": 0.25, "public": 0.15},
		"election_countdown": 52.0, "materiel": 300.0, "fleet_preset": "wedge",
		"planet_overrides": {"unrest": 30.0},
	},
	"republic": {
		"label": "The Republic — W=10, loyal prosperous planets, volunteer crews; a demobilized navy, an election clock already ticking",
		"seats": {
			"fleet_commander": {"name": "Fleet Commander", "kind": "individual", "satisfaction": 65.0, "weight": 2.0},
			"interior_minister": {"name": "Interior Minister", "kind": "individual", "satisfaction": 65.0, "weight": 2.0},
			"veterans_league": {"name": "Veterans' League", "kind": "bloc", "satisfaction": 65.0, "weight": 1.0},
			"industrial_bloc": {"name": "Industrial Bloc", "kind": "bloc", "satisfaction": 65.0, "weight": 1.0},
			"colonial_assembly": {"name": "Colonial Assembly", "kind": "bloc", "satisfaction": 65.0, "weight": 1.0},
			"merchants_guild": {"name": "Merchants' Guild", "kind": "bloc", "satisfaction": 65.0, "weight": 1.0},
			"farmers_congress": {"name": "Farmers' Congress", "kind": "bloc", "satisfaction": 65.0, "weight": 1.0},
			"scholars_council": {"name": "Scholars' Council", "kind": "bloc", "satisfaction": 65.0, "weight": 1.0},
			"clergy_synod": {"name": "Clergy Synod", "kind": "bloc", "satisfaction": 65.0, "weight": 1.0},
			"frontier_council": {"name": "Frontier Council", "kind": "bloc", "satisfaction": 65.0, "weight": 1.0},
		},
		"roster": {
			"fleet_commander": {"name": "Adm. Selwyn Marchetti", "tactics": 30.0, "logistics": 60.0, "charisma": 60.0, "ambition": 0.0, "alive": true, "seat_id": "fleet_commander"},
			"interior_minister": {"name": "Min. Priya Osei", "tactics": 25.0, "logistics": 55.0, "charisma": 55.0, "ambition": 0.0, "alive": true, "seat_id": "interior_minister"},
			"volunteer_captain": {"name": "Cpt. Wren Halloway", "tactics": 55.0, "logistics": 65.0, "charisma": 40.0, "ambition": 0.0, "alive": true, "seat_id": null},
			"citizen_officer": {"name": "Cdr. Jonas Vy", "tactics": 45.0, "logistics": 50.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": null},
		},
		"s_percent": 40.0, "budget": {"military": 0.25, "private": 0.35, "public": 0.4},
		"election_countdown": 15.0, "materiel": 50.0, "fleet_preset": "swarm",
		"planet_overrides": {"loyalty": 90.0, "unrest": 0.0, "conscription": "volunteer", "industry": 3.0},
	},
	"oligarchy": {
		"label": "The Oligarchy — W=6, rich industry, Serapha-adjacent credit; huge seat weights and commercial appetites a war economy starves",
		"seats": {
			"fleet_commander": {"name": "Fleet Commander", "kind": "individual", "satisfaction": 60.0, "weight": 6.0},
			"interior_minister": {"name": "Interior Minister", "kind": "individual", "satisfaction": 60.0, "weight": 4.0},
			"treasury_minister": {"name": "Treasury Minister", "kind": "individual", "satisfaction": 60.0, "weight": 4.0},
			"veterans_league": {"name": "Veterans' League", "kind": "bloc", "satisfaction": 60.0, "weight": 4.0},
			"industrial_bloc": {"name": "Industrial Bloc", "kind": "bloc", "satisfaction": 60.0, "weight": 4.0},
			"colonial_assembly": {"name": "Colonial Assembly", "kind": "bloc", "satisfaction": 60.0, "weight": 6.0},
		},
		"roster": {
			"fleet_commander": {"name": "Adm. Corin Thale", "tactics": 45.0, "logistics": 55.0, "charisma": 60.0, "ambition": 0.0, "alive": true, "seat_id": "fleet_commander"},
			"interior_minister": {"name": "Min. Ysolde Bram", "tactics": 30.0, "logistics": 55.0, "charisma": 55.0, "ambition": 0.0, "alive": true, "seat_id": "interior_minister"},
			"treasury_minister": {"name": "Min. Egon Vasser", "tactics": 25.0, "logistics": 70.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": "treasury_minister"},
			"free_captain": {"name": "Cpt. Nadia Sorel", "tactics": 65.0, "logistics": 50.0, "charisma": 35.0, "ambition": 0.0, "alive": true, "seat_id": null},
		},
		"s_percent": 20.0, "budget": {"military": 0.3, "private": 0.35, "public": 0.35},
		"election_countdown": 52.0, "materiel": 100.0, "fleet_preset": "line",
		"planet_overrides": {"industry": 4.0},
	},
	"garrison_state": {
		"label": "The Garrison State — W=4, military-heavy budget, strong garrisons; a thin treasury and reduced industry",
		"seats": {
			"garrison_commander": {"name": "Garrison Commander", "kind": "individual", "satisfaction": 55.0, "weight": 3.0},
			"interior_minister": {"name": "Interior Minister", "kind": "individual", "satisfaction": 55.0, "weight": 3.0},
			"treasury_minister": {"name": "Treasury Minister", "kind": "individual", "satisfaction": 55.0, "weight": 3.0},
			"quartermaster": {"name": "Quartermaster", "kind": "individual", "satisfaction": 55.0, "weight": 3.0},
		},
		"roster": {
			"garrison_commander": {"name": "Adm. Bryce Ondra", "tactics": 55.0, "logistics": 60.0, "charisma": 45.0, "ambition": 0.0, "alive": true, "seat_id": "garrison_commander"},
			"interior_minister": {"name": "Min. Talia Ferro", "tactics": 35.0, "logistics": 50.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": "interior_minister"},
			"treasury_minister": {"name": "Min. Garek Voss", "tactics": 30.0, "logistics": 55.0, "charisma": 40.0, "ambition": 0.0, "alive": true, "seat_id": "treasury_minister"},
			"quartermaster": {"name": "Qm. Elin Sasso", "tactics": 40.0, "logistics": 70.0, "charisma": 35.0, "ambition": 0.0, "alive": true, "seat_id": "quartermaster"},
			"war_hero": {"name": "Cdr. Osman Vale", "tactics": 70.0, "logistics": 45.0, "charisma": 30.0, "ambition": 0.0, "alive": true, "seat_id": null},
		},
		"s_percent": 20.0, "budget": {"military": 0.6, "private": 0.2, "public": 0.2},
		"election_countdown": 52.0, "materiel": 0.0, "fleet_preset": "line",
		"planet_overrides": {"garrison": 40.0, "unrest": 0.0, "industry": 1.5},
	},
	"trade_federation": {
		"label": "The Trade Federation — W=8, rich populous economy; a weak fleet and a vulnerable frontier",
		"seats": {
			"fleet_commander": {"name": "Fleet Commander", "kind": "individual", "satisfaction": 60.0, "weight": 2.0},
			"treasury_minister": {"name": "Treasury Minister", "kind": "individual", "satisfaction": 60.0, "weight": 2.0},
			"merchants_guild": {"name": "Merchants' Guild", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"industrial_bloc": {"name": "Industrial Bloc", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"shipping_consortium": {"name": "Shipping Consortium", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"colonial_assembly": {"name": "Colonial Assembly", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"bankers_league": {"name": "Bankers' League", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
			"artisans_guild": {"name": "Artisans' Guild", "kind": "bloc", "satisfaction": 60.0, "weight": 2.0},
		},
		"roster": {
			"fleet_commander": {"name": "Adm. Farid Kols", "tactics": 40.0, "logistics": 65.0, "charisma": 55.0, "ambition": 0.0, "alive": true, "seat_id": "fleet_commander"},
			"treasury_minister": {"name": "Min. Constance Reyer", "tactics": 30.0, "logistics": 75.0, "charisma": 45.0, "ambition": 0.0, "alive": true, "seat_id": "treasury_minister"},
			"privateer_captain": {"name": "Cpt. Dashiel Orr", "tactics": 60.0, "logistics": 55.0, "charisma": 30.0, "ambition": 0.0, "alive": true, "seat_id": null},
			"trade_officer": {"name": "Cdr. Mira Toussaint", "tactics": 45.0, "logistics": 60.0, "charisma": 50.0, "ambition": 0.0, "alive": true, "seat_id": null},
		},
		"s_percent": 30.0, "budget": {"military": 0.15, "private": 0.4, "public": 0.45},
		"election_countdown": 52.0, "materiel": 20.0, "fleet_preset": "swarm",
		"planet_overrides": {"industry": 4.0, "population": 150.0, "unrest": 25.0},
	},
}


static func label(start_id: String) -> String:
	return RECIPES[start_id]["label"]


static func fleet_preset(start_id: String) -> String:
	return RECIPES[start_id]["fleet_preset"]


## Applies `start_id`'s recipe to `side`. Overwrites politics/roster/
## materiel wholesale (every field this recipe cares about; anything NOT
## listed here -- instability_ticks_left, coup_insurance_debt, removed_flag,
## next_seat_id, removal_reason -- is left at Politics.default_state()'s own
## seeded zero/false values, which is exactly what the steerability
## guarantee in this file's own docstring relies on). Planet overrides apply
## to EVERY system `side` currently owns (GDD's "sector draw" axis; each
## side starts owning 4 systems per Galaxy.gd, not just its home hub).
static func apply(state: StrategicState, side: int, start_id: String) -> void:
	var recipe: Dictionary = RECIPES[start_id]
	var pol: Dictionary = state.politics[side]
	pol["seats"] = (recipe["seats"] as Dictionary).duplicate(true)
	pol["s_percent"] = recipe["s_percent"]
	pol["budget_military"] = recipe["budget"]["military"]
	pol["budget_private"] = recipe["budget"]["private"]
	pol["budget_public"] = recipe["budget"]["public"]
	pol["election_countdown"] = recipe["election_countdown"]
	state.roster[side] = (recipe["roster"] as Dictionary).duplicate(true)
	state.materiel[side] = recipe["materiel"]

	var overrides: Dictionary = recipe["planet_overrides"]
	if overrides.is_empty():
		return
	for id in state.system_owner.keys():
		if state.system_owner[id] == side:
			var p: Dictionary = state.planets[id]
			for key in overrides.keys():
				p[key] = overrides[key]
