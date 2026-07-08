# Paper Prototype — The Selectorate Game v0.1

Solo-playable encoding of GDD §4.5 (the selectorate model: seats, the three-way budget,
the loyalty norm, removal crises) plus a minimal war track so the military budget has
teeth. Purpose: verify the **autocrat/democrat cost symmetry** is fun and fair before
writing engine code, and answer **open question 2** — *is W = 3–12 the right span, and
is the survival threshold a constant or itself draw-randomized?* (issue #2, GDD §12
Phase 0b).

The design bet being tested: the theory's asymmetries need **no modifiers** — they fall
out of one division (private goods ÷ W) and one ratio (S ÷ W). If a junta and a republic
both play tensely from the same rulebook, the bet pays.

**Play it in the browser:** https://tharak.github.io/Battleships/prototypes/selectorate.html
(source `docs/prototypes/selectorate.html`, same engine as the sim). For table play you
need: seat cards, a d3 (d6 halved), budget tokens, and three tracks (front, grievance,
treasury). Fractional numbers below are exact in the digital version; on paper, round in
the house's favor and don't sweat it.

---

## 1. You, the ruler

You inherit a **regime**: **W seats** (your winning coalition, 3–12 cards) and a
**selectorate S** (% of the population with a formal say). You hold **5 planets**
(revenue 2 each), a **treasury of 5**, a **war front at 10** on a 0–20 track (higher is
worse), and a populace **grievance of 30** (0–100).

**Win:** still in power after **12 turns** (years). Score = treasury + 5 × planets +
(20 − front).
**Lose:** a removal crisis succeeds (coup / voted out), or all planets fall (conquered).

Each seat card has:

- **Type:** *individual* (a person: police chief, admiral, magnate) or *bloc* (a mass
  constituency: assembly, unions, veterans). Number of blocs = `round(W × (W−3) ÷ 9)` —
  W=3 is all individuals, W=12 all blocs, the middle is mixed.
- **Satisfaction** 0–100, start **60**. Satisfied = **50+**.

## 2. Turn sequence

1. **Regime action** (optional, one): purge / broaden / expand / restrict (§7).
2. **Set tax** and collect **revenue**; add treasury if you want to overspend savings.
3. **Split the budget** — Military / Private goods / Public goods. The whole game is
   this slider.
4. **War turn** (§4), then **pay the seats** (§5), then **populace** (§6).
5. **Removal-crisis check** (§8).

## 3. Tax & revenue

Revenue = planets × 2 × tax multiplier, minus unrest (§6).

| Tax | Multiplier | Populace grievance / turn | Bloc seats' anger / turn |
|---|---|---|---|
| Low | ×0.8 | +0 | −0 |
| Medium | ×1.0 | +2 | −1 |
| High (punitive) | ×1.3 | +5 | −3 |

Punitive taxation is politically *cheap* only when nobody at your table answers to
taxpayers — exactly the theory.

## 4. The war track (0–20, start 10, higher = worse)

- Enemy pressure each turn: **1d3 + (turn ÷ 4, rounded down)** — the war escalates —
  **+1** if the populace is in revolt (grievance ≥ 80).
- Your pushback: **0.6 × military spend × corruption** + **morale**.
  - **Corruption skim:** ×(1 − 0.06 × number of *individual* seats), floor ×0.5 —
    cronies steal materiel. A junta's army costs ~20% more per unit of front held.
  - **Volunteer morale:** +0.15 × public-goods spend (max +1.5) — well-treated
    populations crew better fleets.
- Front moves by (pressure − pushback), clamped 0–20.
- **Front ≥ 14:** lose a planet (revenue −2 permanently), front eases −4, grievance +10,
  **every seat −10**. No planets left = conquered.
- **Front ≤ 4:** take an enemy planet (max +2 over start), front stretches +4.

## 5. Paying the seats

All satisfaction changes happen once per turn, then clamp 0–100.

- **Drift −3** for everyone, every turn (appetites grow; yesterday's favors are
  forgotten).
