import { gameConfig } from "./gameConfig";
import { Hex, Point, hexKey } from "./hex";

export type FleetSide = "player" | "enemy";

export class Ship {
  readonly id: string;
  readonly side: FleetSide;
  hex: Hex;
  previousHex: Hex;
  hp = gameConfig.ship.maxHp;
  renderPoint: Point | null = null;

  constructor(id: string, side: FleetSide, hex: Hex) {
    this.id = id;
    this.side = side;
    this.hex = { ...hex };
    this.previousHex = { ...hex };
  }

  get isAlive(): boolean {
    return this.hp > 0;
  }

  get key(): string {
    return hexKey(this.hex);
  }

  moveTo(hex: Hex): void {
    this.previousHex = { ...this.hex };
    this.hex = { ...hex };
  }

  takeDamage(amount: number): void {
    this.hp = Math.max(0, this.hp - amount);
  }
}
