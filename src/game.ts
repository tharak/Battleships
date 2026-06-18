import {
  BOARD_HEXES,
  Hex,
  Point,
  gridPixelBounds,
  hexCorners,
  hexDistance,
  hexKey,
  hexLine,
  hexToPixel,
  hexesInRange,
  isPlayerZone,
} from "./hex";
import {
  Fleet,
  createEnemyFleet,
  createPlayerFleet,
  sortTargetsByDistance,
} from "./fleet";
import { gameConfig } from "./gameConfig";
import { FleetManager } from "./fleetManager";
import { Ship } from "./ship";
import { UiElements, hideTooltip, renderFleetStatus, renderFormationInfo, showTooltip } from "./ui";
import { clamp, lerp } from "./utils";

type GamePhase = "setup" | "battle" | "victory" | "defeat";

type ShotEffect = {
  from: Point;
  to: Point;
  color: string;
  ttl: number;
  maxTtl: number;
};

type DamagePopup = {
  text: string;
  point: Point;
  ttl: number;
};

export class Game {
  private readonly ctx: CanvasRenderingContext2D;
  private phase: GamePhase = "setup";
  private enemyFleet = createEnemyFleet(gameConfig.enemyFormation);
  private playerFleet = createPlayerFleet(gameConfig.playerFormation);
  private size = 16;
  private origin: Point = { x: 0, y: 0 };
  private hoveredShip: Ship | null = null;
  private lastTime = performance.now();
  private roundTimer = 0;
  private readonly roundInterval = 950;
  private shots: ShotEffect[] = [];
  private popups: DamagePopup[] = [];
  private stars: Point[] = [];
  private readonly fleetManager = new FleetManager();

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly ui: UiElements,
  ) {
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      throw new Error("Canvas 2D context is unavailable.");
    }
    this.ctx = ctx;
    this.bindEvents();
    this.syncDebugControls();
    this.restart();
    requestAnimationFrame((time) => this.frame(time));
  }

  restart(): void {
    this.phase = "setup";
    this.enemyFleet = createEnemyFleet(gameConfig.enemyFormation);
    this.playerFleet = createPlayerFleet(gameConfig.playerFormation);
    this.shots = [];
    this.popups = [];
    this.roundTimer = 0;
    this.resize();
    this.updateUi();
  }

  private bindEvents(): void {
    window.addEventListener("resize", () => this.resize());
    this.canvas.addEventListener("pointermove", (event) => this.onPointerMove(event));
    this.canvas.addEventListener("pointerleave", () => {
      this.hoveredShip = null;
      hideTooltip(this.ui.tooltip);
    });
    this.ui.startButton.addEventListener("click", () => this.startBattle());
    this.ui.restartButton.addEventListener("click", () => this.restart());
    this.ui.debugPanel.addEventListener("input", (event) => this.onDebugInput(event));
    this.ui.debugPanel.addEventListener("change", (event) => this.onDebugInput(event));
  }

  private onDebugInput(event: Event): void {
    if (this.phase !== "setup") {
      return;
    }

    const control = event.target;
    if (!(control instanceof HTMLInputElement || control instanceof HTMLSelectElement)) {
      return;
    }

    const path = control.dataset.config;
    if (!path) {
      return;
    }

    const value = control instanceof HTMLInputElement && control.type === "number" ? Number(control.value) : control.value;
    this.setConfigValue(path, value);
    this.rebuildSetupFleets();
    this.syncDebugControls();
  }

  private rebuildSetupFleets(): void {
    this.enemyFleet = createEnemyFleet(gameConfig.enemyFormation);
    this.playerFleet = createPlayerFleet(gameConfig.playerFormation);
    this.updateUi();
  }

  private syncDebugControls(): void {
    const controls = this.ui.debugPanel.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-config]");
    controls.forEach((control) => {
      const path = control.dataset.config;
      if (!path) {
        return;
      }
      control.value = String(this.getConfigValue(path));
    });
  }

  private setDebugControlsDisabled(disabled: boolean): void {
    const controls = this.ui.debugPanel.querySelectorAll<HTMLInputElement | HTMLSelectElement>("[data-config]");
    controls.forEach((control) => {
      control.disabled = disabled;
    });
  }

  private getConfigValue(path: string): string | number {
    return path.split(".").reduce<unknown>((source, key) => {
      if (source && typeof source === "object" && key in source) {
        return (source as Record<string, unknown>)[key];
      }
      return "";
    }, gameConfig) as string | number;
  }

  private setConfigValue(path: string, value: string | number): void {
    const keys = path.split(".");
    const lastKey = keys.pop();
    if (!lastKey) {
      return;
    }

    const target = keys.reduce<unknown>((source, key) => {
      if (source && typeof source === "object" && key in source) {
        return (source as Record<string, unknown>)[key];
      }
      return undefined;
    }, gameConfig);

    if (target && typeof target === "object") {
      (target as Record<string, string | number>)[lastKey] = typeof value === "number" && Number.isFinite(value) ? value : String(value);
    }
  }

  private resize(): void {
    const rect = this.canvas.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    this.canvas.width = Math.floor(rect.width * dpr);
    this.canvas.height = Math.floor(rect.height * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const usableWidth = Math.max(320, rect.width - 32);
    const usableHeight = Math.max(420, rect.height - 32);
    const unitBounds = gridPixelBounds(1, { x: 0, y: 0 });
    this.size = Math.max(8, Math.min(usableWidth / unitBounds.width, usableHeight / unitBounds.height));
    const bounds = gridPixelBounds(this.size, { x: 0, y: 0 });
    this.origin = {
      x: (rect.width - bounds.width) / 2 - bounds.minX,
      y: (rect.height - bounds.height) / 2 - bounds.minY,
    };
    this.stars = Array.from({ length: Math.floor((rect.width * rect.height) / 11000) }, () => ({
      x: Math.random() * rect.width,
      y: Math.random() * rect.height,
    }));
  }

  private frame(time: number): void {
    const delta = Math.min(80, time - this.lastTime);
    this.lastTime = time;
    this.update(delta);
    this.render();
    requestAnimationFrame((nextTime) => this.frame(nextTime));
  }

  private update(delta: number): void {
    this.shots = this.shots
      .map((shot) => ({ ...shot, ttl: shot.ttl - delta }))
      .filter((shot) => shot.ttl > 0);
    this.popups = this.popups
      .map((popup) => ({ ...popup, ttl: popup.ttl - delta, point: { x: popup.point.x, y: popup.point.y - delta * 0.025 } }))
      .filter((popup) => popup.ttl > 0);

    if (this.phase !== "battle") {
      return;
    }

    this.roundTimer += delta;
    if (this.roundTimer >= this.roundInterval) {
      this.roundTimer = 0;
      this.simulateRound();
    }
  }

  private onPointerMove(event: PointerEvent): void {
    const point = this.eventPoint(event);
    const ships = [...this.playerFleet.aliveShips, ...this.enemyFleet.aliveShips];
    this.hoveredShip =
      ships.find((ship) => {
        const center = this.shipPoint(ship);
        return Math.hypot(center.x - point.x, center.y - point.y) <= this.size * 0.72;
      }) ?? null;

    if (this.hoveredShip) {
      showTooltip(
        this.ui.tooltip,
        event.clientX,
        event.clientY,
        `${this.hoveredShip.side === "player" ? "Player" : "Enemy"} ship - HP ${this.hoveredShip.hp}/${gameConfig.ship.maxHp} - Range ${gameConfig.ship.range}`,
      );
    } else {
      hideTooltip(this.ui.tooltip);
    }
  }

  private startBattle(): void {
    if (this.phase !== "setup" || this.playerFleet.ships.length !== 10) {
      return;
    }
    this.phase = "battle";
    this.roundTimer = this.roundInterval * 0.45;
    this.updateUi();
  }

  private simulateRound(): void {
    const actedShipIds = new Set<string>();
    this.fireFleet(this.playerFleet, this.enemyFleet, actedShipIds);
    this.fireFleet(this.enemyFleet, this.playerFleet, actedShipIds);

    const occupied = this.occupiedKeys();
    this.fleetManager.moveFleet(this.playerFleet, this.enemyFleet, occupied, actedShipIds);
    this.fleetManager.moveFleet(this.enemyFleet, this.playerFleet, occupied, actedShipIds);

    if (this.enemyFleet.isDestroyed) {
      this.phase = "victory";
    } else if (this.playerFleet.isDestroyed) {
      this.phase = "defeat";
    }
    this.updateUi();
  }

  private fireFleet(fleet: Fleet, enemy: Fleet, actedShipIds: Set<string>): void {
    for (const ship of fleet.aliveShips) {
      const target = this.findTarget(ship, enemy.aliveShips, fleet.aliveShips);
      if (!target) {
        continue;
      }
      target.takeDamage(gameConfig.ship.damage);
      const from = this.shipPoint(ship);
      const to = this.shipPoint(target);
      this.shots.push({
        from,
        to,
        color: fleet.side === "player" ? "#60ffd6" : "#ff4f77",
        ttl: 260,
        maxTtl: 260,
      });
      this.popups.push({ text: "-" + String(gameConfig.ship.damage), point: { ...to }, ttl: 620 });
      actedShipIds.add(ship.id);
    }
  }

  private findTarget(source: Ship, targets: Ship[], allies: Ship[]): Ship | null {
    return (
      sortTargetsByDistance(
        source,
        targets.filter((target) => hexDistance(source.hex, target.hex) <= gameConfig.ship.range),
      ).find((target) => !this.allyBlocksShot(source, target, allies)) ?? null
    );
  }

  private allyBlocksShot(source: Ship, target: Ship, allies: Ship[]): boolean {
    const line = hexLine(source.hex, target.hex).slice(1, -1);
    const blockers = new Set(allies.filter((ally) => ally.id !== source.id && ally.isAlive).map((ally) => ally.key));
    return line.some((hex) => blockers.has(hexKey(hex)));
  }

  private occupiedKeys(): Set<string> {
    return new Set([...this.playerFleet.aliveShips, ...this.enemyFleet.aliveShips].map((ship) => ship.key));
  }

  private updateUi(): void {
    renderFormationInfo(this.ui.formationInfo, this.enemyFleet.formation);
    renderFleetStatus(this.ui.fleetStatus, this.playerFleet, this.enemyFleet);
    this.ui.startButton.disabled = this.phase !== "setup" || this.playerFleet.ships.length !== 10;
    this.ui.debugPanel.classList.toggle("is-locked", this.phase !== "setup");
    this.setDebugControlsDisabled(this.phase !== "setup");
    const messages: Record<GamePhase, string> = {
      setup: "Setup: tune fleets, then start battle.",
      battle: "Battle running: fleets advance and fire each round.",
      victory: "Victory: enemy fleet destroyed.",
      defeat: "Defeat: player fleet destroyed.",
    };
    this.ui.phaseStatus.textContent = messages[this.phase];
  }

  private render(): void {
    const width = this.canvas.clientWidth;
    const height = this.canvas.clientHeight;
    this.ctx.clearRect(0, 0, width, height);
    this.renderBackground(width, height);
    this.renderGrid();
    this.renderRangePreview();
    this.renderShips();
    this.renderEffects();
    this.renderEndScreen(width, height);
  }

  private renderBackground(width: number, height: number): void {
    const gradient = this.ctx.createLinearGradient(0, 0, width, height);
    gradient.addColorStop(0, "#050812");
    gradient.addColorStop(0.5, "#071324");
    gradient.addColorStop(1, "#0b0818");
    this.ctx.fillStyle = gradient;
    this.ctx.fillRect(0, 0, width, height);

    this.ctx.fillStyle = "rgba(200, 246, 255, 0.78)";
    for (const star of this.stars) {
      this.ctx.fillRect(star.x, star.y, 1.2, 1.2);
    }
  }

  private renderGrid(): void {
    for (const hex of BOARD_HEXES) {
      this.drawHex(hex, isPlayerZone(hex) ? "rgba(96, 255, 214, 0.08)" : "rgba(255, 79, 119, 0.055)");
    }
  }

  private renderRangePreview(): void {
    if (!this.hoveredShip) {
      return;
    }

    this.ctx.save();
    this.ctx.strokeStyle = this.hoveredShip.side === "player" ? "rgba(96, 255, 214, 0.4)" : "rgba(255, 79, 119, 0.38)";
    this.ctx.lineWidth = 1.5;
    for (const hex of hexesInRange(this.hoveredShip.hex, gameConfig.ship.range)) {
      this.traceHex(hex);
      this.ctx.stroke();
    }
    this.ctx.restore();
  }

  private renderShips(): void {
    for (const ship of [...this.enemyFleet.aliveShips, ...this.playerFleet.aliveShips]) {
      const point = this.shipPoint(ship);
      const color = ship.side === "player" ? "#60ffd6" : "#ff4f77";
      const accent = ship.side === "player" ? "#d8fff7" : "#ffe0e8";
      const radius = this.size * 0.62;

      this.ctx.save();
      this.ctx.translate(point.x, point.y);
      this.ctx.rotate(this.shipRotation(ship));
      this.ctx.shadowBlur = this.hoveredShip?.id === ship.id ? 20 : 12;
      this.ctx.shadowColor = color;
      this.ctx.fillStyle = color;
      this.ctx.beginPath();
      this.ctx.moveTo(radius, 0);
      this.ctx.lineTo(-radius * 0.72, -radius * 0.68);
      this.ctx.lineTo(-radius * 0.42, 0);
      this.ctx.lineTo(-radius * 0.72, radius * 0.68);
      this.ctx.closePath();
      this.ctx.fill();
      this.ctx.fillStyle = accent;
      this.ctx.fillRect(-radius * 0.22, -radius * 0.14, radius * 0.48, radius * 0.28);
      this.ctx.restore();

      this.renderHpBar(ship, point);
    }
  }

  private renderHpBar(ship: Ship, point: Point): void {
    const width = this.size * 1.35;
    const height = 4;
    const x = point.x - width / 2;
    const y = point.y - this.size * 0.95;
    this.ctx.fillStyle = "rgba(0, 0, 0, 0.7)";
    this.ctx.fillRect(x, y, width, height);
    this.ctx.fillStyle = ship.side === "player" ? "#60ffd6" : "#ff4f77";
    this.ctx.fillRect(x, y, width * (ship.hp / gameConfig.ship.maxHp), height);
  }

  private renderEffects(): void {
    for (const shot of this.shots) {
      const alpha = clamp(shot.ttl / shot.maxTtl, 0, 1);
      this.ctx.save();
      this.ctx.globalAlpha = alpha;
      this.ctx.strokeStyle = shot.color;
      this.ctx.shadowColor = shot.color;
      this.ctx.shadowBlur = 18;
      this.ctx.lineWidth = 3;
      this.ctx.beginPath();
      this.ctx.moveTo(shot.from.x, shot.from.y);
      this.ctx.lineTo(shot.to.x, shot.to.y);
      this.ctx.stroke();
      this.ctx.restore();
    }

    for (const popup of this.popups) {
      this.ctx.save();
      this.ctx.globalAlpha = clamp(popup.ttl / 620, 0, 1);
      this.ctx.fillStyle = "#fff2a8";
      this.ctx.font = `700 ${Math.max(12, this.size * 0.75)}px Inter, sans-serif`;
      this.ctx.textAlign = "center";
      this.ctx.fillText(popup.text, popup.point.x, popup.point.y);
      this.ctx.restore();
    }
  }

  private renderEndScreen(width: number, height: number): void {
    if (this.phase !== "victory" && this.phase !== "defeat") {
      return;
    }
    this.ctx.save();
    this.ctx.fillStyle = "rgba(1, 5, 12, 0.68)";
    this.ctx.fillRect(0, 0, width, height);
    this.ctx.fillStyle = this.phase === "victory" ? "#60ffd6" : "#ff4f77";
    this.ctx.font = `800 ${clamp(width * 0.07, 28, 72)}px Inter, sans-serif`;
    this.ctx.textAlign = "center";
    this.ctx.fillText(this.phase === "victory" ? "VICTORY" : "DEFEAT", width / 2, height / 2);
    this.ctx.fillStyle = "#d9f7ff";
    this.ctx.font = "700 16px Inter, sans-serif";
    this.ctx.fillText("Use Restart to generate a new engagement.", width / 2, height / 2 + 34);
    this.ctx.restore();
  }

  private drawHex(hex: Hex, fillStyle: string): void {
    this.ctx.save();
    this.traceHex(hex);
    this.ctx.fillStyle = fillStyle;
    this.ctx.strokeStyle = "rgba(112, 219, 255, 0.18)";
    this.ctx.lineWidth = 1;
    this.ctx.fill();
    this.ctx.stroke();
    this.ctx.restore();
  }

  private traceHex(hex: Hex): void {
    const corners = hexCorners(hex, this.size, this.origin);
    this.ctx.beginPath();
    corners.forEach((corner, index) => {
      if (index === 0) {
        this.ctx.moveTo(corner.x, corner.y);
      } else {
        this.ctx.lineTo(corner.x, corner.y);
      }
    });
    this.ctx.closePath();
  }

  private shipPoint(ship: Ship): Point {
    const target = hexToPixel(ship.hex, this.size, this.origin);
    const previous = hexToPixel(ship.previousHex, this.size, this.origin);
    const t = this.phase === "battle" ? clamp(this.roundTimer / 280, 0, 1) : 1;
    return {
      x: lerp(previous.x, target.x, t),
      y: lerp(previous.y, target.y, t),
    };
  }

  private shipRotation(ship: Ship): number {
    const target = hexToPixel(ship.hex, this.size, this.origin);
    const previous = hexToPixel(ship.previousHex, this.size, this.origin);
    const dx = target.x - previous.x;
    const dy = target.y - previous.y;

    if (Math.hypot(dx, dy) > 0.1) {
      return Math.atan2(dy, dx);
    }

    return ship.side === "player" ? -Math.PI / 2 : Math.PI / 2;
  }

  private eventPoint(event: PointerEvent): Point {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: event.clientX - rect.left,
      y: event.clientY - rect.top,
    };
  }
}
