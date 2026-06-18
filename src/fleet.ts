import { GRID_HEIGHT, GRID_WIDTH, Hex, hexDistance, hexKey, isInBounds } from "./hex";
import { FleetSide, Ship } from "./ship";
import { choice, randomInt, shuffle } from "./utils";

export type FormationPattern = "1-2-3-4" | "3-4-3" | "5-5";
export type FleetStrategy = "attack" | "defense";

export type Formation = {
  pattern: FormationPattern;
  spacing: number;
  strategy: FleetStrategy;
};

const FLEET_SIZE = 10;
const FORMATION_ROWS: Record<FormationPattern, number[]> = {
  "1-2-3-4": [4, 3, 2, 1],
  "3-4-3": [3, 4, 3],
  "5-5": [5, 5],
};

export class Fleet {
  readonly side: FleetSide;
  formation: Formation;
  ships: Ship[];

  constructor(side: FleetSide, formation: Formation, ships: Ship[]) {
    this.side = side;
    this.formation = formation;
    this.ships = ships;
  }

  get aliveShips(): Ship[] {
    return this.ships.filter((ship) => ship.isAlive);
  }

  get totalHp(): number {
    return this.aliveShips.reduce((sum, ship) => sum + ship.hp, 0);
  }

  get isDestroyed(): boolean {
    return this.aliveShips.length === 0;
  }
}

export function randomFormation(): Formation {
  return {
    pattern: choice<FormationPattern>(["1-2-3-4", "3-4-3", "5-5"]),
    spacing: randomInt(0, 3),
    strategy: choice<FleetStrategy>(["attack", "defense"]),
  };
}

export function createEnemyFleet(): Fleet {
  const formation = randomFormation();
  const positions = buildFormationPositions(formation, "enemy");
  return new Fleet(
    "enemy",
    formation,
    positions.map((hex, index) => new Ship(`enemy-${index + 1}`, "enemy", hex)),
  );
}

export function createPlayerFleet(positions: Hex[], strategy: FleetStrategy = "attack"): Fleet {
  return new Fleet(
    "player",
    { pattern: "5-5", spacing: 1, strategy },
    positions.map((hex, index) => new Ship(`player-${index + 1}`, "player", hex)),
  );
}

export function randomPlayerPositions(blocked: Set<string> = new Set()): Hex[] {
  const candidates: Hex[] = [];
  for (let r = Math.floor(GRID_HEIGHT / 2); r < GRID_HEIGHT; r += 1) {
    for (let q = 0; q < GRID_WIDTH; q += 1) {
      const hex = { q, r };
      if (!blocked.has(hexKey(hex))) {
        candidates.push(hex);
      }
    }
  }
  return shuffle(candidates).slice(0, FLEET_SIZE);
}

export function buildFormationPositions(formation: Formation, side: FleetSide): Hex[] {
  const rows = FORMATION_ROWS[formation.pattern];
  const spacingStep = formation.spacing + 1;
  const positions: Hex[] = [];
  const maxColumns = Math.max(...rows);
  const formationWidth = (maxColumns - 1) * spacingStep;
  const startQ = Math.max(0, Math.floor((GRID_WIDTH - 1 - formationWidth) / 2));
  const startR = side === "enemy" ? 1 : GRID_HEIGHT - 2 - (rows.length - 1) * spacingStep;
  const orderedRows = side === "enemy" ? rows : [...rows].reverse();

  orderedRows.forEach((count, rowIndex) => {
    const rowWidth = (count - 1) * spacingStep;
    const qOffset = Math.floor((formationWidth - rowWidth) / 2);
    const r = startR + rowIndex * spacingStep;

    for (let i = 0; i < count; i += 1) {
      const hex = { q: startQ + qOffset + i * spacingStep, r };
      if (isInBounds(hex)) {
        positions.push(hex);
      }
    }
  });

  return positions.slice(0, FLEET_SIZE);
}

export function isPlacementValid(hex: Hex, existing: Hex[], enemyShips: Ship[]): boolean {
  if (!isInBounds(hex) || hex.r < Math.floor(GRID_HEIGHT / 2)) {
    return false;
  }

  const key = hexKey(hex);
  return !existing.some((placed) => hexKey(placed) === key) && !enemyShips.some((ship) => ship.key === key);
}

export function sortTargetsByDistance(source: Ship, targets: Ship[]): Ship[] {
  return [...targets].sort((a, b) => {
    const distanceDiff = hexDistance(source.hex, a.hex) - hexDistance(source.hex, b.hex);
    return distanceDiff || a.hp - b.hp;
  });
}
