import Foundation
import CoreGraphics

@Observable
final class RaceViewModel {
    enum Direction {
        case up, down, left, right

        var opposite: Direction {
            switch self {
            case .up: return .down
            case .down: return .up
            case .left: return .right
            case .right: return .left
            }
        }
    }

    let maze: Maze
    var playerPosition: CGPoint
    /// What `MazeView` actually renders the world relative to. Equals `playerPosition`
    /// exactly along whichever axis the player is currently traveling (zero lag, same
    /// crisp tracking as before) but eases toward it on the other axis — see
    /// `updateCamera(direction:dt:)`. Exists so `laneAssist`'s corner correction (which
    /// must move `playerPosition` at a real, collision-checked speed to actually
    /// prevent snagging) doesn't itself read as the camera visibly wobbling sideways.
    var cameraPosition: CGPoint
    private let startY: Double

    /// D-028 supersedes PRD 3.4's original "no finish tile" design: reaching
    /// `maze.finishPosition` is now an instant win, with farthest-progress-at-60s
    /// staying as the fallback if nobody reaches it in time (timer isn't built here —
    /// priority #3). Tracks the *deepest* row ever reached, not current row, so
    /// backtracking into a dead end to try another path doesn't read as "losing
    /// progress" while testing.
    private(set) var bestProgress = 0
    private(set) var hasFinished = false

    /// D-063 item 7 (finish/stats screen) counters — each device tracks only its own,
    /// exchanged via `NetworkMessage.finalStats` at finish time. Displayed as "STUN" on
    /// the stats screen (that's the visible effect); named for the actual mechanism here
    /// (an obstacle hit, not a skill) since that's what actually increments it.
    private(set) var obstacleHitCount = 0
    /// Freeze/Darken/Switch each get their own count — incremented in `activateSkill()`'s
    /// dequeue based on which type came out (Shield never enters `heldSkills`, so a
    /// dequeue is always one of these three).
    private(set) var freezeUsedCount = 0
    private(set) var darkenUsedCount = 0
    private(set) var switchUsedCount = 0
    /// Successful blocks only, from either source (obstacle hit or incoming attack) —
    /// both route through `consumeShieldIfActive()`, so counting there is the one place
    /// that covers both without duplicating the increment at each call site.
    private(set) var shieldBlockCount = 0

    /// Seconds since the race started — drives the obstacle standing/falling/fallen/rising
    /// cycle (`MazeObstacle.state(at:)`) and the stun timer. Keeps ticking during a stun
    /// so obstacles don't freeze too.
    private(set) var elapsedTime: Double = 0
    private(set) var isStunned = false
    private var stunEndsAt: Double = 0

    /// Darken: vision-only, movement unaffected. Camera is always player-centered
    /// (MazeView renders the player sprite fixed at the viewport's own center), so the
    /// view layer just needs this boolean — the dark overlay itself is a static radial
    /// gradient, no per-frame position tracking needed.
    private(set) var isDarkened = false
    private var darkenEndsAt: Double = 0

    /// Grace window right after a stun ends so standing on the same obstacle's tile
    /// doesn't immediately re-trigger it.
    private var invulnerableUntil: Double = 0

    /// Shield: no duration, no Activate press — rolling one auto-applies it immediately
    /// (never enters `heldSkills`) and it sits active until it blocks exactly one hazard
    /// (an incoming attack or an obstacle hit), then it's consumed. Rolling a second
    /// Shield while one is already up is wasted — it doesn't stack or refresh.
    private(set) var isShielded = false

