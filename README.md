# Battleships

*Successor Stars* (working title) — a grand strategy game of galactic war and political
survival, inspired by *Legend of the Galactic Heroes*. The old empire has collapsed; every
player is a sector ruler who inherits a random (but balanced) political setup — junta,
oligarchy, republic — and steers it toward dictatorship or democracy while managing the
planets that feed their fleets, and commanding those fleets in real-time-with-pause
battles decided by formations, maneuver, and supply. Politics runs on selectorate theory:
you stay in power by keeping your essentials satisfied — or you don't stay in power.

🎮 **[Playable battle prototype](https://tharak.github.io/Battleships/prototypes/battle.html)** —
hex battle testbed for the formation/facing/morale rules (Phase 0, issue #1).

🏛 **[Playable selectorate prototype](https://tharak.github.io/Battleships/prototypes/selectorate.html)** —
politics testbed: budget, seats, loyalty norm, removal crises (Phase 0, issue #2).

📄 **[Game Design Document](docs/GAME_DESIGN.md)** — vision, mechanics, and the phased
solo-dev roadmap. Phase 0 (paper prototypes) is complete; Phase 1 (Godot battle
prototype) is underway.

🗂 **[Development board](https://github.com/users/tharak/projects/6)** · 🌐 **[Project site](https://tharak.github.io/Battleships/)**

## Development

The real engine build lives in `game/` (Godot 4.7, GDScript). Its architecture follows
GDD §11: the simulation is plain data + systems that runs headless, and **every
mutation flows through a serialized command stream** — no direct UI-to-sim pokes — so
the game is multiplayer-ready (deterministic lockstep) from day one.

- **Run the battle plane scene:** `godot --path game` (open the project; `main.tscn`
  runs automatically) or `godot --path game main.tscn` from the CLI. Select your
  squadrons (blue) by click or drag-box, right-click to move them, Q/E to turn in
  place, Space to pause, 1/2/3 for 1x/2x/4x speed — orders queue up while paused.
- **Run the tests:**
  `godot --headless --path game --script res://tests/test_determinism.gd` replays a
  recorded command stream and checks the resulting state hash against a committed
  golden fixture (`game/tests/fixtures/`); `res://tests/test_movement.gd` checks the
  movement/turning/cohesion kinematics themselves (arrival, no-overshoot turning,
  cohesion dropping while turning and regenerating while steady). Both run in CI on
  every push/PR that touches `game/` ([sim-tests workflow](.github/workflows/sim-tests.yml)).
- Godot version is pinned in `game/.godot-version`; CI downloads that exact build.
