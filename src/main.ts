import "./style.css";
import { Game } from "./game";
import { getUiElements } from "./ui";

const canvas = document.getElementById("gameCanvas");

if (!(canvas instanceof HTMLCanvasElement)) {
  throw new Error("Missing #gameCanvas canvas element.");
}

new Game(canvas, getUiElements());
