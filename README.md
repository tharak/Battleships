# Space Battleships

Space Battleships is a standalone TypeScript browser game built with Vite and HTML5 Canvas. It is a sci-fi Battleships variant played on a pointy-top hex map.

## Gameplay

- Enemy fleet starts visible at the top in a random formation.
- Player fleet starts in the lower half using the selected setup formation.
- Every ship occupies one hex. HP, range, and damage can be tuned from the setup debug panel.
- Attack fleets move one hex toward the enemy before firing.
- Defense fleets hold position and fire at ships in range.
- Ships target the closest enemy in range. Allied ships on the shot line block fire.
- Destroy every enemy ship to win.

## Controls

- Tune player and enemy formations in the setup debug panel.
- Use **Start Battle** when both generated fleets look right.
- Hover ships to inspect HP and range.
- Use **Restart** to reset both fleets from the current setup values.

## Project Structure

```text
src/
  fleet.ts     Fleet creation, formations, placement helpers
  fleetManager.ts  Boids-style fleet movement manager
  gameConfig.ts  Setup-time tuning defaults
  game.ts      Canvas renderer, input handling, battle state machine
  hex.ts       Pointy-top axial hex coordinates and utilities
  main.ts      App entrypoint
  ship.ts      Ship model and constants
  style.css    Responsive dark space UI
  ui.ts        Sidebar and tooltip rendering
  utils.ts     Small shared helpers
```

## Local Development

```bash
npm install
npm run dev
```

Build for production:

```bash
npm run build
```

Preview the production build:

```bash
npm run preview
```

## GitHub Pages

The Vite config sets:

```ts
base: "/Battleships/"
```

This matches deployment at:

```text
https://tharak.github.io/Battleships/
```

For GitHub Pages, build the project with `npm run build` and deploy the generated `dist/` directory using your preferred Pages workflow.
