#!/usr/bin/env python3
"""Monte-Carlo baseline for the selectorate game prototype
(docs/prototypes/selectorate-game.md, GDD section 4.5, issue #2, Phase 0b).

Implements selectorate-game rules v0.1 exactly: three-way budget split
(military / private goods / public goods), seats with satisfaction, the loyalty
norm (replaceability = S/W), removal crises, the abstract war track, populace
grievance, and regime actions (purge / broaden / franchise) — played by scripted
archetype strategies. Purpose: measure whether autocrat and democrat cost of
power is roughly symmetric (GDD's playtest north star) and gather data for open
question 2 (is W = 3-12 the right span; constant vs randomized survival
threshold) before human play. No dependencies. Deterministic per seed.

Usage: python3 selectorate_sim.py [--trials N] [--seed S]
"""

import argparse
import random

# --- constants (rules v0.1) ---------------------------------------------------

TURNS = 12                 # campaign length (years); survive them all to win
SAT_START = 60
SAT_LINE = 50              # satisfied at or above this
DRIFT = -3                 # per-turn satisfaction decay (appetites grow)
APPETITE = 1.0             # private-goods units per seat per turn to break even
IND_GAIN = 8               # sat delta per unit of private share above/below appetite
BLOC_NEED = 4.0            # public-goods units per turn to keep blocs level
BLOC_GAIN = 6              # sat delta scale for public goods vs need
SAT_DELTA_CLAMP = 12

THRESHOLD = 0.50           # weighted support below this -> removal crisis
INSTABILITY_BONUS = 0.10   # threshold bump during instability windows
INSTABILITY_TURNS = 2
PLOT_BASE = 1.0            # plot-join probability scale (times disloyalty & anger)

BASE_PLANETS = 5
REV_PER_PLANET = 2
TAX = {"low": (0.8, 0), "medium": (1.0, 2), "high": (1.3, 5)}  # mult, grievance/turn

FRONT_START = 10           # war track 0..20; higher is worse for you
FRONT_MAX = 20
FRONT_LOSE = 14            # front at/above this -> lose a planet, front eases 4
FRONT_WIN = 4              # front at/below this -> take a planet, front stretches 4
MIL_EFF = 0.6              # front pushback per military unit
SKIM = 0.06                # corruption: military effect lost per individual seat
MORALE = 0.15              # volunteer quality: front pushback per public-goods unit
MORALE_CAP = 1.5
TAX_BLOC_ANGER = {"low": 0, "medium": 1, "high": 3}  # blocs punish taxation
CASUALTY_REVERSE = 2       # front must worsen by this much to count as a reverse

GRIEV_START = 30
GRIEV_NATURE = 1           # per-turn baseline growth
GRIEV_PUB = 1.2            # grievance relief per public-goods unit
GRIEV_UNREST = 60          # at/above: unrest, -1 revenue
GRIEV_REVOLT = 80          # at/above: revolt, -2 revenue, front +1, blocs -5

PLANET_LOSS_SAT = -10      # every seat, when a planet falls
PLANET_LOSS_GRIEV = 10
CASUALTY_BLOC_SAT = -4     # blocs, any turn the front worsened

PURGE_LOOT = 2             # treasury seized from a purged seat
PURGE_PANIC = -5           # other seats' sat when a *satisfied* seat is purged
BROADEN_SAT = -5           # existing seats' sat when a new seat joins
NEW_SEAT_SAT = 55
FRANCHISE_STEP = 0.15      # S change per franchise action


def n_blocs(w):
    """Seats that are mass blocs rather than individuals. Small W: cronies;
    large W: constituencies (GDD 4.5). 3->0, 6->2, 9->6, 12->12."""
    return min(w, round(w * (w - 3) / 9))


def loyalty(s, w):
    """The loyalty norm: replaceability = S/W, normalized so a machine state
    (huge S, tiny W) pins to 1 and an aristocratic republic lands near 0."""
    return min(1.0, (s * 100) / (w * 10))


class Seat:
    __slots__ = ("kind", "sat")

    def __init__(self, kind, sat=SAT_START):
        self.kind = kind  # "ind" | "bloc"
        self.sat = sat


class Regime:
    def __init__(self, w, s, rng, threshold=THRESHOLD):
        blocs = n_blocs(w)
        self.seats = [Seat("bloc" if i < blocs else "ind") for i in range(w)]
        self.s = s
        self.threshold = threshold
        self.instability = 0
        self.rng = rng

    @property
    def w(self):
        return len(self.seats)

    def support(self):
        if not self.seats:
            return 0.0
        return sum(1 for x in self.seats if x.sat >= SAT_LINE) / len(self.seats)

    def effective_threshold(self):
        return self.threshold + (INSTABILITY_BONUS if self.instability > 0 else 0)


