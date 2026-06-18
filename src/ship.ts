import { Hex, Point, hexKey } from './hex';

export type FleetSide = 'player' | 'enemy';

export const SHIP_MAX_HP = 7;
export const SHIP_RANGE = 3;
export const SHIP_DAMAGE = 1;

export class Ship {
  readonly id: string;
  readonly side: FleetSide;
  hex: Hex;
  previousHex: Hex;
  hp = SHIP_MAX_HP;
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
