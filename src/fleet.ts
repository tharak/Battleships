import { BOARD_HEXES, Hex, boardY, hexDistance, hexKey, isInBounds, isPlayerZone } from './hex';
import { FleetSide, Ship } from './ship';
import { choice, randomInt, shuffle } from './utils';

export type FormationPattern = '1-2-3-4' | '3-4-3' | '5-5';
export type FleetStrategy = 'attack' | 'defense';

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
    pattern: choice<FormationPattern>(['1-2-3-4', '3-4-3', '5-5']),
    spacing: randomInt(0, 2),
    strategy: choice<FleetStrategy>(['attack', 'defense']),
  };
}

export function createEnemyFleet(): Fleet {
  const formation = randomFormation();
  const positions = buildFormationPositions(formation, 'enemy');
  return new Fleet(
    'enemy',
    formation,
    positions.map((hex, index) => new Ship("enemy-" + String(index + 1), 'enemy', hex)),
  );
}

export function createPlayerFleet(positions: Hex[], strategy: FleetStrategy = 'attack'): Fleet {
  return new Fleet(
    'player',
    { pattern: '5-5', spacing: 1, strategy },
    positions.map((hex, index) => new Ship("player-" + String(index + 1), 'player', hex)),
  );
}

export function randomPlayerPositions(blocked: Set<string> = new Set()): Hex[] {
  return shuffle(BOARD_HEXES.filter((hex) => isPlayerZone(hex) && !blocked.has(hexKey(hex)))).slice(0, FLEET_SIZE);
}

export function buildFormationPositions(formation: Formation, side: FleetSide): Hex[] {
  const rows = side === 'enemy' ? FORMATION_ROWS[formation.pattern] : [...FORMATION_ROWS[formation.pattern]].reverse();
  const anchors = [...BOARD_HEXES]
    .filter((hex) => (side === 'enemy' ? !isPlayerZone(hex) : isPlayerZone(hex)))
    .sort((a, b) => (side === 'enemy' ? boardY(a) - boardY(b) : boardY(b) - boardY(a)) || Math.abs(a.q) - Math.abs(b.q));

  for (const anchor of anchors) {
    const positions = formationAt(anchor, rows, formation.spacing, side);
    if (positions.length === FLEET_SIZE && positions.every((hex) => side === 'enemy' ? !isPlayerZone(hex) : isPlayerZone(hex))) {
      return positions;
    }
  }

  return shuffle(anchors).slice(0, FLEET_SIZE);
}

export function isPlacementValid(hex: Hex, existing: Hex[], enemyShips: Ship[]): boolean {
  if (!isInBounds(hex) || !isPlayerZone(hex)) {
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

function formationAt(anchor: Hex, rows: number[], spacing: number, side: FleetSide): Hex[] {
  const step = spacing + 1;
  const rowDirection = side === 'enemy' ? 1 : -1;
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