    /// The active incoming attack telegraphs before resolving; further attacks wait in
    /// order so every network message gets one resolution.
    private(set) var pendingAttack: SkillType?
    private var pendingAttackResolvesAt: Double = 0
    private var queuedAttacks: [SkillType] = []
    private var nextAttackStartsAt: Double = 0
    /// Set by MatchViewModel so a resolved attack can be reported back to the attacker.
    /// The `CGPoint?` is only meaningful for Switch: the receiver's own position right
    /// before it dashed away, which the attacker needs to dash to in turn. Nil for
    /// every other type, and for a blocked resolution.
    var onAttackResolved: ((SkillType, Bool, CGPoint?) -> Void)?
    /// Set by MatchViewModel: the opponent's latest known live position (from the
    /// periodic raceUpdate broadcast, up to ~0.5s stale — an accepted approximation).
    /// Read once, at the moment a resolved Switch needs a dash target.
    var opponentPositionProvider: (() -> CGPoint)?
    /// D-062: fires exactly once, the instant `hasFinished` flips true — lets
    /// MatchViewModel send the finish-timestamp message immediately instead of waiting
    /// for the next periodic broadcast tick.
    var onFinished: (() -> Void)?
    /// Gameplay event hooks keep this model independent from playback and UI details.
    var onItemCollected: (() -> Void)?
    var onObstacleResolved: ((Bool) -> Void)?
    var onDashCompleted: (() -> Void)?

    var pendingAttackCountdown: Double {
        guard pendingAttack != nil else { return 0 }
        return max(0, pendingAttackResolvesAt - elapsedTime)
    }

    /// Switch's dash: both sides run the exact real corridor route (never a straight
    /// line — the camera doesn't wall-check, so a straight-line move would visibly
    /// clip through walls) at a fixed total duration regardless of distance, so a
    /// far-apart swap doesn't eat a disproportionate chunk of the 60s race. Manual
    /// input is locked and obstacle collision is skipped for the whole dash (matches
    /// "it's the skill's own automated movement, not a walk" — see D-047).
    private(set) var isDashing = false
    private var dashWaypoints: [CGPoint] = []
    private var dashStartedAt: Double = 0

    /// Each obstacle carries its own Roll item (1 obstacle = 1 charge), parallel array
    /// indexed the same as `maze.obstacles`. Rolling itself is on a flat cooldown
    /// independent of Activate — charges can bank up while waiting it out.
    private(set) var rollCharges: Int = 0
    private var itemLastCollectedAt: [Double]

    /// Roll can queue up multiple held skills without needing Activate first. Which one
    /// Activate actually fires is `selectorType`, not queue order (D-072/D-073 playtest
    /// finding #5: strict FIFO forced a bad-timing skill out first) — see
    /// `advanceSelector()`/`activateSelectedSkill()`.
    private(set) var heldSkills: [SkillType] = []
    private var rollCooldownEndsAt: Double = 0

    /// Which held skill type the mini-screen's selector triangle points at and Activate
    /// (on hold) will fire. Always either `nil` (nothing held) or a type with
    /// `heldSkills` count > 0 — Shield never appears here, it auto-applies on Roll and
    /// never enters the queue.
    private(set) var selectorType: SkillType?

    /// Quick-tap on Activate: cycle the selector to the next held type. No-op with 0 or
    /// 1 distinct held types.
    func advanceSelector() {
        let heldTypes = SkillType.allCases.filter { $0 != .shield && heldSkills.contains($0) }
        guard heldTypes.count > 1, let current = selectorType,
              let index = heldTypes.firstIndex(of: current) else { return }
        selectorType = heldTypes[(index + 1) % heldTypes.count]
    }

    var canRoll: Bool {
        rollCharges > 0 && elapsedTime >= rollCooldownEndsAt
    }

    /// Per-obstacle (same indexing as `maze.obstacles`) whether that item is currently
    /// collectible — mirrors the exact respawn check `tick()`'s pickup loop already uses.
    var isItemAvailable: [Bool] {
        itemLastCollectedAt.map { elapsedTime - $0 >= GameConfig.Roll.itemRespawnCooldown }
    }

    /// 8Hz blink while stunned; always visible otherwise. View reads this to hide/show the sprite.
    var isSpriteVisible: Bool {
        !isStunned || Int(elapsedTime * 8) % 2 == 0
    }

    private(set) var activeDirection: Direction?
    private(set) var facingDirection: Direction = .down
    private(set) var walkFrame = 0

    /// `player_sprites` sheet layout (verified against the source template's per-direction
    /// GIF previews via pixel-exact template matching): row = direction, cols 0/1/3 are the
    /// 3 unique walk-cycle poses (col 2 duplicates col 0).
    private static let walkCycleCols = [0, 1, 0, 3]
    private var walkAnimAccumulator: TimeInterval = 0