- **Individuals:** private-goods **share = Private ÷ W** (the division that runs the
  whole theory — blocs get a share too, they just can't use it: broadening dilutes).
  Satisfaction **+8 × (share − 1.0)**, clamped ±12. Appetite is 1.0/seat/turn.
- **Blocs:** satisfaction **+6 × (Public − 4) ÷ 4**, clamped ±12; **minus tax anger**
  (§3); **−4** any turn the front worsens by 2+ (casualties).
- **Planet lost:** −10, everyone (already counted above).

## 6. The populace (grievance 0–100, start 30)

Each turn: **+1** naturally, **+tax grievance** (§3), **−1.2 × Public spend**,
**+10 per planet lost**.

- **≥ 60 — unrest:** revenue −1.
- **≥ 80 — revolt:** revenue −2 and war pressure +1 (troops watch the streets).

The populace never removes you directly — that's what your seats are for. It just
bleeds you until they do.

## 7. Regime actions (one per turn, each opens a 2-turn **instability window**:
survival threshold +10 percentage points)

| Action | Effect | Cost / risk |
|---|---|---|
| **Purge** (W>3) | Remove your least-satisfied seat; loot +2 treasury | If the victim was *satisfied*, every other seat −5 (panic) |
| **Broaden** (W<12) | Add a seat (type per the bloc formula) at satisfaction 55 | Every existing seat −5; everyone's share dilutes |
| **Expand franchise** | S +15pp; grievance −5 (inclusion) | Loyalty math shifts; expectations follow |
| **Restrict franchise** | S −15pp | Grievance +10, permanent resentment |

## 8. The loyalty norm & removal crises

**Loyalty = min(1, S% ÷ (10 × W))** — replaceability. A machine state (S 60%, W 3)
pins loyalty at 1.0: any crony can be swapped for a million party members, so nobody
plots. An aristocratic republic (S 10%, W 9) gives 0.11: *they* are irreplaceable,
*you* aren't.

**Check each turn:** if the fraction of satisfied seats < **survival threshold (50%**,
+10pp during instability**)**, a crisis fires. Every dissatisfied seat decides to move
against you with probability:

- *Individual:* **(1 − loyalty) × anger** — plotters risk their necks, the norm
  protects you.
- *Bloc:* **anger** — voting you out costs voters nothing. No loyalty shield at the
  ballot box.

where anger = (50 − satisfaction) ÷ 50.

- **Movers outnumber the rest → you are removed.** Coup if your coalition is mostly
  individuals, voted out if mostly blocs. Game over.
- **Otherwise, the plot fails:** the ringleader (lowest satisfaction) is purged from
  the coalition (W−1), remaining dissatisfied seats are bought off (+10), and you get
  an instability window. Survive it — but if failed plots whittle W below 3, the state
  collapses into a coup anyway.

## 9. Scenarios

| # | Scenario | W | S | Feel |
|---|---|---|---|---|
| 1 | **Junta** | 3 | 5% | Cheap cronies, corrupt army, loyalty is middling — purge fast, tax hard, watch the rot |
| 2 | **Machine state** | 3 | 60% | The coup-proofed autocracy: loyalty 1.0. Your only enemies are the war and the ledger |
| 3 | **Oligarchy** | 6 | 30% | Mixed table: cronies *and* blocs both want feeding. The middle is expensive |
| 4 | **Aristocratic republic** *(hard)* | 9 | 10% | Bold, irreplaceable essentials. Sim survival: 17%. Good luck |
| 5 | **Broad republic** | 12 | 85% | All blocs: public goods or the ballot box. Casualties are votes |
| 6 | **Random draw** | 3–12 | 5–85% | The balanced-random-starts preview: read your regime, then govern it |

## 10. Playtest protocol

Play scenarios 1, 3, and 5 at least twice each; then 4 once (to feel the loyalty norm's
teeth) and 6 a few times. Use the auto-advisor (watch mode) to see the archetype lines.
Record result lines, and — most important — **what you found yourself wanting to do**.

**Questions to answer:**

1. **Cost symmetry:** do junta and republic runs feel *different but comparably tense*?
   Does either pole feel like the obviously correct way to play?
2. **Open question 2a — the W span:** is 3–12 seats right? Is the W=9–11 valley
   (expensive politics + bold essentials) interesting-hard or just unfair?
