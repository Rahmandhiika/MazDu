import SwiftUI

/// Player-centric camera: renders only the tiles visible around `cameraPosition`
/// (tile-space, same units as `RaceViewModel.playerPosition`) so the world appears
/// to scroll while the player stays visually centered. `cameraPosition` isn't always
/// bit-identical to `playerPosition` — it eases in on the axis perpendicular to travel
/// (see `RaceViewModel.updateCamera`) so a corner-turn correction glides instead of
/// visibly snapping the camera sideways. The gap is small and self-corrects within a
/// few frames, not a persistent offset.
struct MazeView: View {
    let maze: Maze
    let cameraPosition: CGPoint
    let spriteCell: (col: Int, row: Int)
    var elapsedTime: Double = 0
    var isPlayerVisible: Bool = true
    var isItemAvailable: [Bool] = []
    var isDarkened: Bool = false

    var body: some View {
        GeometryReader { geo in
            let viewportCols = GameConfig.Camera.viewportCols
            let tileSize = geo.size.width / CGFloat(viewportCols)
            let viewportRows = Int((geo.size.height / tileSize).rounded(.up))
            let originCol = Int(cameraPosition.x.rounded(.down)) - viewportCols / 2 - 1
            let originRow = Int(cameraPosition.y.rounded(.down)) - viewportRows / 2 - 1

            ZStack(alignment: .topLeading) {
                Color(red: 0.027, green: 0.094, blue: 0.129) // #071821 — void beyond generated maze

                ForEach(0...(viewportRows + 2), id: \.self) { r in
                    ForEach(0...(viewportCols + 2), id: \.self) { c in
                        let row = originRow + r
                        let col = originCol + c
                        Group {
                            if row == maze.finishPosition.row, col == maze.finishPosition.col {
                                // D-028: a marathon-style checkered finish line on the
                                // ground you visibly walk across, not just a small icon
                                // easy to miss from a distance.
                                finishLineTile(tileSize: tileSize)
                            } else {
                                tileImage(for: maze.tile(row: row, col: col))
                                    .resizable()
                                    .interpolation(.none)
                            }
                        }
                        .frame(width: tileSize, height: tileSize)
                        .position(
                            x: (CGFloat(col) + 0.5 - cameraPosition.x) * tileSize + geo.size.width / 2,
                            y: (CGFloat(row) + 0.5 - cameraPosition.y) * tileSize + geo.size.height / 2
                        )
                    }
                }

                ForEach(Array(maze.obstacles.enumerated()), id: \.offset) { index, obstacle in
                    if index < isItemAvailable.count, isItemAvailable[index] {
                        // Static tile center — doesn't sway with the obstacle, just bobs
                        // and spins in place so it reads as "collectible sitting here".
                        let bob = sin(elapsedTime * 2 * .pi / GameConfig.Camera.itemBobPeriod) * GameConfig.Camera.itemBobAmplitude
                        let frame = Int(elapsedTime / GameConfig.Camera.itemFrameDuration) % Self.rollItemFrames.count
                        Image(uiImage: Self.rollItemFrames[frame])
                            .resizable()
                            .interpolation(.none)
                            .frame(width: tileSize * 0.85, height: tileSize * 0.85)
                            .position(
                                x: (Double(obstacle.col) + 0.5 - cameraPosition.x) * tileSize + geo.size.width / 2,
                                y: (Double(obstacle.row) + 0.5 + bob - cameraPosition.y) * tileSize + geo.size.height / 2
                            )
                    }

                    let obstacleState = obstacle.state(at: elapsedTime)
                    let obstacleFrameSet = obstacle.swingsVertically ? Self.obstacleFramesVertical : Self.obstacleFrames
                    Image(uiImage: obstacleFrameSet[obstacleState.frame.rawValue])
                        .resizable()
                        .interpolation(.none)
                        .frame(width: tileSize, height: tileSize)
                        .scaleEffect(x: obstacle.spriteFlippedHorizontally ? -1 : 1, y: 1)
                        .position(
                            x: (obstacleState.spritePosition.x - cameraPosition.x) * tileSize + geo.size.width / 2,
                            y: (obstacleState.spritePosition.y - cameraPosition.y) * tileSize + geo.size.height / 2
                        )
                }

                playerSprite(tileSize: tileSize)
                    .opacity(isPlayerVisible ? 1 : 0)
                    .position(
                        x: geo.size.width / 2,
                        // The down-facing frames have ~0px of empty margin at the sprite's
                        // own bottom edge in the source art (unlike up/left/right, which
                        // have 1-2px) — nudge the whole sprite up a hair so its feet don't
                        // visually poke into a wall tile directly below when resting flush
                        // against one. ponytail: single fixed nudge for the one direction
                        // that needed it, not a per-direction offset table; revisit if
                        // up/left/right ever start reading as clipped too.
                        y: geo.size.height / 2 - (spriteCell.row == 0 ? tileSize * 0.12 : 0)
                    )

                if isDarkened {
                    darkenOverlay(tileSize: tileSize, geo: geo)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    /// Static radial gradient centered on the viewport — no per-frame tracking needed
    /// since the camera always keeps the player at the exact screen center. Fade starts
    /// at half the vision radius and reaches full black at the radius itself; beyond
    /// that SwiftUI clamps to the last stop, so the whole viewport (including corners
    /// past `endRadius`) stays covered.
    private func darkenOverlay(tileSize: CGFloat, geo: GeometryProxy) -> some View {
        let visionRadius = tileSize * CGFloat(GameConfig.Skills.darkenVisionRadius)
        let maxRadius = sqrt(pow(geo.size.width, 2) + pow(geo.size.height, 2))
        return RadialGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black.opacity(0), location: visionRadius * 0.5 / maxRadius),
                .init(color: .black, location: visionRadius / maxRadius)
            ],
            center: .center,
            startRadius: 0,
            endRadius: maxRadius
        )
        .frame(width: geo.size.width, height: geo.size.height)
        .position(x: geo.size.width / 2, y: geo.size.height / 2)
        .allowsHitTesting(false)
    }

    private func finishLineTile(tileSize: CGFloat) -> some View {
        let cell = tileSize / 4
        let dark = Color(red: 0.027, green: 0.094, blue: 0.129)
        let light = Color(red: 0.878, green: 0.973, blue: 0.812)
        return VStack(spacing: 0) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { col in
                        ((row + col).isMultiple(of: 2) ? light : dark)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
    }

    private func tileImage(for tile: Tile) -> Image {
        switch tile {
        case .wall: return Image("wall_tile")
        case .floor(let variant): return Image(variant == 0 ? "floor_tile" : "floor_tile_2")
        }
    }

    /// 8x8 grid of 16x16 frames; row = facing direction, col = walk-cycle pose
    /// (`RaceViewModel.spriteCell`, verified against the source template's GIFs).
    /// Each used cell is pre-cropped to its own bitmap (see `croppedCell`) so SwiftUI
    /// never has to offset+clip a scaled-up sheet at render time — that approach let
    /// fractional-pixel drift bleed a sliver of the neighboring cell's chroma-key
    /// green through, worse for cells further from the sheet's origin (e.g. "up").
    private static let playerFrames: [Int: [Int: UIImage]] = {
        let raw = UIImage(named: "player_sprites") ?? UIImage()
        let sheet = raw.chromaKeyed(removing: (101, 255, 0))
        var frames: [Int: [Int: UIImage]] = [:]
        for row in [0, 2, 4, 6] {
            var cols: [Int: UIImage] = [:]
            for col in [0, 1, 3] {
                cols[col] = sheet.croppedCell(col: col, row: row, cellSize: 16)
            }
            frames[row] = cols
        }
        return frames
    }()

    private func playerSprite(tileSize: CGFloat) -> some View {
        Self.playerFrame(col: spriteCell.col, row: spriteCell.row)
            .resizable()
            .interpolation(.none)
            .frame(width: tileSize, height: tileSize)
    }

    /// Reuses the same pre-cropped gameplay frames for small UI animations, keeping
    /// the player readable and avoiding a second sprite-sheet cropping path.
    static func playerFrame(col: Int, row: Int) -> Image {
        Image(uiImage: playerFrames[row]?[col] ?? UIImage())
    }

    /// Half (left or right 8 of the standing frame's 16px width) of a player frame —
    /// whichever half actually has the face (the eye/eyebrow detail sits on the same
    /// side the character faces; the other half is a mostly-blank back-of-head/body,
    /// verified by inspecting the raw sheet). Lets a UI spot show a tighter, more
    /// zoomed-in crop than the full sprite without just stretching it, e.g. the main
    /// menu's poster background pinned flush to a screen edge.
    static func playerHalfFrame(row: Int, keepRightHalf: Bool, height: Int = 16) -> Image {
        let standing = playerFrames[row]?[0] ?? UIImage()
        return Image(uiImage: standing.croppedCell(col: keepRightHalf ? 1 : 0, row: 0, width: 8, height: height))
    }

    /// 4-frame die-face spin (roll_item.png, 64x16, real alpha — no chroma key needed).
    private static let rollItemFrames: [UIImage] = {
        let sheet = UIImage(named: "roll_item") ?? UIImage()
        return (0..<4).map { sheet.croppedCell(col: $0, row: 0, cellSize: 16) }
    }()

    /// 4-frame standing/leaning/reclining/fallen sheet (obstacle_tree, 192x48, real alpha
    /// — no chroma key needed), indexed by `ObstacleFrame.rawValue`. For obstacles on a
    /// vertical (north-south) corridor — walls flank left/right. Default art assumes the
    /// obstacle is parked against its right-hand wall (root right, falls left) —
    /// `MazeObstacle.spriteFlippedHorizontally` mirrors it for the left wall.
    private static let obstacleFrames: [UIImage] = {
        let sheet = UIImage(named: "obstacle_tree") ?? UIImage()
        return (0..<4).map { sheet.croppedCell(col: $0, row: 0, cellSize: 48) }
    }()

    /// Same 4-state layout as `obstacleFrames` but for obstacles on a horizontal
    /// (east-west) corridor — walls flank top/bottom, and this asset is drawn falling
    /// straight down rather than sideways (a separate hand-drawn sheet, not a rotation of
    /// `obstacleFrames` — rotating pixel art to an arbitrary angle aliases badly). Always
    /// parked at the top wall, falling straight down — `MazeObstacle.sideSign` never
    /// picks the bottom wall for these, so no vertical flip is ever needed.
    private static let obstacleFramesVertical: [UIImage] = {
        let sheet = UIImage(named: "obstacle_tree_vertical") ?? UIImage()
        return (0..<4).map { sheet.croppedCell(col: $0, row: 0, cellSize: 48) }
    }()
}
