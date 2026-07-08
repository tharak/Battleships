#!/usr/bin/env python3
"""Monte-Carlo baseline for the paper battle rules (docs/prototypes/battle-rules.md).

Implements battle-rules v0.1 exactly — arcs, facing, LOS masking, morale ladder,
command radius, supply — with deliberately DUMB handling: every squadron advances
toward the nearest enemy and shoots when it can. No maneuvering cleverness, no
formation-keeping. Purpose: measure what the geometry alone gives us (GDD open
question 1) before table play. No dependencies. Deterministic per seed.

Usage: python3 battle_sim.py [--trials N] [--seed S]
"""

import argparse
import math
import random

SQRT3_2 = math.sqrt(3) / 2
BOARD_COLS, BOARD_ROWS = 24, 18
CUBE_DIRS = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)]  # axial (q, r)
DIR_ANGLE = [0.0, -60.0, -120.0, 180.0, 120.0, 60.0]  # cartesian angle of each dir
RANGE = 3
CMD_RADIUS = 4
MP = 3
BREAK_LOSSES = 5
MAX_TURNS = 40


# --- hex math (odd-r offset storage, axial for distances) --------------------

def to_axial(col, row):
    return col - (row - (row & 1)) // 2, row


def from_axial(q, r):
    return q + (r - (r & 1)) // 2, r


def hex_dist(a, b):
    aq, ar = to_axial(*a)
    bq, br = to_axial(*b)
    dq, dr = aq - bq, ar - br
    return (abs(dq) + abs(dr) + abs(dq + dr)) // 2


def neighbor(pos, d):
    q, r = to_axial(*pos)
    dq, dr = CUBE_DIRS[d]
    return from_axial(q + dq, r + dr)


def to_cart(pos):
    col, row = pos
    return col + 0.5 * (row & 1), row * SQRT3_2


def angle_between(frm, to):
    fx, fy = to_cart(frm)
    tx, ty = to_cart(to)
    return math.degrees(math.atan2(ty - fy, tx - fx))


def rel_angle(facing, frm, to):
    """Unsigned angle between `frm`'s facing and the direction to `to`."""
    a = angle_between(frm, to) - DIR_ANGLE[facing]
    a = (a + 180.0) % 360.0 - 180.0
    return abs(a)


def incoming_arc(target, firer_pos):
    """Arc of the TARGET the fire comes into. Seams favor the shooter."""
    a = rel_angle(target.facing, target.pos, firer_pos)
    if a < 90.0 - 1e-9:
        return "front"
    if a < 150.0 - 1e-9:
        return "flank"
    return "rear"


def in_fire_arc(firer, target_pos):
    """Shooter's front arc (faced hexside + 2 adjacent = 180 deg, seams favor shooter)."""
    return rel_angle(firer.facing, firer.pos, target_pos) <= 90.0 + 1e-9


def cube_lerp_round(a, b, t):
    aq, ar = to_axial(*a)
    bq, br = to_axial(*b)
    q = aq + (bq - aq) * t
    r = ar + (br - ar) * t
    s = -q - r
    rq, rr, rs = round(q), round(r), round(s)
    dq, dr, ds = abs(rq - q), abs(rr - r), abs(rs - s)
    if dq > dr and dq > ds:
        rq = -rr - rs
    elif dr > ds:
        rr = -rq - rs
    return from_axial(rq, int(rr))


def los_clear(a, b, occupied):
    """Beam LOS blocked by any squadron between. Edge cases favor the shooter."""
    n = hex_dist(a, b)
    if n <= 1:
        return True
    for eps in (1e-6, -1e-6):
        clear = True
        for i in range(1, n):
            aq, ar = to_axial(*a)
            bq, br = to_axial(*b)
            t = i / n
            q = aq + (bq - aq) * t + eps
            r = ar + (br - ar) * t + eps / 2
            s = -q - r
            rq, rr, rs = round(q), round(r), round(s)
            dq, dr, ds = abs(rq - q), abs(rr - r), abs(rs - s)
            if dq > dr and dq > ds:
                rq = -rr - rs
            elif dr > ds:
                rr = -rq - rs
            h = from_axial(int(rq), int(rr))
            if h != a and h != b and h in occupied:
                clear = False
                break
        if clear:
            return True
    return False


# --- units -------------------------------------------------------------------

STEADY, SHAKEN, ROUTED = 0, 1, 2


