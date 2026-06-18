# Space Battleships

Space Battleships is a standalone TypeScript browser game built with Vite and HTML5 Canvas. It is a sci-fi Battleships variant played on a 15 x 30 flat-top hex grid.

## Gameplay

- Enemy fleet starts visible at the top in a random formation.
- Player places 10 ships in the lower half of the map.
- Every ship occupies one hex, has 7 HP, range 3, and deals 1 damage.
- Attack fleets move one hex toward the enemy before firing.
- Defense fleets hold position and fire at ships in range.
- Ships target the closest enemy in range. Allied ships on the shot line block fire.
- Destroy every enemy ship to win.

## Controls

- Click an empty lower-half hex to place a player ship.
- Click a placed player ship during setup to remove it.
- Use **Randomize Player Placement** to quickly place all 10 ships.
- Use **Start Battle** after placing all ships.
- Hover ships to inspect HP and range.
- Use **Restart** to generate a new enemy formation.

## Project Structure

```text
src/
  fleet.ts     Fleet creation, formations, placement helpers
  game.ts      Canvas renderer, input handling, battle state machine
  hex.ts       Flat-top axial hex coordinates and utilities
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
