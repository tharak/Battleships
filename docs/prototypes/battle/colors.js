// All canvas/board color config lives here, in one place, so retuning the
// palette never means hunting for inline hex strings inside render.js.
// Mirrors (but does not read from) the CSS custom properties in styles.css.

export const SIDE_COLORS = { 0: "#4a9eff", 1: "#ff5a5a" };

// A squadron's hex fill is always its faction's SIDE_COLORS -- state is
// shown entirely via the border color, one explicit entry per state here.
// `null` means "use the side color" (Steady has no accent of its own, so
// its border just matches the fill). Precedence when more than one applies
// (e.g. a Shaken squadron that already acted this turn): routed > shaken >
// activated > steady, applied in render.js.
export const STATE_COLORS = {
  steady:    null,
  shaken:    "#ffd166", // yellow
  routed:    "#ff3333", // red
  activated: "#8892ab", // grey
};

export const ACCENT = {
  flagshipArrow: "#ffd166",
  selectionOutline: "#ffffff",
  targetOutline: "#ff3333",
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