class Squadron:
    __slots__ = ("side", "pos", "facing", "strength", "state", "flag",
                 "hit_since_act", "alive", "exited")

    def __init__(self, side, pos, facing, flag=False):
        self.side = side
        self.pos = pos
        self.facing = facing
        self.strength = 4
        self.state = STEADY
        self.flag = flag
        self.hit_since_act = False
        self.alive = True
        self.exited = False


class Fleet:
    def __init__(self, name, units, low_supply=False):
        self.name = name
        self.units = units
        self.low_supply = low_supply
        self.flag_lost = False

    def losses(self):
        return sum(1 for u in self.units if not u.alive)

    def flagship(self):
        for u in self.units:
            if u.flag and u.alive:
                return u
        return None


# --- formations (fwd, lat, dfacing) ; dfacing: 0 straight, +1 toward +lat ----

def formation_layout(name):
    if name == "line":
        return [(0, l, 0) for l in range(-4, 5)], 4
    if name == "spindle":  # diamond 1-2-3-2-1, deep and narrow
        sp = [(2, 0, 0), (1, -1, 0), (1, 1, 0), (0, -1, 0), (0, 0, 0), (0, 1, 0),
              (-1, -1, 0), (-1, 1, 0), (-2, 0, 0)]
        return sp, 4
    if name == "crescent":  # wings advanced, angled inward
        out = []
        for l in range(-4, 5):
            fwd = 2 if abs(l) >= 3 else (1 if abs(l) == 2 else 0)
            df = 1 if l <= -2 else (-1 if l >= 2 else 0)
            out.append((fwd, l, df))
        return out, 4
    if name == "echelon":  # refused flank diagonal
        return [(-l, l, 0) for l in range(-4, 5)], 4
    if name == "sphere":  # ring, facing outward; holds position
        ring = [(0, 0, 0)]
        for i, (dc, dl) in enumerate([(1, 0), (1, -1), (0, -1), (-1, -1),
                                      (-1, 0), (-1, 1), (0, 1), (1, 1)]):
            ring.append((dc, dl, 0))
        return ring, 0
    if name == "column":  # single file travel order
        return [(f, 0, 0) for f in range(-4, 5)], 4
    raise ValueError(name)


HOLD_FORMATIONS = {"sphere"}  # doctrine: stand and receive


def deploy(name, side):
    layout, flag_idx = formation_layout(name)
    straight = 0 if side == 0 else 3
    toward_pos_lat = 5 if side == 0 else 4
    toward_neg_lat = 1 if side == 0 else 2
    units = []
    for i, (fwd, lat, df) in enumerate(layout):
        col = (5 + fwd) if side == 0 else (18 - fwd)
        row = 9 + lat
        facing = straight if df == 0 else (toward_pos_lat if df > 0 else toward_neg_lat)
        units.append(Squadron(side, (col, row), facing, flag=(i == flag_idx)))
    if name == "sphere":  # outward ring facings
        center = units[0].pos
        for u in units[1:]:
            ang = angle_between(center, u.pos)
            u.facing = min(range(6), key=lambda d: abs(((DIR_ANGLE[d] - ang + 180) % 360) - 180))
    return units


# --- battle ------------------------------------------------------------------

