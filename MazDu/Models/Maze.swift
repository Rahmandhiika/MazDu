import Foundation
import CoreGraphics

/// Deterministic RNG (splitmix64) — same seed on both devices produces the same maze.
/// Never use the system RNG for generation; it can't be seeded/reproduced.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

enum Tile {
    case wall
    case floor(variant: Int)
}

/// Frame index into the obstacle sprite sheet's 4 areas (16x16 each, left to right):
/// standing (parked outside the path, safe) → leaning (just starting to swing, still
/// mostly at the wall, safe) → reclining (swung across the path, danger) → fallen (lying
/// across the path, still danger).
enum ObstacleFrame: Int {
    case standing = 0
    case leaning = 1
    case reclining = 2
    case fallen = 3
}

/// A hazard whose sprite and hitbox are both parked toward one flanking wall while
/// standing, swinging in to the tile center as it falls (now lying across the passage)
/// and back out as it rises — at 2 different offsets (`state(at:).hitboxPosition` /
/// `.spritePosition`), since the hitbox has a hard geometric ceiling on how far it can
/// sit off-center and still fully block a 1-tile corridor, while the sprite doesn't (the
/// flanking wall is a full adjacent tile, so it can push much further in with zero
/// gameplay effect). Blocks/stuns from the moment it's swung across the corridor
/// (reclining) through lying across it (fallen); standing and leaning are safe, since
/// neither has any part of the obstacle actually in the path yet.
struct MazeObstacle {
    let row: Int
    let col: Int

    /// Tile-center reference point that both `hitboxPosition` and `spritePosition` are
    /// computed from.
    var position: CGPoint {
        CGPoint(x: Double(col) + 0.5, y: Double(row) + 0.5)
    }

    /// Exactly one of row/col is odd for a connector tile (see `Maze.generate`). An odd
    /// row (even col) is an east-west connector — walls flank top/bottom, so the sprite
    /// leans toward one of them, and it needs the dedicated top/bottom-fall asset
    /// (`obstacle_tree_vertical`) rather than the left/right one; an odd col (even row)
    /// is north-south, walls flank left/right, uses the original `obstacle_tree` asset.
    var swingsVertically: Bool { row % 2 == 1 }

    /// Deterministic per-obstacle: which of the 2 flanking walls it's parked against, so
    /// obstacles on a vertical corridor don't all lean the same left/right direction.
    /// +1 = toward the bottom/right wall, -1 = toward the top/left wall. Horizontal
    /// corridors always get -1 (top) — the user explicitly wants every one of these
    /// falling downward, never placed at the bottom wall (`obstacle_tree_vertical`'s art
    /// is drawn top-anchored; there's no bottom-wall variant in use).
    ///
    /// Bug fixed here: a plain `(row*31+col*17) % 2` (31 and 17 both odd) always
    /// evaluated to the same constant for every connector tile, since a connector always
    /// has exactly one of row/col odd — the sum's lowest bit is mathematically forced to
    /// 1 regardless of the actual coordinates, so this "variety" never once happened
    /// since it was introduced (D-053a). Dividing out that fixed low bit before taking
    /// `% 2` uses the next bit up instead, which does vary with the actual row/col
    /// values — confirmed via a full sweep (400/400 split, not 800/0).
    private var sideSign: Double {
        guard !swingsVertically else { return -1 }
        return ((row * 31 + col * 17) / 2) % 2 == 0 ? -1 : 1
    }

    /// Mirrors the sprite horizontally when parked on the left wall (the `obstacle_tree`
    /// default art assumes the right wall). Only meaningful when `!swingsVertically`.
    var spriteFlippedHorizontally: Bool {
        !swingsVertically && sideSign < 0
    }

    private static let fallDuration = GameConfig.Obstacle.fallFrame1Duration + GameConfig.Obstacle.fallFrame2Duration
    private static let riseDuration = GameConfig.Obstacle.riseFrame3Duration + GameConfig.Obstacle.riseFrame2Duration
    private static let cycleDuration = GameConfig.Obstacle.standingDuration + fallDuration
        + GameConfig.Obstacle.fallenDuration + riseDuration