3. **Open question 2b — the threshold:** the sim says randomizing it (40–60%) changes
   nothing measurable. Does a constant, visible 50% line *feel* right in play?
4. **Steering:** did you ever *want* to purge/broaden/move the franchise mid-game, or
   are regime actions dead weight?
5. **The war dial:** does the escalating front force real budget pain, or is it
   background noise?
6. **Fun check:** did you want another run after game 3?

---

## 11. Playtest notes

### 11.a Simulated baseline — `prototypes/selectorate_sim.py`

The exact rules above, played by scripted archetype strategies (dumb, consistent hands —
the political equivalent of the battle sim's advance-and-shoot AI). 1000 campaigns per
row, seed 42; reproduce with `python3 prototypes/selectorate_sim.py`.

**Cost symmetry (the north-star test):**

| strategy | W | S | survived | coup | voted out | conquered |
|---|---|---|---|---|---|---|
| autocrat (matched) | 3 | 5% | **94%** | 6% | 0% | 0% |
| democrat (matched) | 12 | 85% | **90%** | 0% | 9% | 0% |
| oligarch (adaptive) | 6 | 30% | **89%** | 10% | 0% | 0% |
| autocrat→public goods (MISMATCH) | 3 | 5% | **0%** | 100% | 0% | 0% |
| democrat→private goods (MISMATCH) | 12 | 85% | **0%** | 52% | 47% | 0% |

**W sweep (adaptive strategy, S = 30%):** 3→100%, 4→96%, 5→92%, 6→91%, 7→82%, 8→79%,
**9→61%, 10→54%, 11→58%**, 12→100%.

**Threshold, constant 50% vs randomized 40–60% per game:** autocrat 93% vs 92%;
democrat 91% vs 91%.

**Loyalty norm sanity (adaptive hands everywhere):** machine state (W3, S60) 100% ·
junta (W3, S5) 49% · aristocratic republic (W9, S10) **17%** · broad republic (W12,
S85) 99%.

**Headline findings:**

1. **The cost symmetry holds with zero modifiers.** Matched archetypes land within
   5 points of each other (94/90/89), and *both* mismatched strategies die: a junta
   funding schools loses its cronies (100% coups), a democracy shoveling private goods
   at bloc seats gets voted out or couped (0% survival). The theory's asymmetry is pure
   arithmetic: one division and one ratio. **Encouraging for the Phase 0b bet.**
2. **The 3–12 span is playable with a deliberate valley.** Both poles are safe in
   competent hands; W=9–11 sags to 54–61% because mixed tables must pay the diluted
   private bill *and* the public bill while their loyalty norm weakens. That is the
   GDD's "dangerous middle" (§4.5 steering) — emergent, not scripted. Provisional
   answer to **OQ2a: keep 3–12**; the valley is a feature if human play confirms it
   feels tense rather than hopeless.
3. **Randomizing the survival threshold adds nothing** (≤1 point everywhere). The
   crisis machinery already carries the variance. Provisional answer to **OQ2b: keep it
   constant and visible** — legibility beats hidden dice. Human check pending.
4. **The loyalty norm is the strongest single lever in the game.** Same hands, same W:
   S 60% → 100% survival, S 10% → 17%. At W=6 there is a stability *cliff* between
   S=25% (30%) and S=35% (95%). Franchise actions move S by 15 points — the sharpest
   knife on the table. Watch for degenerate franchise-spam in human play.
5. **Tax has texture.** Medium tax can beat low even at W=12 — the extra revenue buys
   more bloc satisfaction than the tax anger costs. The slider is not a solved dial.
6. **Autocrats bank, democrats budget.** Matched-autocrat average score is 56 vs the
   democrat's 24 — cheap coalitions hoard treasure; broad ones convert it to survival.
   Score symmetry (unlike survival symmetry) is *not* a design goal, but worth watching.

*Sim limitations:* scripted hands never steer W/S mid-game, never react to a bad front
beyond a fixed rule, and never time regime actions around instability windows —
everything the human playtest is for.

### 11.b Human playtests — DONE (the human half of issue #2)

- [x] Result lines & answers to questions 1–6 (§10)

  ```text
  2026-07-08  Junta | play | survived | turns=12 | score=51 | W=3 S=5%  | planets=7 front=5  grievance=24
  2026-07-08  Junta | play | coup     | turns=3  |          | W=3 S=5%  | planets=7 front=0  grievance=48
  2026-07-08  Junta | play | coup     | turns=4  |          | W=3 S=20% | planets=5 front=11 grievance=0
  2026-07-08  Junta | play | coup     | turns=7  |          | W=2 S=5%  | planets=4 front=10 grievance=29
  2026-07-08  Machine state | play | survived ×2 (scores 52, 38)
  2026-07-08  Oligarchy | play | survived | W=3 S=30% | planets=2 front=13 grievance=96 | score=17
  2026-07-08  Oligarchy | play | survived | W=4 S=30% | planets=7 front=8  grievance=0  | score=47
  2026-07-08  Aristocratic republic | play | coup ×2 (turns 8 and 11; one whittled to W=2)
  2026-07-08  Broad republic | play | survived ×2 (scores 48, 54; ended W=8 and W=9)
  2026-07-08  Random draw | play ×2 + watch:adaptive ×2 | survived ×4
  ```

  **16 games, 11 survived.** Player verdict: *"I think it's working well."* The lines
  carry more than the tally:

  - **The junta went 1–3 in human hands** against the autocrat doctrine's 94% — the
    sim's script *knows* to pay the cronies first; a human learns it by dying. One run
    tried expanding the franchise (S 5→20%) and still fell; one was whittled to W=2 by
    failed plots. Sharpest skill curve of the set, like spindle-vs-line in the battle
    prototype.
  - **Steering got used, unprompted, and it won games.** Both oligarchy wins came from
    regime actions: one purged the coalition from 6 down to 3 — deliberately collapsing
    an oligarchy into a junta — and scraped through with 2 planets and grievance 96;
    the other trimmed to W=4 and kept the populace at 0 grievance. Regime actions are
    not dead weight.
  - **The predictions held at every preset:** machine state 2–0 (coup-proof as
    designed), aristocratic republic 0–2 (17% sim; the loyalty norm's teeth are real),
    broad republic 2–0 (casualties-are-votes never got fatal), random draws 4–0.
  - **The war dial bites:** across runs planets ranged 2–7 and fronts 0–13 — the
    military slice was never safely ignorable.

- [x] Verdict on **open question 2** — see 11.c
- [x] Verdict on **cost symmetry** — see 11.c
- [x] Number tweaks for v0.2 — none requested; v0.1 numbers stand

### 11.c Final verdict (closes issue #2)

Answers to the §10 questions:

1. **Cost symmetry: PASS.** Both poles won games from the same rulebook and play
   completely differently — the junta is pay-the-cronies-first brinkmanship, the
   republic is a public-goods budget puzzle. Neither is the obviously correct pole
   (sim: 94/90; human: both survivable, junta harder to *learn*).
2. **Open question 2a — W span: keep 3–12.** Every band got played: poles safe in
   competent hands, the W=9–11 valley and the low-S trap punishing but legible. No run
   suggested the span is wrong. **CLOSED.**
3. **Open question 2b — survival threshold: constant and visible.** Randomizing it
   moved nothing in the sim (≤1pp) and the fixed 50% line reads clearly in play; the
   crisis system already supplies the variance. **CLOSED.**
4. **Steering: real and load-bearing** — purging an oligarchy down to a junta was a
   winning human line on day one. *Watch-item for Phase 4:* shrinking W looks strong
   (cheaper politics, only instability windows as the price). The full game must make
   coup insurance and the excluded seats' clients cost more, or purge-down becomes the
   universal opener.
5. **The war dial forces real budget pain** — planet counts swung 2–7 across runs.
6. **Fun: 16 voluntary games** including replays of lost scenarios. Passed.

**Carried forward:** the purge-down dominance watch-item (Phase 4, issue for the
selectorate build); franchise-spam watch-item from §11.a finding 4; election events vs
continuous checks (GDD open question 7) untouched by design — v0.1's continuous check
was fine at this fidelity.