class Game:
    """One campaign. step() advances a turn given a decision dict:
    {tax, mil, priv, pub, action} where action is None or
    ("purge",) | ("broaden",) | ("expand",) | ("restrict",)."""

    def __init__(self, w, s, rng, threshold=THRESHOLD):
        self.rng = rng
        self.regime = Regime(w, s, rng, threshold)
        self.planets = BASE_PLANETS
        self.front = FRONT_START
        self.grievance = GRIEV_START
        self.treasury = 5
        self.turn = 0
        self.over = False
        self.result = None  # "survived" | "coup" | "voted_out" | "conquered"
        self.log = []

    # -- economy --
    def revenue(self, tax):
        mult, _ = TAX[tax]
        rev = self.planets * REV_PER_PLANET * mult
        if self.grievance >= GRIEV_REVOLT:
            rev -= 2
        elif self.grievance >= GRIEV_UNREST:
            rev -= 1
        return max(0.0, rev)

    # -- regime actions --
    def act(self, action):
        r = self.regime
        if action is None:
            return
        kind = action[0]
        if kind == "purge" and r.w > 3:
            victim = min(r.seats, key=lambda x: x.sat)
            r.seats.remove(victim)
            self.treasury += PURGE_LOOT
            if victim.sat >= SAT_LINE:  # purging the loyal panics the rest
                for x in r.seats:
                    x.sat = max(0, x.sat + PURGE_PANIC)
            r.instability = INSTABILITY_TURNS
        elif kind == "broaden" and r.w < 12:
            for x in r.seats:
                x.sat = max(0, x.sat + BROADEN_SAT)
            blocs = n_blocs(r.w + 1)
            have = sum(1 for x in r.seats if x.kind == "bloc")
            r.seats.append(Seat("bloc" if have < blocs else "ind", NEW_SEAT_SAT))
            r.instability = INSTABILITY_TURNS
        elif kind == "expand":
            r.s = min(1.0, r.s + FRANCHISE_STEP)
            self.grievance = max(0, self.grievance - 5)
            r.instability = INSTABILITY_TURNS
        elif kind == "restrict":
            r.s = max(0.02, r.s - FRANCHISE_STEP)
            self.grievance += 10
            r.instability = INSTABILITY_TURNS

    # -- one turn --
    def step(self, d):
        assert not self.over
        self.turn += 1
        r = self.regime
        rng = self.rng

        self.act(d.get("action"))

        rev = self.revenue(d["tax"])
        mil, priv, pub = d["mil"], d["priv"], d["pub"]
        spend = mil + priv + pub
        budget = rev + self.treasury
        if spend > budget:  # can't spend money you don't have: scale down
            k = budget / spend if spend else 0
            mil, priv, pub = mil * k, priv * k, pub * k
            spend = budget
        self.treasury = budget - spend

        # war track (the war escalates: +1 pressure every 4 turns)
        pressure = rng.randint(1, 3) + self.turn // 4 \
            + (1 if self.grievance >= GRIEV_REVOLT else 0)
        n_ind = sum(1 for x in r.seats if x.kind == "ind")
        skim = max(0.5, 1 - SKIM * n_ind)   # cronies steal materiel
        effect = MIL_EFF * mil * skim + min(MORALE_CAP, MORALE * pub)
        front_before = self.front
        self.front = max(0.0, min(FRONT_MAX, self.front + pressure - effect))
        lost_planet = False
        if self.front >= FRONT_LOSE:
            self.planets -= 1
            lost_planet = True
            self.front -= 4
            self.grievance += PLANET_LOSS_GRIEV
            if self.planets <= 0:
                self.over, self.result = True, "conquered"
                return
        elif self.front <= FRONT_WIN and self.planets < BASE_PLANETS + 2:
            self.planets += 1
            self.front += 4

        # seats
        share = priv / r.w if r.w else 0
        for x in r.seats:
            delta = DRIFT
            if x.kind == "ind":
                delta += max(-SAT_DELTA_CLAMP,
                             min(SAT_DELTA_CLAMP, IND_GAIN * (share - APPETITE)))
            else:
                delta += max(-SAT_DELTA_CLAMP,
                             min(SAT_DELTA_CLAMP,
                                 BLOC_GAIN * (pub - BLOC_NEED) / BLOC_NEED))
                delta -= TAX_BLOC_ANGER[d["tax"]]
                if self.front - front_before >= CASUALTY_REVERSE:
                    delta += CASUALTY_BLOC_SAT
            if lost_planet:
                delta += PLANET_LOSS_SAT
            x.sat = max(0, min(100, x.sat + delta))

        # populace
        _, tax_grief = TAX[d["tax"]]
        self.grievance = max(0, min(100, self.grievance + GRIEV_NATURE
                                    + tax_grief - GRIEV_PUB * pub))

        # removal crisis
        if r.instability > 0:
            r.instability -= 1
        if r.support() < r.effective_threshold():
            loy = loyalty(r.s, r.w)
            plotters = loyal = 0
            for x in r.seats:
                anger = (SAT_LINE - x.sat) / SAT_LINE
                # individuals risk their necks -> damped by the loyalty norm;
                # blocs "plot" at the ballot box, which costs voters nothing
                p = anger if x.kind == "bloc" else (1 - loy) * anger
                if x.sat < SAT_LINE and rng.random() < PLOT_BASE * p:
                    plotters += 1
                else:
                    loyal += 1
            if plotters > loyal:
                self.over = True
                self.result = "voted_out" if n_blocs(r.w) > r.w / 2 else "coup"
                return
            if plotters:  # failed plot: ringleader purged, the rest bought off
                victim = min((x for x in r.seats if x.sat < SAT_LINE),
                             key=lambda x: x.sat)
                r.seats.remove(victim)
                for x in r.seats:
                    if x.sat < SAT_LINE:
                        x.sat = min(100, x.sat + 10)
                r.instability = INSTABILITY_TURNS
                if r.w < 3:
                    self.over, self.result = True, "coup"  # no coalition left
                    return

        if self.turn >= TURNS:
            self.over, self.result = True, "survived"

    def score(self):
        return round(self.treasury + self.planets * 5 + (FRONT_MAX - self.front))


