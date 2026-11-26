import Foundation

/// Single home for every tunable gameplay value — durations, radii, speeds, maze-gen
/// density — so a tuning pass touches one file instead of hunting across the codebase.
enum GameConfig {
    enum Match {
        static let raceDuration: Double = 180
        /// D-062: how long a device waits after its own finish before declaring a win,
        /// giving an already-in-flight `.finishedAt` from the opponent a chance to
        /// arrive — see `MatchViewModel.handleOwnFinish`.
        static let finishGraceWindow: Double = 0.4
    }

    enum Movement {
        static let speed: Double = 3.0 // tiles per second
        static let playerRadius: Double = 0.3
        static let walkFrameDuration: TimeInterval = 0.12
        // A quick tap only overlaps a couple of 60fps ticks — barely a pixel of movement,
        // so it reads as "the D-pad doesn't respond to taps, only drags". Guarantee every
        // press stays active at least this long, however briefly it's actually held.
        static let minimumPressDuration: TimeInterval = 0.12
        // How fast the off-axis coordinate drifts toward the corridor's lane center
        // while walking. Faster than `speed` so it resolves well before the player
        // reaches the next turn instead of trailing behind them.
        static let laneAssistSpeed: Double = 6.0 // tiles per second
        // How close to a finish tile's exact center counts as "arrived" — see
        // `updateProgress()`. Must clear `playerRadius` (0.3) plus a little slack so a
        // player who is merely brushing the tile's edge doesn't trigger it.
        static let finishArrivalRadius: Double = 0.15
    }

    enum Skills {
        static let stunDuration: Double = 1.0
        static let freezeDuration: Double = 3.0
        static let darkenDuration: Double = 5.0
        /// Radius (in tiles) of the still-visible circle around the player while darkened.
        static let darkenVisionRadius: Double = 2.5
        /// Grace window right after a stun ends so standing on the same obstacle's tile
        /// doesn't immediately re-trigger it.
        static let invulnerabilityDuration: Double = 2.0
        static let telegraphDuration: Double = 3.0
        static let dashDuration: Double = 1.5
        /// D-072/D-073 playtest finding #5: how long Activate must be held to fire the
        /// selected skill (a quick tap instead cycles the selector — see
        /// `RaceViewModel.advanceSelector()`). Placeholder, tune via playtest.
        static let activateHoldDuration: Double = 0.4
        /// A release at or before this counts as a deliberate tap (cycles the selector).
        /// A release AFTER this but before `activateHoldDuration` is a failed/aborted hold
        /// attempt, not a tap — does nothing. Without this dead zone, releasing a fraction
        /// too early to activate silently cycled the selector instead, which read as "I
        /// held it and it jumped to a different skill" (real user-reported bug).
        static let tapMaxDuration: Double = 0.15
    }

    enum Roll {
        static let itemRespawnCooldown: Double = 8.0
        static let itemPickupRadius: Double = 0.35
        static let cooldownDuration: Double = 5.0
    }

    enum Obstacle {
        static let radius: Double = 0.22
        static let braidChance: Double = 0.5 // ponytail: fixed rate, not tuned per-maze-size; revisit if playtest wants more/fewer loops
        static let densityDivisor = 6 // was /4 — user felt obstacles+items were too dense on screen
        static let minSpacing = 6 // was 4, same density complaint // ponytail: fixed spacing, not tuned per-maze-size; revisit if playtest wants denser/sparser items

        // Standing/falling/fallen/rising cycle (replaces the old left-right/up-down sway).
        // Idle holds (user-picked, brainstormed before building): 3s fully standing
        // (parked outside the path, safe) before it starts to fall, 3s fully fallen
        // (lying across the path, blocks — see `MazeObstacle.state(at:)`) before it
        // starts to rise. Frame speeds are the sprite sheet author's own spec.
        static let standingDuration: Double = 3.0
        static let fallenDuration: Double = 3.0
        // Sprite-0007 (obstacle v3): 4 frames, 2 fall transitions (no 3-way split like the
        // first sheet had) — frame 2 held 120ms, then frame 3 held 120ms, then frame 4.
        static let fallFrame1Duration: Double = 0.12 // frame 2 ("mulai miring") held before frame 3 appears
        static let fallFrame2Duration: Double = 0.12 // frame 3 ("hampir roboh") held before frame 4 (fallen) appears
        // Rising timing isn't specified by the sprite's own spec (fall-only) — mirrored
        // from the fall durations, same convention as the first sheet ("waktu sama, dibalik").
        static let riseFrame3Duration: Double = 0.12
        static let riseFrame2Duration: Double = 0.12

