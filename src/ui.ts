import { gameConfig } from "./gameConfig";
import { Fleet, Formation } from "./fleet";
import { formatStrategy } from "./utils";

export type UiElements = {
  phaseStatus: HTMLElement;
  formationInfo: HTMLElement;
  fleetStatus: HTMLElement;
  tooltip: HTMLElement;
  startButton: HTMLButtonElement;
  restartButton: HTMLButtonElement;
  debugPanel: HTMLElement;
};

export function getUiElements(): UiElements {
  return {
    phaseStatus: requireElement("phaseStatus"),
    formationInfo: requireElement("formationInfo"),
    fleetStatus: requireElement("fleetStatus"),
    tooltip: requireElement("tooltip"),
    startButton: requireElement("startButton"),
    restartButton: requireElement("restartButton"),
    debugPanel: requireElement("debugPanel"),
  };
}

export function renderFormationInfo(container: HTMLElement, formation: Formation): void {
  container.innerHTML = `
    <dt>Pattern</dt><dd>${formation.pattern}</dd>
    <dt>Spacing</dt><dd>${formation.spacing} hex${formation.spacing === 1 ? "" : "es"}</dd>
    <dt>Strategy</dt><dd>${formatStrategy(formation.strategy)}</dd>
  `;
}

export function renderFleetStatus(container: HTMLElement, playerFleet: Fleet, enemyFleet: Fleet): void {
  container.innerHTML = `
    ${fleetRow("Player", playerFleet.aliveShips.length, playerFleet.totalHp)}
    ${fleetRow("Enemy", enemyFleet.aliveShips.length, enemyFleet.totalHp)}
  `;
}

export function showTooltip(tooltip: HTMLElement, x: number, y: number, content: string): void {
  tooltip.style.display = "block";
  tooltip.style.left = `${x + 14}px`;
  tooltip.style.top = `${y + 14}px`;
  tooltip.textContent = content;
}

export function hideTooltip(tooltip: HTMLElement): void {
  tooltip.style.display = "none";
}

function fleetRow(label: string, ships: number, hp: number): string {
  return `
    <div class="fleet-row">
      <span>${label}</span>
      <strong>${ships}/10 ships - ${hp}/${gameConfig.ship.maxHp * 10} HP</strong>
    </div>
  `;
}

function requireElement<T extends HTMLElement>(id: string): T {
  const element = document.getElementById(id);
  if (!element) {
    throw new Error(`Missing required element: #${id}`);
  }
  return element as T;
}