# --- strategies ----------------------------------------------------------------
# A strategy maps game state -> decision dict. All are deliberately simple
# rules of thumb, like the battle sim's dumb AI: the baseline is what the
# arithmetic gives us, human cunning comes on top.

def hold_front_mil(g, pub_planned=0.0):
    """Military units to spend so the expected front drifts gently down,
    accounting for the regime's own corruption skim and volunteer morale."""
    expected = 2.2 + (g.turn + 1) // 4  # keeps pace with the escalating war
    n_ind = sum(1 for x in g.regime.seats if x.kind == "ind")
    skim = max(0.5, 1 - SKIM * n_ind)
    need = expected - min(MORALE_CAP, MORALE * pub_planned)
    return max(0.0, need / (MIL_EFF * skim) + (g.front - FRONT_START) * 0.15)


def autocrat(g):
    """W=3 cronies, punitive tax, private goods first, no public goods."""
    rev = g.revenue("high") + min(g.treasury, 2)
    priv = min(rev, g.regime.w * (APPETITE + 0.3))
    mil = min(rev - priv, hold_front_mil(g))
    return {"tax": "high", "mil": mil, "priv": priv, "pub": 0,
            "action": ("purge",) if g.regime.w > 3 else None}


def democrat(g):
    """W=12 blocs, low tax, public goods first, no private goods."""
    rev = g.revenue("low") + min(g.treasury, 2)
    pub = min(rev, BLOC_NEED + 1.5)
    mil = min(rev - pub, hold_front_mil(g, pub))
    return {"tax": "low", "mil": mil, "priv": 0, "pub": pub,
            "action": ("broaden",) if g.regime.w < 12 else None}


def autocrat_public(g):
    """MISMATCH: a W=3 junta funding public goods and starving its cronies."""
    rev = g.revenue("medium") + min(g.treasury, 2)
    pub = min(rev, BLOC_NEED + 1.5)
    mil = min(rev - pub, hold_front_mil(g, pub))
    return {"tax": "medium", "mil": mil, "priv": 0, "pub": pub, "action": None}


def democrat_private(g):
    """MISMATCH: a W=12 democracy shoveling private goods at bloc seats."""
    rev = g.revenue("high") + min(g.treasury, 2)
    priv = min(rev, g.regime.w * APPETITE)
    mil = min(rev - priv, hold_front_mil(g))
    return {"tax": "high", "mil": mil, "priv": priv, "pub": 0, "action": None}


