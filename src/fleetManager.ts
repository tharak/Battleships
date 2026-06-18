import { gameConfig } from "./gameConfig";
import { Fleet, sortTargetsByDistance } from "./fleet";
import { Hex, boardY, hexDistance, hexKey, neighbors } from "./hex";
import { Ship } from "./ship";

export type SteeringWeights = {
  separation: number;
  cohesion: number;
  alignment: number;
  target: number;
};

type FleetCenter = {
  q: number;
  r: number;
};

export class FleetManager {
  constructor(private readonly weights: SteeringWeights = gameConfig.steering) {}

  moveFleet(fleet: Fleet, enemy: Fleet, occupied: Set<string>, actedShipIds: Set<string> = new Set()): void {
    if (fleet.formation.strategy !== "attack") {
      this.holdFleetFormation(fleet);
      return;
    }

    const allies = fleet.aliveShips;
    const enemies = enemy.aliveShips;
    if (allies.length === 0 || enemies.length === 0) {
      return;
    }

    for (const ship of allies) {
      if (actedShipIds.has(ship.id)) {
        ship.previousHex = { ...ship.hex };
        continue;
      }

      const target = sortTargetsByDistance(ship, enemies)[0];
      if (!target) {
        ship.previousHex = { ...ship.hex };
        continue;
      }

      const candidate = this.bestBoidMove(ship, target, allies, occupied);
      if (!candidate) {
        ship.previousHex = { ...ship.hex };
        continue;
      }

      occupied.delete(ship.key);
      ship.moveTo(candidate);
      occupied.add(ship.key);
    }
  }

  private holdFleetFormation(fleet: Fleet): void {
    for (const ship of fleet.aliveShips) {
      ship.previousHex = { ...ship.hex };
    }
  }

  private bestBoidMove(ship: Ship, target: Ship, allies: Ship[], occupied: Set<string>): Hex | null {
    const currentDistance = hexDistance(ship.hex, target.hex);
    const center = this.fleetCenter(allies.filter((ally) => ally.id !== ship.id));
    const currentScore = this.scoreMove(ship, ship.hex, target.hex, currentDistance, allies, center);
    const candidates = neighbors(ship.hex).filter((hex) => !occupied.has(hexKey(hex)));

    const best = candidates
      .map((hex) => ({ hex, score: this.scoreMove(ship, hex, target.hex, currentDistance, allies, center) }))
      .sort((a, b) => b.score - a.score)[0];

    if (!best || best.score <= currentScore) {
      return null;
    }

    return best.hex;
  }

  private scoreMove(ship: Ship, candidate: Hex, target: Hex, currentDistance: number, allies: Ship[], center: FleetCenter): number {
    const separation = this.separationScore(ship, candidate, allies);
    const cohesion = -this.centerDistance(candidate, center);
    const alignment = this.alignmentScore(ship, candidate);
    const targetPressure = currentDistance - hexDistance(candidate, target);

    return (
      separation * this.weights.separation +
      cohesion * this.weights.cohesion +
      alignment * this.weights.alignment +
      targetPressure * this.weights.target
    );
  }

  private separationScore(ship: Ship, candidate: Hex, allies: Ship[]): number {
    return allies.reduce((score, ally) => {
      if (ally.id === ship.id || !ally.isAlive) {
        return score;
      }

      const distance = hexDistance(candidate, ally.hex);
      if (distance === 0) {
        return score - 10;
      }
      if (distance === 1) {
        return score - 4;
      }
      if (distance === 2) {
        return score + 2;
      }
      if (distance === 3) {
        return score + 0.8;
      }
      return score - 0.35;
    }, 0);
  }

  private alignmentScore(ship: Ship, candidate: Hex): number {
    const direction = ship.side === "player" ? -1 : 1;
    const deltaY = boardY(candidate) - boardY(ship.hex);
    if (deltaY * direction > 0) {
      return 0.6;
    }
    if (deltaY === 0) {
      return 0.2;
    }
    return -0.8;
  }

  private fleetCenter(ships: Ship[]): FleetCenter {
    if (ships.length === 0) {
      return { q: 0, r: 0 };
    }

    return {
      q: ships.reduce((sum, ship) => sum + ship.hex.q, 0) / ships.length,
      r: ships.reduce((sum, ship) => sum + ship.hex.r, 0) / ships.length,
    };
  }

  private centerDistance(hex: Hex, center: FleetCenter): number {
    return Math.hypot(hex.q - center.q, hex.r - center.r);
  }
}
