import { gameConfig } from "./gameConfig";
import { BOARD_HEXES, Hex, boardY, hexDistance, hexKey, isInBounds, isPlayerZone } from "./hex";
import { FleetSide, Ship } from "./ship";
import { shuffle } from "./utils";

export type FormationPattern = "1-2-3-4" | "3-4-3" | "5-5";
export type FleetStrategy = "attack" | "defense";

export type Formation = {
  pattern: FormationPattern;
  spacing: number;
  strategy: FleetStrategy;
};

const FLEET_SIZE = 10;
export const FORMATION_PATTERNS: FormationPattern[] = ["1-2-3-4", "3-4-3", "5-5"];
export const FLEET_STRATEGIES: FleetStrategy[] = ["attack", "defense"];
const FORMATION_ROWS: Record<FormationPattern, number[]> = {
  "1-2-3-4": [1, 2, 3, 4],
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

export function createEnemyFleet(formation: Formation = gameConfig.enemyFormation): Fleet {
  return createFleet("enemy", formation);
}

export function createPlayerFleet(formation: Formation = gameConfig.playerFormation, positions?: Hex[]): Fleet {
  return createFleet("player", formation, positions);
}

export function buildFormationPositions(formation: Formation, side: FleetSide): Hex[] {
  const rows = FORMATION_ROWS[formation.pattern];
  const anchors = [...BOARD_HEXES]
    .filter((hex) => (side === "enemy" ? !isPlayerZone(hex) : isPlayerZone(hex)))
    .sort((a, b) => (side === "enemy" ? boardY(a) - boardY(b) : boardY(b) - boardY(a)) || Math.abs(a.q) - Math.abs(b.q));

  for (const anchor of anchors) {
    const positions = formationAt(anchor, rows, formation.spacing, side);
    if (positions.length === FLEET_SIZE && positions.every((hex) => side === "enemy" ? !isPlayerZone(hex) : isPlayerZone(hex))) {
      return positions;
    }
  }

  return shuffle(anchors).slice(0, FLEET_SIZE);
}

export function sortTargetsByDistance(source: Ship, targets: Ship[]): Ship[] {
  return [...targets].sort((a, b) => {
    const distanceDiff = hexDistance(source.hex, a.hex) - hexDistance(source.hex, b.hex);
    return distanceDiff || a.hp - b.hp;
  });
}

function createFleet(side: FleetSide, formation: Formation, explicitPositions?: Hex[]): Fleet {
  const resolvedFormation = { ...formation };
  const positions = explicitPositions ?? buildFormationPositions(resolvedFormation, side);
  return new Fleet(
    side,
    resolvedFormation,
    positions.map((hex, index) => new Ship(side + "-" + String(index + 1), side, hex)),
  );
}

function formationAt(anchor: Hex, rows: number[], spacing: number, side: FleetSide): Hex[] {
  const step = spacing + 1;
  const rowDirection = side === "enemy" ? 1 : -1;
  const positions: Hex[] = [];
  const occupied = new Set<string>();

  rows.forEach((count, rowIndex) => {
    const rowWidth = (count - 1) * step;
    const startQ = anchor.q - Math.floor(rowWidth / 2);
    const r = anchor.r + rowIndex * step * rowDirection;

    for (let i = 0; i < count; i += 1) {
      const hex = { q: startQ + i * step, r };
      const key = hexKey(hex);
      if (isInBounds(hex) && !occupied.has(key)) {
        positions.push(hex);
        occupied.add(key);
      }
    }
  });

  return positions.slice(0, FLEET_SIZE);
}