def adaptive(g):
    """Pay whoever the regime shape says to pay; medium tax; front third.
    Used for the W sweep — the same sane hands at every coalition size."""
    r = g.regime
    inds = sum(1 for x in r.seats if x.kind == "ind")
    blocs = r.w - inds
    rev = g.revenue("medium") + min(g.treasury, 3)
    want_priv = r.w * (APPETITE + 0.3) if inds else 0     # share dilutes over all W
    want_pub = BLOC_NEED + 1.0 if blocs else 0
    mil = min(rev, hold_front_mil(g, want_pub))
    rest = rev - mil
    if want_priv + want_pub <= rest:
        priv, pub = want_priv, want_pub
    elif want_priv + want_pub > 0:  # can't afford both: split by need
        k = rest / (want_priv + want_pub)
        priv, pub = want_priv * k, want_pub * k
    else:
        priv = pub = 0
    return {"tax": "medium", "mil": mil, "priv": priv, "pub": pub, "action": None}


ARCHETYPES = [
    ("autocrat (matched)", autocrat, 3, 0.05),
    ("democrat (matched)", democrat, 12, 0.85),
    ("oligarch (adaptive)", adaptive, 6, 0.30),
    ("autocrat->public (MISMATCH)", autocrat_public, 3, 0.05),
    ("democrat->private (MISMATCH)", democrat_private, 12, 0.85),
]


# --- experiments ----------------------------------------------------------------

def run(strategy, w, s, trials, rng, threshold=None):
    outcomes = {"survived": 0, "coup": 0, "voted_out": 0, "conquered": 0}
    score = 0
    for _ in range(trials):
        th = threshold if threshold is not None else THRESHOLD
        if threshold == "random":
            th = rng.uniform(0.40, 0.60)
        g = Game(w, s, rng, th)
        while not g.over:
            g.step(strategy(g))
        outcomes[g.result] += 1
        if g.result == "survived":
            score += g.score()
    surv = outcomes["survived"]
    return outcomes, (score / surv if surv else 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=1000)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    N = args.trials

    print(f"selectorate_sim — trials={N}, seed={args.seed}, rules v0.1, "
          f"{TURNS}-turn campaigns\n")

    print("## Cost symmetry (matched archetypes should be close; mismatches should fail)\n")
    print("| strategy | W | S | survived | coup | voted out | conquered | avg score |")
    print("|---|---|---|---|---|---|---|---|")
    for name, strat, w, s in ARCHETYPES:
        o, sc = run(strat, w, s, N, rng)
        print(f"| {name} | {w} | {int(s * 100)}% | {100 * o['survived'] // N}% "
              f"| {100 * o['coup'] // N}% | {100 * o['voted_out'] // N}% "
              f"| {100 * o['conquered'] // N}% | {sc:.0f} |")

    print("\n## W sweep, adaptive strategy, S=0.30 (open question 2: is 3-12 playable?)\n")
    print("| W | blocs | loyalty | survived | coup | voted out | conquered |")
    print("|---|---|---|---|---|---|---|")
    for w in range(3, 13):
        o, _ = run(adaptive, w, 0.30, N, rng)
        print(f"| {w} | {n_blocs(w)} | {loyalty(0.30, w):.2f} "
              f"| {100 * o['survived'] // N}% | {100 * o['coup'] // N}% "
              f"| {100 * o['voted_out'] // N}% | {100 * o['conquered'] // N}% |")

    print("\n## Survival threshold: constant 50% vs randomized 40-60% per game\n")
    for name, strat, w, s in ARCHETYPES[:2]:
        oc, _ = run(strat, w, s, N, rng, threshold=THRESHOLD)
        orand, _ = run(strat, w, s, N, rng, threshold="random")
        print(f"{name:>22}: constant {100 * oc['survived'] // N}% · "
              f"randomized {100 * orand['survived'] // N}%")

    print("\n## Loyalty norm sanity (machine state vs aristocratic republic, adaptive)\n")
    for label, w, s in [("machine state (W=3, S=60%)", 3, 0.60),
                        ("junta (W=3, S=5%)", 3, 0.05),
                        ("aristocratic republic (W=9, S=10%)", 9, 0.10),
                        ("broad republic (W=12, S=85%)", 12, 0.85)]:
        o, _ = run(adaptive, w, s, N, rng)
        print(f"{label:>36}: loyalty {loyalty(s, w):.2f} · "
              f"survived {100 * o['survived'] // N}% · coup {100 * o['coup'] // N}% · "
              f"voted out {100 * o['voted_out'] // N}%")


if __name__ == "__main__":
    main()