    var spriteCell: (col: Int, row: Int) {
        let row: Int
        switch facingDirection {
        case .down: row = 0
        case .left: row = 2
        case .up: row = 4
        case .right: row = 6
        }
        return (Self.walkCycleCols[walkFrame], row)
    }

    private var timer: Timer?
    private var pressStartedAt: Date?
    private var releaseRequested = false

    // Viewport shows ~9 tiles wide (see MazeView.viewportCols). A maze only a little
    // wider than that (the old cellCols: 5 -> 11 tiles) is nearly all visible at once,
    // so every fork is already in view before you reach it — no real left/right
    // decision, it just reads as "follow the only path you can already see". Cols well
    // beyond the viewport keeps real width off-screen, forcing blind choices.
    let spawnPosition: CGPoint

    init(seed: UInt64 = 1, cellCols: Int = 11, cellRows: Int = 25) {
        maze = Maze.generate(seed: seed, cellCols: cellCols, cellRows: cellRows)
        let startCol = (cellCols / 2) * 2 + 1
        startY = 1.5
        let spawn = CGPoint(x: Double(startCol) + 0.5, y: startY)
        spawnPosition = spawn
        playerPosition = spawn
        cameraPosition = spawn
        itemLastCollectedAt = Array(repeating: -.infinity, count: maze.obstacles.count)
    }

    /// The 3 real points of interest the intro tour showcases (D-063 item 4): the
    /// player's own spawn, the finish tile, and the obstacle nearest to spawn — which
    /// doubles as introducing the Roll pickup, since every obstacle carries one at its
    /// tile center. Not a full route — showing the actual shortest path would spoil the
    /// maze's own challenge, per live feedback while testing the first (flythrough)
    /// version of this tour.
    var introTourPoints: [CGPoint] {
        let finishCenter = CGPoint(x: Double(maze.finishPosition.col) + 0.5, y: Double(maze.finishPosition.row) + 0.5)
        func distanceSquared(_ a: CGPoint, _ b: CGPoint) -> Double {
            let dx = a.x - b.x, dy = a.y - b.y
            return dx * dx + dy * dy
        }
        let nearestObstacle = maze.obstacles.min { lhs, rhs in
            let lhsCenter = CGPoint(x: Double(lhs.col) + 0.5, y: Double(lhs.row) + 0.5)
            let rhsCenter = CGPoint(x: Double(rhs.col) + 0.5, y: Double(rhs.row) + 0.5)
            return distanceSquared(spawnPosition, lhsCenter) < distanceSquared(spawnPosition, rhsCenter)
        }
        let obstacleCenter = nearestObstacle.map { CGPoint(x: Double($0.col) + 0.5, y: Double($0.row) + 0.5) } ?? finishCenter
        return [spawnPosition, finishCenter, obstacleCenter]
    }

    /// Consumes 1 charge and rolls a random skill. Shield never enters the queue — it
    /// auto-applies right here (or is wasted if one's already up); the other 3 types
    /// append to `heldSkills` as before. No-op (silently) if there's no charge banked or
    /// the flat cooldown hasn't elapsed yet — the view should gate the button on
    /// `canRoll` instead of relying on this being silent.
    func rollSkill() {
        guard canRoll else { return }
        rollCharges -= 1
        rollCooldownEndsAt = elapsedTime + GameConfig.Roll.cooldownDuration
        let rolled = SkillType.allCases.randomElement()!
        if rolled == .shield {
            if !isShielded { isShielded = true } // else wasted — doesn't stack/refresh
        } else {
            heldSkills.append(rolled)
            if selectorType == nil { selectorType = rolled } // don't dangle on nothing after the first pickup
        }
    }