class Battle:
    def __init__(self, forms, rng, low_supply=(False, False)):
        self.rng = rng
        self.forms = forms
        self.fleets = [Fleet(forms[0], deploy(forms[0], 0), low_supply[0]),
                       Fleet(forms[1], deploy(forms[1], 1), low_supply[1])]

    def occupied(self):
        return {u.pos: u for f in self.fleets for u in f.units if u.alive}

    def enemies(self, side):
        return [u for u in self.fleets[1 - side].units if u.alive]

    def friends(self, u):
        return [v for v in self.fleets[u.side].units if v.alive and v is not u]

    def in_command(self, u):
        fl = self.fleets[u.side].flagship()
        return fl is not None and hex_dist(u.pos, fl.pos) <= CMD_RADIUS

    # -- morale --
    def morale_check(self, u, from_flank_rear=False):
        if not u.alive or u.state == ROUTED:
            return
        mod = 0
        if any(v.state == STEADY and hex_dist(u.pos, v.pos) == 1 for v in self.friends(u)):
            mod += 1
        if self.in_command(u):
            mod += 1
        if from_flank_rear:
            mod -= 1
        if self.fleets[u.side].low_supply:
            mod -= 1
        if self.fleets[u.side].flag_lost:
            mod -= 1
        if self.rng.randint(1, 6) + mod >= 4:
            return
        if u.state == STEADY:
            u.state = SHAKEN
        elif u.state == SHAKEN:
            u.state = ROUTED
            u.facing = 3 if u.side == 0 else 0  # face own edge
            self.contagion(u)

    def contagion(self, source):
        for v in list(self.friends(source)):
            if v.alive and v.state != ROUTED and hex_dist(v.pos, source.pos) <= 2:
                self.morale_check(v)

    def destroy(self, u):
        u.alive = False
        was_flag = u.flag
        self.contagion(u)
        if was_flag:
            self.fleets[u.side].flag_lost = True
            for v in list(self.fleets[u.side].units):
                if v.alive:
                    self.morale_check(v)

    # -- fire --
    def pick_target(self, u):
        occ = self.occupied()
        best = None
        for e in self.enemies(u.side):
            d = hex_dist(u.pos, e.pos)
            if d > RANGE or not in_fire_arc(u, e.pos) or not los_clear(u.pos, e.pos, occ):
                continue
            key = (d, e.strength)
            if best is None or key < best[0]:
                best = (key, e)
        return best[1] if best else None

    def fire(self, u, target):
        dice = u.strength if u.state == STEADY else (u.strength + 1) // 2
        arc = incoming_arc(target, u.pos)
        need = {"front": 5, "flank": 4, "rear": 3}[arc]
        if self.fleets[u.side].low_supply:
            need += 1
        hits = sum(1 for _ in range(dice) if self.rng.randint(1, 6) >= need)
        if hits == 0:
            return
        target.strength = max(0, target.strength - hits)
        target.hit_since_act = True
        if target.strength == 0:
            self.destroy(target)
        else:
            self.morale_check(target, from_flank_rear=(arc != "front"))

    # -- movement --
    def turn_toward(self, u, d):
        diff = (d - u.facing) % 6
        u.facing = (u.facing + (1 if diff <= 3 else -1)) % 6

    def desired_dir(self, u, goal):
        ang = angle_between(u.pos, goal)
        return min(range(6), key=lambda d: abs(((DIR_ANGLE[d] - ang + 180) % 360) - 180))

    def step(self, u):
        """One MP spent advancing toward nearest enemy. True if MP was usable."""
        enemies = self.enemies(u.side)
        if not enemies:
            return False
        goal = min(enemies, key=lambda e: hex_dist(u.pos, e.pos)).pos
        d = self.desired_dir(u, goal)
        if u.facing != d:
            self.turn_toward(u, d)
            return True
        nxt = neighbor(u.pos, d)
        occ = self.occupied()
        if (0 <= nxt[0] < BOARD_COLS and 0 <= nxt[1] < BOARD_ROWS
                and nxt not in occ and hex_dist(nxt, goal) < hex_dist(u.pos, goal)):
            u.pos = nxt
            return True
        return False  # blocked: hold

    def flee(self, u):
        d = 3 if u.side == 0 else 0
        for _ in range(MP):
            if u.facing != d:
                self.turn_toward(u, d)
                continue
            nxt = neighbor(u.pos, d)
            if not (0 <= nxt[0] < BOARD_COLS and 0 <= nxt[1] < BOARD_ROWS):
                u.alive = False
                u.exited = True
                return
            if nxt not in self.occupied():
                u.pos = nxt

    # -- activation --
    def activate(self, u):
        if not u.alive:
            return
        if u.state == ROUTED:
            if not u.hit_since_act:
                bonus = 1 if self.in_command(u) else 0
                if self.rng.randint(1, 6) + bonus >= 4:
                    u.state = SHAKEN
                    u.hit_since_act = False
                    return
            u.hit_since_act = False
            self.flee(u)
            return
        u.hit_since_act = False
        cmd = self.in_command(u)
        hold = self.fleets[u.side].name in HOLD_FORMATIONS
        target = self.pick_target(u)
        if u.state == SHAKEN:
            if target is None and not hold:
                en = self.enemies(u.side)
                if en:  # may turn in place, not approach
                    goal = min(en, key=lambda e: hex_dist(u.pos, e.pos)).pos
                    d = self.desired_dir(u, goal)
                    if u.facing != d:
                        self.turn_toward(u, d)
                target = self.pick_target(u) if cmd else None
            if target is not None:
                self.fire(u, target)
            return
        # steady
        if target is not None:
            self.fire(u, target)
            return
        if hold:
            en = self.enemies(u.side)
            if en:
                goal = min(en, key=lambda e: hex_dist(u.pos, e.pos)).pos
                nearest = hex_dist(u.pos, goal)
                if nearest <= RANGE + 1:  # only rotate once threatened
                    d = self.desired_dir(u, goal)
                    if u.facing != d:
                        self.turn_toward(u, d)
            if cmd:
                target = self.pick_target(u)
                if target is not None:
                    self.fire(u, target)
            return
        for _ in range(MP):
            if not self.step(u):
                break
        if cmd:
            target = self.pick_target(u)
            if target is not None:
                self.fire(u, target)

    def broken(self, side):
        return self.fleets[side].losses() >= BREAK_LOSSES

    def run(self):
        for turn in range(1, MAX_TURNS + 1):
            first = (turn + 1) % 2
            queues = [[u for u in self.fleets[s].units if u.alive] for s in (0, 1)]
            i = [0, 0]
            side = first
            while i[0] < len(queues[0]) or i[1] < len(queues[1]):
                if i[side] < len(queues[side]):
                    self.activate(queues[side][i[side]])
                    i[side] += 1
                    for s in (0, 1):
                        if self.broken(s):
                            return 1 - s, turn
                side = 1 - side
        # draw: score by surviving strength
        s0 = sum(u.strength for u in self.fleets[0].units if u.alive)
        s1 = sum(u.strength for u in self.fleets[1].units if u.alive)
        return (None, MAX_TURNS) if s0 == s1 else (0 if s0 > s1 else 1, MAX_TURNS)


