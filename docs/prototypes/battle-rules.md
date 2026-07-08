# Paper Prototype — Fleet Battle Rules v0.1

Playable-on-a-table encoding of GDD §5.4–§5.5 (formations, arcs, facing, morale, rout,
supply). Purpose: answer **open question 1** — *does the formation counter-wheel emerge
from arcs and facing alone, or do we need hard formation-vs-formation modifiers?* —
before writing any engine code (issue #1, GDD §12 Phase 0a).

These rules contain **zero formation modifiers**: a "formation" is nothing but where you
put your counters and where they point. If the counter-wheel appears anyway, question 1
is answered the way we hoped.

**Components:** hex paper (~24×18 hexes), 9 squadron counters per side with a printed
facing arrow (mark one `F` for flagship), d6s, strength tokens (4 per squadron), and
markers for *Shaken* / *Routed* / *Activated*.

---

## 1. Squadrons

Each squadron has:

- **Strength 4** (tokens). Hits remove tokens; at 0 the squadron is destroyed.
- **Status:** *Steady* → *Shaken* → *Routed* (morale ladder, §6).
- **Facing:** the arrow points at a hexside (not a corner). All arcs derive from it.

A fleet = 9 squadrons, one of which is the **flagship**.

## 2. Turn structure

Players **alternate activating one squadron at a time** (this stands in for real-time
flow). Roll off for who activates first each turn; each squadron activates once per turn
(mark with a token). When all squadrons have activated, remove tokens and start the next
turn.

**Activation:**
- **In command** (within 4 hexes of your flagship): the squadron may **move and fire**,
  in either order.
- **Out of command:** it may **move or fire**, not both. *(This is the command-radius /
  order-delay rule from GDD §5.6, in paper form.)*

## 3. Movement

- **3 movement points (MP)** per activation.
- 1 MP: move one hex straight ahead (through the faced hexside).
- 1 MP: turn 60° (one hexside) in place.
- No entering occupied hexes. Leaving the map = squadron is gone (routed off / withdrawn).

## 4. Arcs & line of sight

Arcs are measured from the **target's** facing when receiving fire, and from the
**firer's** facing when shooting:

- **Front arc:** the faced hexside plus the two adjacent hexsides (a 180° bow band).
  You may **only fire into your own front arc**.
- **Flank arc:** the two rear-oblique hexsides.
- **Rear arc:** the hexside directly astern.
- Borderline cases (the shot runs exactly along an arc seam) resolve **in the shooter's
  favor** — maneuvering for angle should pay, never disappoint.

**Line of sight:** beams are blocked by *any* squadron (friend or enemy) in a hex on the
straight line between firer and target. Use a straight-edge; if the line runs along a
hex edge, the shooter picks which hex it passes through. *(This is what makes depth a
real trade-off: rear ranks in a deep formation are protected but masked.)*

## 5. Firing

- **Range:** 3 hexes.
- Roll **1d6 per current Strength point**. *Shaken* squadrons roll half, rounded up.
- **To-hit, by the arc of the TARGET you are firing into:**

  | You are in the target's… | Hit on | (Low supply: hit on) |
  |---|---|---|
  | Front arc | 5+ | 6 |
  | Flank arc | 4+ | 5+ |
  | Rear arc | 3+ | 4+ |

- Each hit removes 1 Strength token. Choose one target per activation (nearest legal
  target if you can't decide).

**Low supply** is a scenario flag on a whole fleet (GDD §5.8): its squadrons use the
bracketed to-hit column and take −1 on all morale rolls.

## 6. Morale

**Check morale (roll 1d6, pass on 4+)** whenever, and once per trigger:

- the squadron lost ≥1 Strength during an enemy activation (check after that activation);
- a friendly squadron within 2 hexes routs or is destroyed;
- the fleet's flagship is destroyed (every squadron checks once).

**Modifiers (cumulative):**

| Condition | Mod |
|---|---|
| A *Steady* friendly squadron is adjacent | +1 |
| Within flagship command radius (4 hexes) | +1 |
| The triggering fire came from your flank or rear | −1 |
| Low supply | −1 |
| Your flagship has been destroyed (permanent) | −1 |

**Failing a check:** *Steady* → *Shaken*; *Shaken* → *Routed*.

- **Shaken:** rolls half dice (round up); may turn and fire but **may not end a move
  closer to the nearest enemy**.
- **Routed:** immediately faces its own map edge. Each activation it must spend all MP
  fleeing toward that edge and may not fire. Off the map = eliminated. Note that a
  fleeing squadron shows its **rear arc** (hit on 3+) — routs are contagious *and*
  bloody, per GDD §5.5.
- **Rally:** a *Routed* squadron that took no hits since its last activation may roll at
  the start of its activation: 4+ (+1 if in command radius) → becomes *Shaken* and stops.

**Flagship destroyed:** immediate fleet-wide morale check, permanent −1 morale, and the
command radius is gone (every squadron is move-*or*-fire for the rest of the battle).

## 7. Victory

A fleet **breaks** when 5 of its 9 squadrons are destroyed or have fled the map. The
other side wins. If neither fleet breaks by the end of turn 15 (paper) the battle is a
draw — score it by surviving Strength. Voluntary withdrawal off your own edge is always
legal (and often correct).

## 8. Formation setup templates

Formations are **only setups** — positions and facings inside your deployment zone
(within 3 hexes of your edge, fleets ~16 hexes apart). `>` marks facing toward the enemy;
`F` is the flagship.

```text
WIDE LINE                    SPINDLE (diamond)          ECHELON
> > > > F > > > >                  >                    > 
                                  > >                     > 
(9 abreast, adjacent             > F >                      F
 = max arcs + mutual              > >                         >
 support morale)                   >                            >
                             (1-2-3-2-1, deep &        (diagonal; refused
                              narrow: masked rear       flank; each unit
                              ranks replace losses)     covers the next)

CRESCENT / ENVELOPMENT       SPHERE (all-round)         COLUMN
>                                > > >                  > > > F > > (single
  >                              > F >                   file; travel order;
    > F >                        > > >                   terrible in combat)
  >                          (ring, facing out;
>                             no flank to find)
(wings advanced and
 angled inward)
```

## 9. Playtest protocol

Play each matchup below at least twice, swapping sides. Record: winner, turns, surviving
strength, and — most important — **what you found yourself wanting to do** (the game
design lives there).

| # | Matchup | The counter-wheel predicts |
|---|---|---|
| 1 | Spindle vs Wide Line | Spindle pierces the center and wins |
| 2 | Wide Line vs Crescent | Line's massed arcs shoot the thin arc apart |
| 3 | Crescent vs Spindle | Crescent wraps the wedge and rakes its flanks |
| 4 | Echelon vs Spindle | Echelon deflects the punch into a flank trade |
| 5 | Sphere vs Crescent | Sphere holds (no flanks) but can't win — draw-ish |
| 6 | Any vs Column | Column gets slaughtered (sanity check) |
| 7 | Mirror match, one side **Low supply** | Supply side loses clearly but not hopelessly |
| 8 | Mirror match, one side flagship hunted early | Decapitation is strong but risky |

**Questions to answer (write answers in the playtest notes below):**

1. Does the wheel hold with *zero* formation modifiers? Which legs fail?
2. Are flank/rear multipliers (via to-hit) strong enough to make maneuver the game?
3. Is morale cascade pace right — do battles end in routs, not annihilation (GDD §5.5)?
4. Command radius: does flagship placement create real decisions?
5. Is Low supply's weight right (clear handicap, not auto-loss)?
6. Fun check: did you want to keep playing after game 3?

---

## 10. Playtest notes

### 10.a Simulated baseline — `prototypes/battle_sim.py`

Before any table play, these exact rules were implemented in a ~400-line Python
simulator (`prototypes/battle_sim.py`, no dependencies, seeded) with deliberately **dumb
handling**: every squadron advances toward the nearest enemy and shoots when it can —
no clever maneuvering, no formation-keeping. This measures what the *geometry alone*
gives us; table play with human cunning comes on top.

Results (400 battles per matchup, sides mirrored, seed 42 — reproduce with
`python3 prototypes/battle_sim.py`):

**Win% matrix (row's win rate vs column):**

| vs | spindle | line | crescent | echelon | sphere | column |
|---|---|---|---|---|---|---|
| **spindle** | — | 26% | 45% | 36% | 66% | 94% |
| **line** | 74% | — | 36% | 80% | 88% | 88% |
| **crescent** | 55% | 64% | — | 78% | 87% | 90% |
| **echelon** | 64% | 20% | 22% | — | 85% | 90% |
| **sphere** | 32% | 11% | 12% | 13% | — | 91% |
| **column** | 6% | 12% | 9% | 9% | 8% | — |

Supply test (mirror line-vs-line, one side low supply): normal supply wins **97%**.
Average battle length: 6–12 turns, always ending by break threshold, never by grind.

**Headline findings:**

1. **Flanking geometry works with zero modifiers.** Every formation that presents
   angled or staggered facings (crescent, echelon) beats straight-ahead advances by
   generating flank arcs on the approach — crescent wraps spindle 55/45 and even beats
   line 64/36. The to-hit steps (5+/4+/3+) plus the flank-fire morale penalty carry
   pillar 1 on their own. **Encouraging for open question 1.**
2. **The spindle's breakthrough does NOT emerge from dumb handling** (26% vs line).
   Piercing a line is a *maneuver*, not a stat — the sim's advance-and-shoot AI walks
   the wedge into a concave firebase and never exploits a penetration. **The key table
   test:** can a human driving the spindle punch through and win? If yes, the wheel is
   emergent-with-skill (ideal — it means formation play is skill expression). If no,
   v0.2 needs a piercing mechanic (e.g., extra cohesion/morale damage on a squadron
   whose adjacent file is destroyed).
3. **Sphere loses open-field duels badly** (11–13% vs the firing-line formations) and
   resists concentrated wedges best (32% vs spindle, its least-bad matchup). That is
   roughly as designed — it's a survival formation, and a 1v1 frontal duel isn't its
   use case. Test it on the table in its real context: surrounded, awaiting relief,
   scoring turns survived rather than wins.
4. **Low supply is drastically over-weighted** (97/3 — auto-loss, not handicap).
   +1 to-hit *and* −1 morale double-dips. Recommendation for v0.2: low supply affects
   **morale only** (−1), with to-hit worsening reserved for a deeper "critical supply"
   state — retest for a ~70/30 target.
5. **Pacing is right:** battles are decisive (6–12 turns), always ending in a break —
   the morale cascade produces rout endings, not annihilation grinds, exactly per GDD
   §5.5.
6. **Column dies to everything** (6–12%). Sanity check passed; travel order is a real
   risk, which is what makes strategic-layer interception matter.

*Sim limitations to keep in mind at the table:* no formation-keeping (shapes smear as
units home in), no deliberate flanking movement, no withdrawal judgment, no flagship
hunting. Everything the sim can't do is precisely what the table playtest is for.

### 10.b Human playtests — TO DO (the human half of issue #1)

The sim can't test what only a human will find: deliberate flank hooks, feints, refusing
a flank, flagship sniping, when to withdraw. These rules are playable in the browser —
**https://tharak.github.io/Battleships/prototypes/battle.html**
(source: `docs/prototypes/battle.html`, a single self-contained page implementing this
exact ruleset; its AI is the same dumb advance-and-shoot logic as the Python sim, and a
headless port-validation test confirms the page reproduces the sim's win rates). The
scenario menu is the §9 protocol. Play each test, use the "copy result line" button, and
fill in:

- [ ] Result lines & answers to questions 1–6 (§9)

  ```text
  2026-07-08  Spindle vs Wide Line | ctrl=Blue | winner=Blue (spindle) | turn=6 | strength 12-16 | losses 4-5
  2026-07-08  Spindle vs Wide Line | ctrl=Blue | winner=Red (line)     | turn=5 | strength 14-19 | losses 5-4
  2026-07-08  Spindle vs Wide Line | ctrl=Blue | winner=Red (line)     | turn=6 | strength 12-28 | losses 5-0
  2026-07-08  Spindle vs Wide Line | ctrl=Blue | winner=Blue (spindle) | turn=5 | strength 19-14 | losses 3-5
  ```
  **Human spindle vs line: 2–2** (AI baseline: 26/74). Human maneuver roughly doubles
  the spindle's odds — the matchup is *competitive with skill*, not dominant. One loss
  was total (5–0): misplay the approach and the wedge gets shot apart before contact.

  **Winning tactic (player report):** don't pierce the center — attack the *edge* of the
  line, keep the flagship protected, and bait the AI's units into converging so they
  stack up and **mask their own lines of fire**. Local superiority at one end + LOS
  self-blocking beats the line's width. Notably this is defeat-in-detail against a wing,
  not the classic center punch — and it works with zero formation modifiers.

  Interpretation for question 1: the wheel is **soft/emergent** — formations create real
  and different problems, skill decides. First wins over the AI came only after learning
  the trick (games 2–3 were losses), which is the skill curve we want.

  ```text
  2026-07-08  Spindle vs Wide Line | ctrl=Blue | winner=Blue (spindle) | turn=4 | strength 21-15 | losses 3-5
  ```
  3–2. **Player diagnosis of the AI's real weakness: the flagship charges recklessly.**
  The AI treats its flagship like any squadron — it homes on the nearest enemy, arrives
  early, and dies. Winning pattern: hold your own flagship back, let the wings make
  contact first, then kill the enemy flagship — the fleet-wide morale shock + permanent
  −1 + loss of the command net turns the battle. Two conclusions:
  - **Rules:** decapitation is strong *by design* (GDD §5.6) and its counter — flagship
    positioning — is real, playable, and skill-expressive. No rules change needed.
  - **AI (feeds issue #11):** Battle AI v1 needs flagship-preservation behavior — keep
    station behind the engaged line, balance command-radius coverage against exposure,
    withdraw the flagship under threat. Without it every battle vs the AI collapses
    into flagship sniping.
- [ ] Verdict on **open question 1** (emergent wheel vs. need for modifiers)
- [ ] Recommended number tweaks for battle-rules v0.2
- [ ] Verdict on **squadron count** feel (open question 3 — needs a v0.2 page option
      for 5- and 12-squadron fleets)