    /// Current sprite frame, whether it currently blocks the path, and where the hitbox
    /// vs. the sprite should sit (parked at the wall while standing/fully risen, swung to
    /// the tile center while fallen, interpolated during the fall/rise animation) — all
    /// derived from a single elapsed-time (seconds since race start). Per-obstacle phase
    /// offset (derived from its own coordinates) keeps multiple obstacles from all
    /// falling/rising in lockstep. `hitboxPosition` is what `RaceViewModel` collides
    /// against (never the visual position alone, and never the fixed tile center — either
    /// would risk "hitting thin air" or letting the corridor be dodged); `spritePosition`
    /// is purely what `MazeView` draws at, offset further since it has no blocking
    /// constraint to respect.
    func state(at time: Double) -> (frame: ObstacleFrame, blocksPath: Bool, hitboxPosition: CGPoint, spritePosition: CGPoint) {
        let phase = Double(row * 31 + col * 17).truncatingRemainder(dividingBy: Self.cycleDuration)
        let t = (time + phase).truncatingRemainder(dividingBy: Self.cycleDuration)

        let standingEnd = GameConfig.Obstacle.standingDuration
        let leaningEnd = standingEnd + GameConfig.Obstacle.fallFrame1Duration
        let recliningEnd = leaningEnd + GameConfig.Obstacle.fallFrame2Duration
        let fallenEnd = recliningEnd + GameConfig.Obstacle.fallenDuration
        let riseStep1End = fallenEnd + GameConfig.Obstacle.riseFrame3Duration
        // beyond riseStep1End, up to cycleDuration: rising's final leg, back to standing

        let frame: ObstacleFrame
        let fallProgress: Double // 0 = parked at the wall, 1 = swung fully to tile center
        switch t {
        case ..<standingEnd:
            frame = .standing
            fallProgress = 0
        case ..<leaningEnd:
            frame = .leaning
            fallProgress = (t - standingEnd) / Self.fallDuration
        case ..<recliningEnd:
            frame = .reclining
            fallProgress = (t - standingEnd) / Self.fallDuration
        case ..<fallenEnd:
            frame = .fallen
            fallProgress = 1
        case ..<riseStep1End:
            frame = .reclining
            fallProgress = 1 - (t - fallenEnd) / Self.riseDuration
        default:
            frame = .leaning
            fallProgress = 1 - (t - fallenEnd) / Self.riseDuration
        }

        let center = position
        func parkedPosition(offset: Double) -> CGPoint {
            let edge = swingsVertically
                ? CGPoint(x: center.x, y: center.y + offset * sideSign)
                : CGPoint(x: center.x + offset * sideSign, y: center.y)
            return CGPoint(x: edge.x + (center.x - edge.x) * fallProgress, y: edge.y + (center.y - edge.y) * fallProgress)
        }
        let hitboxPosition = parkedPosition(offset: GameConfig.Obstacle.hitboxEdgeOffset)
        let spritePosition = parkedPosition(offset: GameConfig.Obstacle.spriteEdgeOffset)
        // Standing and leaning are safe — the obstacle is parked entirely outside the
        // path (spriteEdgeOffset ≈ 0.98) or has barely started swinging in, so there's
        // nothing there to hit yet. Only .leaning is excluded from blocking despite being
        // mid-swing: hitbox and sprite interpolate from very different offsets (0.3 vs
        // 0.98) sharing the same fallProgress fraction, not the same physical speed, so
        // early on (fallProgress below ~0.27) the sprite's still too far out for its
        // drawn footprint to reach where the hitbox already sits — the same "hits thin
        // air" bug this whole offset scheme exists to avoid, just for a fraction of a
        // second. By fallProgress 0.5 (.reclining's start) the sprite's footprint already
        // reaches back past the tile center, so there's no gap for the rest of the swing
        // through fallen. From .reclining onward, danger is continuous — once any part of
        // the obstacle is over the path, it stays dangerous until it's fully swung back
        // out past .leaning again. `.fallen` blocking (not safe, despite the original
        // written spec saying otherwise) was an explicit call after live playtesting.
        let blocksPath = frame == .reclining || frame == .fallen
        return (frame, blocksPath, hitboxPosition, spritePosition)
    }
}

/// A maze rendered as a tile grid: odd rows/cols are carved cells, even rows/cols are
/// walls between them (standard cell->tile doubling), so rendering is a flat 2D lookup.
struct Maze {
    let cols: Int
    let rows: Int
    let tiles: [[Tile]]
    let finishPosition: (row: Int, col: Int)
    let obstacles: [MazeObstacle]

    func tile(row: Int, col: Int) -> Tile {
        guard row >= 0, row < rows, col >= 0, col < cols else { return .wall }
        return tiles[row][col]
    }

    func isBlocked(row: Int, col: Int) -> Bool {
        if case .wall = tile(row: row, col: col) { return true }
        return false
    }

