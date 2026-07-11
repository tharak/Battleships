extends RefCounted
class_name Ticker
## Event ticker (issue #30, GDD §9): a rolling history of recent events
## (casualty reports, planet/regime escalation transitions, rival regime
## news) -- distinct from strategic/era_events.gd's own `last_announcement`
## (a single CAMPAIGN-STORY-BEAT string, one-shot bookkeeping) even though
## both feed the same HUD panel. A dedicated, small file rather than folded
## into era_events.gd -- "campaign story-beat bookkeeping" and "UI log
## rendering data" are different concerns, and this codebase's own
## precedent is one small file per orthogonal concern even among closely
## related mechanics (Planet/Rebellion/Politics/Removal/Regime/Manpower/
## EraEvents are all separate files despite adjacency).
##
## "Two-tick advance warnings" (GDD's own design rule): NOT new predictive
## code here -- already a STRUCTURAL guarantee this codebase proved for
## Rebellion's own escalation ladder (test_home_front_demo.gd's
## _test_escalation_always_warns_before_rebelling: Planet.UNREST_DRIFT_RATE
## bounds the largest single-tick move well under the gap between adjacent
## thresholds, so a stage can never be skipped). Removal's own ladder needed
## an ACTUAL fix, not just documentation, to make the same guarantee hold --
## see removal.gd's THRESHOLD_BUMP_CLAMP (issue #30's own design review
## caught the combined instability+pretender bump could otherwise exceed a
## threshold gap and skip a stage). This file's job is just to surface every
## stage TRANSITION (not only the terminal one) so that pre-existing/newly-
## fixed structural guarantee becomes player-visible, not to add lookahead.

const MAX_ENTRIES := 3   # this HUD is already dense after #22-#29; kept tight


static func push(state: StrategicState, message: String) -> void:
	state.ticker.append(message)
	while state.ticker.size() > MAX_ENTRIES:
		state.ticker.pop_front()
