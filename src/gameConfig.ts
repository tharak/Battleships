import type { FleetStrategy, FormationPattern } from './fleet';
import type { SteeringWeights } from './fleetManager';

export type ShipConfig = {
  maxHp: number;
  range: number;
  damage: number;
};

export type GameConfig = {
  ship: ShipConfig;
  steering: SteeringWeights;
  playerFormation: {
    pattern: FormationPattern;
    spacing: number;
    strategy: FleetStrategy;
  };
  enemyFormation: {
    pattern: FormationPattern;
    spacing: number;
    strategy: FleetStrategy;
  };
};

export const gameConfig: GameConfig = {
  ship: {
    maxHp: 7,
    range: 3,
    damage: 1,
  },
  steering: {
    separation: 3,
    cohesion: 5,
    alignment: 5,
    target: 20,
  },
  playerFormation: {
    pattern: '5-5',
    spacing: 1,
    strategy: 'attack',
  },
  enemyFormation: {
    pattern: '1-2-3-4',
    spacing: 1,
    strategy: 'attack',
  },
};