        // How far (in tiles) the obstacle is parked toward its flanking wall while
        // standing, swinging in to the tile center (fully "fallen", lying across the
        // passage) and back out again each cycle. Split into 2 separate offsets:
        // `hitboxEdgeOffset` bounds how far the *collision* circle can sit off-center
        // and still fully block the corridor — 0.32 tiles is the hard ceiling (a 1-tile
        // corridor, playerRadius 0.3, this radius 0.22: beyond that, a real gap opens on
        // the far side and the tree stops actually blocking). `spriteEdgeOffset` is
        // purely visual and has no such ceiling — the flanking wall is itself a full
        // adjacent tile, so the sprite can push well into it with zero gameplay effect.
        static let hitboxEdgeOffset: Double = 0.3 // ponytail: fixed, close to the 0.32 safety ceiling — don't raise without re-deriving that ceiling
        // User's core ask, made precise: while standing, ZERO sprite pixels should
        // overlap the corridor tile at all. Measured directly (not guessed) from the
        // standing frame's actual alpha channel: its non-transparent content comes within
        // 2px of the frame's bottom edge (the tightest of its 4 margins, out of 48px) —
        // so the offset needs to clear at least 1.0 - 2/48 ≈ 0.958 tiles for that margin
        // to fully exit the corridor regardless of which edge ends up path-facing after
        // rotation/flip. 0.98 adds a small buffer for anti-aliased edge pixels.
        static let spriteEdgeOffset: Double = 0.98 // was 0.3, then 0.55 — both were guesses; this is measured from the actual sprite sheet
    }

    /// D-055 3-slot HUD (timer/vs-arrow/mini-screen icons + their code-driven animations).
    enum HUD {
        static let timerBlinkThreshold: Double = 10 // seconds remaining
        static let timerBlinkInterval: Double = 0.4
        static let warningBlinkInterval: Double = 0.25
        static let vsArrowBounceDuration: Double = 0.35
        static let planeFrameDuration: Double = 0.12
        static let gachaCycleDuration: Double = 0.6 // rapid-cycle phase before locking to the real result
        static let gachaLockHoldDuration: Double = 0.8 // how long the locked result stays on screen after settling
        static let shieldUsedMessageDuration: Double = 1.2 // D-058: "SHIELD USED" transient in the bottom shelf

        // D-060: 4-beat plane choreography shared by the send flourish and the
        // incoming-attack plane (`RaceView.PlaneChoreography`) — fly in, pause, drop
        // cargo in/out, fly out (accelerating, for a "gas tancap" departure feel).
        static let planeFlyInDuration: Double = 0.32
        static let planePauseDuration: Double = 0.12
        static let planeTransferDuration: Double = 0.18
        static let planeFlyOutDuration: Double = 0.38
    }

    /// D-063 item 4: showcase tour — camera pans between 3 real points of interest
    /// (spawn/finish/nearest obstacle) before racing starts, each held with a caption.
    enum IntroTour {
        static let holdDuration: Double = 2.0 // seconds each point is held with its caption visible
        static let panDuration: Double = 0.8 // seconds to glide the camera between points
    }

    /// D-063 item 6: synced countdown between the second ready-check and racing.
    enum Countdown {
        static let stepDuration: Double = 0.8 // seconds each of 3/2/1/MULAI is shown
    }

    enum Camera {
        static let viewportCols = 7
        static let itemBobAmplitude: Double = 0.12
        static let itemBobPeriod: Double = 1.4
        static let itemFrameDuration: Double = 0.15
        // How fast the camera's off-travel axis catches up to the player's actual
        // (lane-assisted) position — see `RaceViewModel.updateCamera`. Deliberately
        // slower than `Movement.laneAssistSpeed` so a corner correction reads as a
        // gentle glide on screen instead of the camera visibly snapping/wobbling
        // sideways at the same speed the hitbox is being nudged.
        static let cameraCatchUpSpeed: Double = 3.0 // tiles per second
    }
}
