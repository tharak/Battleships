export type Hex = {
  q: number;
  r: number;
};

export type Point = {
  x: number;
  y: number;
};

export const GRID_WIDTH = 15;
export const GRID_HEIGHT = 20;

const SQRT3 = Math.sqrt(3);
const DIRECTIONS: Hex[] = [
  { q: 1, r: 0 },
  { q: 1, r: -1 },
  { q: 0, r: -1 },
  { q: -1, r: 0 },
  { q: -1, r: 1 },
  { q: 0, r: 1 },
];

export function hexKey(hex: Hex): string {
  return String(hex.q) + "," + String(hex.r);
}

export function sameHex(a: Hex, b: Hex): boolean {
  return a.q === b.q && a.r === b.r;
}

export function addHex(a: Hex, b: Hex): Hex {
  return { q: a.q + b.q, r: a.r + b.r };
}

export function isInBounds(hex: Hex): boolean {
  return hex.q >= 0 && hex.q < GRID_WIDTH && hex.r >= 0 && hex.r < GRID_HEIGHT;
}

export function hexToPixel(hex: Hex, size: number, origin: Point): Point {
  return {
    x: origin.x + size * 1.5 * hex.q,
    y: origin.y + size * SQRT3 * (hex.r + hex.q / 2),
  };
}

export function pixelToHex(point: Point, size: number, origin: Point): Hex {
  const x = (point.x - origin.x) / size;
  const y = (point.y - origin.y) / size;
  return roundHex({ q: (2 / 3) * x, r: (-1 / 3) * x + (SQRT3 / 3) * y });
}

export function hexCorners(hex: Hex, size: number, origin: Point): Point[] {
  const center = hexToPixel(hex, size, origin);
  return Array.from({ length: 6 }, (_, index) => {
    const angle = (Math.PI / 180) * (60 * index);
    return {
      x: center.x + size * Math.cos(angle),
      y: center.y + size * Math.sin(angle),
    };
  });
}

export function hexDistance(a: Hex, b: Hex): number {
  const ac = axialToCube(a);
  const bc = axialToCube(b);
  return Math.max(Math.abs(ac.x - bc.x), Math.abs(ac.y - bc.y), Math.abs(ac.z - bc.z));
}

export function neighbors(hex: Hex): Hex[] {
  return DIRECTIONS.map((direction) => addHex(hex, direction)).filter(isInBounds);
}

export function hexesInRange(center: Hex, range: number): Hex[] {
  const results: Hex[] = [];
  for (let q = -range; q <= range; q += 1) {
    const minR = Math.max(-range, -q - range);
    const maxR = Math.min(range, -q + range);
    for (let r = minR; r <= maxR; r += 1) {
      const hex = { q: center.q + q, r: center.r + r };
      if (isInBounds(hex)) {
        results.push(hex);
      }
    }
  }
  return results;
}

export function hexLine(a: Hex, b: Hex): Hex[] {
  const distance = hexDistance(a, b);
  if (distance === 0) {
    return [a];
  }

  const start = axialToCube(a);
  const end = axialToCube(b);
  const line: Hex[] = [];

  for (let i = 0; i <= distance; i += 1) {
    const t = i / distance;
    line.push(
      cubeToAxial(
        roundCube({
          x: lerp(start.x, end.x, t),
          y: lerp(start.y, end.y, t),
          z: lerp(start.z, end.z, t),
        }),
      ),
    );
  }

  return line;
}

export function gridPixelBounds(size: number, origin: Point): { width: number; height: number } {
  const corners = [
    ...hexCorners({ q: 0, r: 0 }, size, origin),
    ...hexCorners({ q: GRID_WIDTH - 1, r: GRID_HEIGHT - 1 }, size, origin),
  ];
  return {
    width: Math.max(...corners.map((point) => point.x)) - Math.min(...corners.map((point) => point.x)),
    height: Math.max(...corners.map((point) => point.y)) - Math.min(...corners.map((point) => point.y)),
  };
}

type Cube = {
  x: number;
  y: number;
  z: number;
};

function axialToCube(hex: Hex): Cube {
  const x = hex.q;
  const z = hex.r;
  return { x, y: -x - z, z };
}

function cubeToAxial(cube: Cube): Hex {
  return { q: cube.x, r: cube.z };
}

function roundHex(hex: Hex): Hex {
  return cubeToAxial(roundCube(axialToCube(hex)));
}

function roundCube(cube: Cube): Cube {
  let rx = Math.round(cube.x);
  let ry = Math.round(cube.y);
  let rz = Math.round(cube.z);

  const xDiff = Math.abs(rx - cube.x);
  const yDiff = Math.abs(ry - cube.y);
  const zDiff = Math.abs(rz - cube.z);

  if (xDiff > yDiff && xDiff > zDiff) {
    rx = -ry - rz;
  } else if (yDiff > zDiff) {
    ry = -rx - rz;
  } else {
    rz = -rx - ry;
  }

  return { x: rx, y: ry, z: rz };
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}