    /// Uses (and removes) one instance of `selectorType` from `heldSkills`. Never returns
    /// `.shield` — it's applied at roll time and never enters this queue. Advances the
    /// selector to the next held type if this emptied the one it was pointing at.
    @discardableResult
    func activateSelectedSkill() -> SkillType? {
        guard let skill = selectorType, let index = heldSkills.firstIndex(of: skill) else { return nil }
        heldSkills.remove(at: index)
        switch skill {
        case .freeze: freezeUsedCount += 1
        case .darken: darkenUsedCount += 1
        case .switchPlace: switchUsedCount += 1
        case .shield: break // unreachable — Shield never enters heldSkills
        }
        if !heldSkills.contains(skill) {
            selectorType = SkillType.allCases.first { $0 != .shield && heldSkills.contains($0) }
        }
        return skill
    }

    /// Consumes the active Shield if one is up. Used by both the incoming-attack
    /// resolution and the obstacle-collision check — Shield blocks either.
    private func consumeShieldIfActive() -> Bool {
        guard isShielded else { return false }
        isShielded = false
        shieldBlockCount += 1
        return true
    }

    /// Called by MatchViewModel when `.incomingAttack` arrives from the opponent.
    func beginIncomingAttack(_ type: SkillType) {
        queuedAttacks.append(type)
        startNextQueuedAttackIfReady()
    }

    private func startNextQueuedAttackIfReady() {
        guard pendingAttack == nil,
              elapsedTime >= nextAttackStartsAt,
              !queuedAttacks.isEmpty else { return }
        pendingAttack = queuedAttacks.removeFirst()
        pendingAttackResolvesAt = elapsedTime + GameConfig.Skills.telegraphDuration
    }

    private func stun(for duration: Double) {
        isStunned = true
        stunEndsAt = elapsedTime + duration
        activeDirection = nil
    }

    /// Applies a resolved (non-blocked) attack's effect. Returns the position to report
    /// back via `onAttackResolved` — only Switch uses this (the attacker needs to know
    /// exactly where the receiver was standing, to dash there in turn).
    @discardableResult
    private func applyAttackEffect(_ type: SkillType) -> CGPoint? {
        switch type {
        case .freeze:
            stun(for: GameConfig.Skills.freezeDuration)
            return nil
        case .darken:
            isDarkened = true
            darkenEndsAt = elapsedTime + GameConfig.Skills.darkenDuration
            return nil
        case .switchPlace:
            let ownPositionBeforeSwap = playerPosition
            if let targetPosition = opponentPositionProvider?() {
                beginDash(to: targetPosition)
            }
            return ownPositionBeforeSwap
        case .shield:
            return nil
        }
    }

    /// Starts the dash animation toward `targetPosition` along the real corridor route.
    /// Called both when this device's own Switch resolves (target = opponent's latest
    /// known position) and when the attacker's `attackResolved` reply arrives (target =
    /// the receiver's exact pre-dash position).
    func beginDash(to targetPosition: CGPoint) {
        let startTile = (row: Int(playerPosition.y.rounded(.down)), col: Int(playerPosition.x.rounded(.down)))
        let targetTile = (row: Int(targetPosition.y.rounded(.down)), col: Int(targetPosition.x.rounded(.down)))
        let tilePath = bfsTilePath(from: startTile, to: targetTile)
        guard tilePath.count > 1 else {
            playerPosition = CGPoint(x: Double(targetTile.col) + 0.5, y: Double(targetTile.row) + 0.5)
            cameraPosition = playerPosition
            updateProgress()
            onDashCompleted?()
            return
        }
        dashWaypoints = tilePath.map { CGPoint(x: Double($0.col) + 0.5, y: Double($0.row) + 0.5) }
        isDashing = true
        dashStartedAt = elapsedTime
        activeDirection = nil
        invulnerableUntil = elapsedTime + GameConfig.Skills.dashDuration
    }