    /// Seeded recursive-backtracker (DFS) generation — one long maze generated upfront
    /// rather than streamed in chunks (simpler, no real-time generation edge cases).
    static func generate(seed: UInt64, cellCols: Int, cellRows: Int, startCellCol: Int? = nil) -> Maze {
        var rng = SeededGenerator(seed: seed)
        let cols = cellCols * 2 + 1
        let rows = cellRows * 2 + 1
        var grid = Array(repeating: Array(repeating: Tile.wall, count: cols), count: rows)
        var visited = Array(repeating: Array(repeating: false, count: cellCols), count: cellRows)

        func carve(_ cellRow: Int, _ cellCol: Int, enteredFrom: (dr: Int, dc: Int)?) {
            visited[cellRow][cellCol] = true
            grid[cellRow * 2 + 1][cellCol * 2 + 1] = .floor(variant: Int.random(in: 0...1, using: &rng))

            var dirs = [(dr: 0, dc: 1), (dr: 0, dc: -1), (dr: 1, dc: 0), (dr: -1, dc: 0)]
            dirs.shuffle(using: &rng)
            // Turn bias: try "continue straight" last. Plain random order produces long,
            // easily-guessable straight runs (recursive backtracker's usual signature) —
            // by the time "straight" is tried, the cell it leads to has often already been
            // claimed by a turn explored first, forcing an actual turn instead.
            if let entered = enteredFrom,
               let straightIndex = dirs.firstIndex(where: { $0.dr == entered.dr && $0.dc == entered.dc }) {
                dirs.append(dirs.remove(at: straightIndex))
            }

            for dir in dirs {
                let nr = cellRow + dir.dr, nc = cellCol + dir.dc
                guard nr >= 0, nr < cellRows, nc >= 0, nc < cellCols, !visited[nr][nc] else { continue }
                grid[cellRow * 2 + 1 + dir.dr][cellCol * 2 + 1 + dir.dc] = .floor(variant: Int.random(in: 0...1, using: &rng))
                carve(nr, nc, enteredFrom: dir)
            }
        }

        carve(0, startCellCol ?? cellCols / 2, enteredFrom: nil)

        // Braiding: a recursive backtracker produces a *perfect* maze (a spanning tree —
        // exactly one path between any two cells), so every wrong turn is a hard dead end
        // and there is only ever one correct choice at a fork. That's what reads as
        // "always the same" despite the seed changing each race — the branching shape is
        // structurally identical every time. Knock down one extra wall at ~half the dead
        // ends to create a loop back into the maze instead: a real left/right decision
        // (both lead somewhere) rather than a guaranteed-wrong guess.
        func cellDegree(_ cellRow: Int, _ cellCol: Int) -> Int {
            var degree = 0
            for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                let nr = cellRow + dr, nc = cellCol + dc
                guard nr >= 0, nr < cellRows, nc >= 0, nc < cellCols else { continue }
                if case .floor = grid[cellRow * 2 + 1 + dr][cellCol * 2 + 1 + dc] { degree += 1 }
            }
            return degree
        }
        for cellRow in 0..<cellRows {
            for cellCol in 0..<cellCols {
                guard cellDegree(cellRow, cellCol) == 1 else { continue }
                guard Double.random(in: 0..<1, using: &rng) < GameConfig.Obstacle.braidChance else { continue }
                var candidates: [(dr: Int, dc: Int)] = []
                for (dr, dc) in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
                    let nr = cellRow + dr, nc = cellCol + dc
                    guard nr >= 0, nr < cellRows, nc >= 0, nc < cellCols else { continue }
                    guard case .wall = grid[cellRow * 2 + 1 + dr][cellCol * 2 + 1 + dc] else { continue }
                    candidates.append((dr, dc))
                }
                guard let pick = candidates.randomElement(using: &rng) else { continue }
                grid[cellRow * 2 + 1 + pick.dr][cellCol * 2 + 1 + pick.dc] = .floor(variant: Int.random(in: 0...1, using: &rng))
            }
        }

        // The generator's a spanning tree over every cell (recursive backtracker always
        // visits the whole grid), so the deepest cell row always has a carved cell —
        // finish is the first one found there. Same seed -> same maze -> same finish on
        // both devices once this is networked.
        var finish = (row: rows - 2, col: cols / 2)
        outer: for row in stride(from: rows - 2, through: 1, by: -2) {
            for col in 0..<cols {
                if case .floor = grid[row][col] {
                    finish = (row, col)
                    break outer
                }
            }
        }

        // Obstacles only ever sit on connector tiles (exactly one of row/col even — the
        // 1-tile doorway between two room cells), never room tiles. Kept away from the
        // start (first few rows) and the finish (last few rows) so neither end of the
        // race opens with a forced hit.
        var connectorCandidates: [(row: Int, col: Int)] = []
        for row in 0..<rows {
            for col in 0..<cols {
                guard case .floor = grid[row][col] else { continue }
                let rowIsOdd = row % 2 == 1
                let colIsOdd = col % 2 == 1
                guard rowIsOdd != colIsOdd else { continue } // both odd = room tile, skip
                guard row > 5, abs(row - finish.row) > 3 else { continue }
                connectorCandidates.append((row, col))
            }
        }
        // Each obstacle carries its own Roll item (1 obstacle = 1 item), so clustering
        // them would let a player farm several charges almost for free in one stretch —
        // greedily enforce a minimum tile spacing between picks instead of pure random
        // sampling.
        let obstacleCount = connectorCandidates.count / GameConfig.Obstacle.densityDivisor
        var pickedObstacles: [(row: Int, col: Int)] = []
        for candidate in connectorCandidates.shuffled(using: &rng) {
            guard pickedObstacles.count < obstacleCount else { break }
            let farEnough = pickedObstacles.allSatisfy {
                abs($0.row - candidate.row) + abs($0.col - candidate.col) >= GameConfig.Obstacle.minSpacing
            }
            guard farEnough else { continue }
            pickedObstacles.append(candidate)
        }
        let obstacles = pickedObstacles.map { MazeObstacle(row: $0.row, col: $0.col) }

        return Maze(cols: cols, rows: rows, tiles: grid, finishPosition: finish, obstacles: Array(obstacles))
    }
}
