// All canvas/board color config lives here, in one place, so retuning the
// palette never means hunting for inline hex strings inside render.js.
// Mirrors (but does not read from) the CSS custom properties in styles.css.

export const SIDE_COLORS = { 0: "#4a9eff", 1: "#ff5a5a" };

// One explicit entry per on-board unit state. `fill: null` means "use the
// side color" -- Steady has no override color of its own. `activated` is a
// turn-flow pseudo-state (already acted this turn), not a morale state, but
// is rendered the same way (a hex fill + outline) so it gets a slot here
// too, deliberately a different gray from `routed` so the two are never
// confused at a glance.
export const STATE_COLORS = {
  steady:    { fill: null,      outline: "#0b0e14" },
  shaken:    { fill: null,      outline: "#ffd166" }, // gold outline + "!" icon
  routed:    { fill: "#8a7a6a", outline: "#0b0e14" }, // warm gray
  activated: { fill: "#454b58", outline: "#0b0e14" }, // cool gray
};

export const ACCENT = {
  flagshipArrow: "#ffd166",
  selectionOutline: "#ffffff",
  targetOutline: "#ff3333",
  shakenIcon: "#ffd166",
  labelText: "#0b0e14",   // squadron id / flagship star / non-flagship arrow fill
  pipFilled: "#ffffff",
  pipEmpty: "#ffffff33",
};

export const BOARD_TINT = {
  bg: "#0b0e14",
  gridCell: "#111624",
  gridLine: "#1d2438",
  fireZone: "#26203a",
  commandReach: side => side === 0 ? "#4a9eff1c" : "#ff5a5a1c",
  setupZone:    side => side === 0 ? "#4a9eff14" : "#ff5a5a14",
};