    /// BFS over walkable tiles — the maze is always fully connected (spanning-tree
    /// generation plus braiding, see `Maze.generate`), so an empty/unreachable result
    /// shouldn't happen in practice; falls back to snapping in place rather than
    /// crashing if it ever does.
    private func bfsTilePath(from start: (row: Int, col: Int), to target: (row: Int, col: Int)) -> [(row: Int, col: Int)] {
        if start.row == target.row, start.col == target.col { return [start] }
        func key(_ r: Int, _ c: Int) -> Int { r * maze.cols + c }
        var queue = [start]
        var cameFrom: [Int: Int] = [:]
        var visited = Set<Int>([key(start.row, start.col)])
        var head = 0
        while head < queue.count {
            let cur = queue[head]; head += 1
            if cur.row == target.row, cur.col == target.col { break }
            for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
                let nr = cur.row + dr, nc = cur.col + dc
                guard !maze.isBlocked(row: nr, col: nc) else { continue }
                let k = key(nr, nc)
                guard !visited.contains(k) else { continue }
                visited.insert(k)
                cameFrom[k] = key(cur.row, cur.col)
                queue.append((nr, nc))
            }
        }
        let targetKey = key(target.row, target.col)
        guard visited.contains(targetKey) else { return [start] }
        var path: [(row: Int, col: Int)] = [target]
        var curKey = targetKey
        while curKey != key(start.row, start.col) {
            guard let prevKey = cameFrom[curKey] else { return [start] }
            path.append((prevKey / maze.cols, prevKey % maze.cols))
            curKey = prevKey
        }
        return path.reversed()
    }

    private func updateDash(dt: Double) {
        walkAnimAccumulator += dt
        while walkAnimAccumulator >= GameConfig.Movement.walkFrameDuration {
            walkAnimAccumulator -= GameConfig.Movement.walkFrameDuration
            walkFrame = (walkFrame + 1) % Self.walkCycleCols.count
        }

        let segments = dashWaypoints.count - 1
        guard segments > 0 else {
            isDashing = false
            return
        }
        let t = min(1.0, (elapsedTime - dashStartedAt) / GameConfig.Skills.dashDuration)
        let scaledT = t * Double(segments)
        let segmentIndex = min(segments - 1, Int(scaledT))
        let localT = scaledT - Double(segmentIndex)
        let from = dashWaypoints[segmentIndex]
        let to = dashWaypoints[segmentIndex + 1]
        playerPosition = CGPoint(x: from.x + (to.x - from.x) * localT, y: from.y + (to.y - from.y) * localT)
        cameraPosition = playerPosition

        if to.x > from.x { facingDirection = .right }
        else if to.x < from.x { facingDirection = .left }
        else if to.y > from.y { facingDirection = .down }
        else if to.y < from.y { facingDirection = .up }

        updateProgress()

        if t >= 1.0 {
            isDashing = false
            playerPosition = dashWaypoints.last!
            onDashCompleted?()
        }
    }

    private func updateProgress() {
        bestProgress = max(bestProgress, Int(playerPosition.y - startY))
        // Tile-bounds equality alone fired as soon as the player's circle crossed into
        // the finish tile at all — including brushing its left edge while still mostly
        // in the corridor. Require the player to actually reach the tile's center
        // instead, so finishing reads as "arriving", not "grazing".
        let finishCenter = CGPoint(x: Double(maze.finishPosition.col) + 0.5, y: Double(maze.finishPosition.row) + 0.5)
        let dx = playerPosition.x - finishCenter.x
        let dy = playerPosition.y - finishCenter.y
        if (dx * dx + dy * dy).squareRoot() < GameConfig.Movement.finishArrivalRadius {
            // Snap both the hitbox and the camera dead-center on arrival — `tick()`
            // stops updating either one for good right after this (`guard !hasFinished`),
            // so whatever position is left here is what's on screen forever after. Without
            // this, "arrived" could still land (and freeze) anywhere inside the small
            // arrival radius, which read as "finish is still in the corner".
            playerPosition = finishCenter
            cameraPosition = finishCenter
            hasFinished = true
            onFinished?()
        }
    }

    func startLoop() {
        stopLoop()
        // `Timer.scheduledTimer` only registers on the run loop's `.default` mode, which
        // UIKit suspends while a touch gesture is actively tracking (e.g. holding the
        // D-pad) — the whole game loop would visibly stall until release. `.common`
        // keeps ticking through touch tracking too.
        let newTimer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick(dt: 1.0 / 60.0)
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stopLoop() {
        timer?.invalidate()
        timer = nil
    }

    func press(_ direction: Direction) {
        activeDirection = direction
        facingDirection = direction
        pressStartedAt = Date()
        releaseRequested = false
    }

    func release() {
        releaseRequested = true
    }

    private func tick(dt: Double) {
        elapsedTime += dt
        guard !hasFinished else { return }

        if isDarkened, elapsedTime >= darkenEndsAt {
            isDarkened = false
        }

        if let type = pendingAttack, elapsedTime >= pendingAttackResolvesAt {
            pendingAttack = nil
            nextAttackStartsAt = elapsedTime + 0.1
            let blocked = consumeShieldIfActive()
            let reportPosition = blocked ? nil : applyAttackEffect(type)
            onAttackResolved?(type, blocked, reportPosition)
        }
        startNextQueuedAttackIfReady()

        if isDashing {
            updateDash(dt: dt)
            return
        }

        if isStunned {
            if elapsedTime >= stunEndsAt {
                isStunned = false
                invulnerableUntil = elapsedTime + GameConfig.Skills.invulnerabilityDuration
            } else {
                walkFrame = 0
                walkAnimAccumulator = 0
                return
            }
        }

        if releaseRequested,
           let startedAt = pressStartedAt,
           Date().timeIntervalSince(startedAt) >= GameConfig.Movement.minimumPressDuration {
            activeDirection = nil
            pressStartedAt = nil
            releaseRequested = false
        }

        guard let direction = activeDirection else {
            walkFrame = 0
            walkAnimAccumulator = 0
            return
        }

        walkAnimAccumulator += dt
        while walkAnimAccumulator >= GameConfig.Movement.walkFrameDuration {
            walkAnimAccumulator -= GameConfig.Movement.walkFrameDuration
            walkFrame = (walkFrame + 1) % Self.walkCycleCols.count
        }

        var dx = 0.0, dy = 0.0
        switch direction {
        case .up: dy = -1
        case .down: dy = 1
        case .left: dx = -1
        case .right: dx = 1
        }
        dx *= GameConfig.Movement.speed * dt
        dy *= GameConfig.Movement.speed * dt

        let afterX = CGPoint(x: playerPosition.x + dx, y: playerPosition.y)
        if !collides(at: afterX) { playerPosition.x = afterX.x }

        let afterY = CGPoint(x: playerPosition.x, y: playerPosition.y + dy)
        if !collides(at: afterY) { playerPosition.y = afterY.y }

        laneAssist(direction: direction, dt: dt)
        updateCamera(direction: direction, dt: dt)

        if elapsedTime >= invulnerableUntil {
            for obstacle in maze.obstacles {
                let obstacleState = obstacle.state(at: elapsedTime)
                guard obstacleState.blocksPath else { continue }
                let obstaclePosition = obstacleState.hitboxPosition
                let dx = playerPosition.x - obstaclePosition.x
                let dy2 = playerPosition.y - obstaclePosition.y
                if (dx * dx + dy2 * dy2).squareRoot() < GameConfig.Movement.playerRadius + GameConfig.Obstacle.radius {
                    let blocked = consumeShieldIfActive()
                    if blocked {
                        // A blocked hit doesn't halt movement the way a real stun does
                        // (that early-returns out of tick() entirely while stunned), so
                        // without this the player stays overlapping the same obstacle's
                        // hitbox on the very next 60fps tick — shield is already
                        // consumed by then, so it silently stuns anyway. Grant the same
                        // grace window a stun's end normally gets, so one shield charge
                        // reliably absorbs the whole hit, not just its first frame.
                        invulnerableUntil = elapsedTime + GameConfig.Skills.invulnerabilityDuration
                    } else {
                        obstacleHitCount += 1
                        stun(for: GameConfig.Skills.stunDuration)
                    }
                    onObstacleResolved?(blocked)
                    break
                }
            }
        }


        for (index, obstacle) in maze.obstacles.enumerated() {
            guard elapsedTime - itemLastCollectedAt[index] >= GameConfig.Roll.itemRespawnCooldown else { continue }
            let itemCenter = CGPoint(x: Double(obstacle.col) + 0.5, y: Double(obstacle.row) + 0.5)
            let dx = playerPosition.x - itemCenter.x
            let dy2 = playerPosition.y - itemCenter.y
            if (dx * dx + dy2 * dy2).squareRoot() < GameConfig.Roll.itemPickupRadius {
                rollCharges += 1
                itemLastCollectedAt[index] = elapsedTime
                onItemCollected?()
            }
        }

        updateProgress()
    }

    /// D-050's circle-vs-tile fix stopped *false* blocks at corners, but a turn
    /// attempted while a few pixels off-center is still a *real* block (the circle
    /// genuinely clips the wall) — that's the residual "still catches a little"
    /// feeling. Rather than require pixel-perfect alignment before a turn registers,
    /// continuously drift the axis perpendicular to travel toward the corridor's lane
    /// center, one collision-checked step at a time, so the player is already
    /// centered by the time they reach an intersection.
    private func laneAssist(direction: Direction, dt: Double) {
        let maxStep = GameConfig.Movement.laneAssistSpeed * dt
        switch direction {
        case .left, .right:
            let target = playerPosition.y.rounded(.down) + 0.5
            let step = max(-maxStep, min(maxStep, target - playerPosition.y))
            let candidate = CGPoint(x: playerPosition.x, y: playerPosition.y + step)
            if !collides(at: candidate) { playerPosition.y = candidate.y }
        case .up, .down:
            let target = playerPosition.x.rounded(.down) + 0.5
            let step = max(-maxStep, min(maxStep, target - playerPosition.x))
            let candidate = CGPoint(x: playerPosition.x + step, y: playerPosition.y)
            if !collides(at: candidate) { playerPosition.x = candidate.x }
        }
    }

    /// Tracks `playerPosition` exactly on the axis the player is currently traveling
    /// (that axis only ever moves forward at the fixed walk speed, so there's nothing to
    /// smooth) and eases toward it on the other axis, which is the one `laneAssist` can
    /// move on its own at a different speed. Slower than `laneAssist` on purpose — see
    /// `GameConfig.Camera.cameraCatchUpSpeed`.
    private func updateCamera(direction: Direction, dt: Double) {
        let maxStep = GameConfig.Camera.cameraCatchUpSpeed * dt
        switch direction {
        case .left, .right:
            cameraPosition.x = playerPosition.x
            cameraPosition.y = Self.eased(cameraPosition.y, toward: playerPosition.y, maxStep: maxStep)
        case .up, .down:
            cameraPosition.y = playerPosition.y
            cameraPosition.x = Self.eased(cameraPosition.x, toward: playerPosition.x, maxStep: maxStep)
        }
    }

    private static func eased(_ current: Double, toward target: Double, maxStep: Double) -> Double {
        let diff = target - current
        if abs(diff) <= maxStep { return target }
        return current + (diff > 0 ? maxStep : -maxStep)
    }

    /// Circle-vs-tile, not box-vs-tile: a wall tile only blocks if the player's actual
    /// circle overlaps its square footprint (closest-point distance < radius), not merely
    /// because the tile falls inside the circle's bounding box. The bounding-box version
    /// false-blocked at every inside corner (an L-turn's far corner tile sits inside the
    /// box despite the circle never reaching it) — that's what read as "snags/can't turn
    /// smoothly right at a corner" and "walks flush along a wall it's merely brushing".
    private func collides(at point: CGPoint) -> Bool {
        let minRow = Int((point.y - GameConfig.Movement.playerRadius).rounded(.down))
        let maxRow = Int((point.y + GameConfig.Movement.playerRadius).rounded(.down))
        let minCol = Int((point.x - GameConfig.Movement.playerRadius).rounded(.down))
        let maxCol = Int((point.x + GameConfig.Movement.playerRadius).rounded(.down))
        for row in minRow...maxRow {
            for col in minCol...maxCol {
                guard maze.isBlocked(row: row, col: col) else { continue }
                let closestX = min(max(point.x, Double(col)), Double(col) + 1)
                let closestY = min(max(point.y, Double(row)), Double(row) + 1)
                let dx = point.x - closestX
                let dy = point.y - closestY
                if (dx * dx + dy * dy).squareRoot() < GameConfig.Movement.playerRadius {
                    return true
                }
            }
        }
        return false
    }
}