# --- experiments ---------------------------------------------------------------

FORMS = ["spindle", "line", "crescent", "echelon", "sphere", "column"]

WHEEL = [("spindle", "line"), ("line", "crescent"), ("crescent", "spindle"),
         ("echelon", "spindle"), ("sphere", "crescent")]


def run_pair(f1, f2, trials, rng, supply=(False, False)):
    wins = {f1: 0, f2: 0, "draw": 0}
    turns = 0
    for t in range(trials):
        flip = t % 2 == 1
        forms = (f2, f1) if flip else (f1, f2)
        sup = (supply[1], supply[0]) if flip else supply
        w, tn = Battle(forms, rng, sup).run()
        turns += tn
        if w is None:
            wins["draw"] += 1
        else:
            wins[forms[w]] += 1
    return wins, turns / trials


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--trials", type=int, default=400)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    print(f"battle_sim — trials/pair={args.trials}, seed={args.seed}, "
          f"dumb-advance AI, rules v0.1\n")

    print("## Full matrix (row formation win% vs column; rest are losses or draws)\n")
    header = "| vs | " + " | ".join(FORMS) + " |"
    print(header)
    print("|---" * (len(FORMS) + 1) + "|")
    results = {}
    for f1 in FORMS:
        cells = []
        for f2 in FORMS:
            if f1 == f2:
                cells.append("—")
                continue
            key = tuple(sorted((f1, f2)))
            if key not in results:
                results[key] = run_pair(key[0], key[1], args.trials, rng)
            wins, avg_t = results[key]
            pct = 100.0 * wins[f1] / args.trials
            cells.append(f"{pct:.0f}%")
        print(f"| **{f1}** | " + " | ".join(cells) + " |")

    print("\n## Counter-wheel legs (predicted winner listed first)\n")
    print("| Leg | predicted winner win% | loser win% | draws | avg turns |")
    print("|---|---|---|---|---|")
    for a, b in WHEEL:
        key = tuple(sorted((a, b)))
        wins, avg_t = results[key]
        d = 100.0 * wins["draw"] / args.trials
        print(f"| {a} vs {b} | {100.0 * wins[a] / args.trials:.0f}% | "
              f"{100.0 * wins[b] / args.trials:.0f}% | {d:.0f}% | {avg_t:.1f} |")

    print("\n## Supply weight (mirror line-vs-line, side 2 on low supply)\n")
    wins, avg_t = run_pair("line", "line", args.trials, rng, supply=(False, True))
    # run_pair can't distinguish mirror sides by name; rerun manually
    w_ok = w_low = dr = 0
    for t in range(args.trials):
        flip = t % 2 == 1
        sup = (True, False) if flip else (False, True)
        w, _ = Battle(("line", "line"), rng, sup).run()
        if w is None:
            dr += 1
        elif sup[w]:
            w_low += 1
        else:
            w_ok += 1
    print(f"normal supply wins {100.0 * w_ok / args.trials:.0f}% · "
          f"low supply wins {100.0 * w_low / args.trials:.0f}% · "
          f"draws {100.0 * dr / args.trials:.0f}%")


if __name__ == "__main__":
    main()
