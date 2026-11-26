import Foundation
import CoreGraphics

enum NetworkMessage: Codable {
    /// Sent once by whichever peer wins host election (MatchViewModel.startMatch), so
    /// both devices call Maze.generate(seed:) with the *same* seed — generating it
    /// independently on each side would produce two different mazes.
    case matchStart(seed: UInt64)
    /// Broadcast periodically while racing (PRD 4.3: every 0.5-1s). `progress` drives the
    /// simple "lawan di atas/bawah" indicator; `position` was added for Switch (D-047) —
    /// the receiver's dash target, accepted as up to ~0.5s stale. Finish state is no
    /// longer carried here — see `finishedAt` (D-062).
    case raceUpdate(progress: Int, position: CGPoint)
    /// D-062: sent immediately (not on the 0.5s `raceUpdate` cadence) the instant a
    /// device detects its own finish. `elapsed` is time since that device's own local
    /// race start — comparing the two devices' `elapsed` values (not arrival order)
    /// decides the winner, fixing the near-simultaneous-finish bug where each device
    /// could independently declare itself the winner. See `MatchViewModel.resolveFinish`.
    case finishedAt(elapsed: TimeInterval)
    /// Attacker's Activate press for Darken/Freeze/Switch (never Shield, which is
    /// self-only and applies with no network round-trip). Receiver telegraphs it for
    /// ~3s (RaceViewModel.beginIncomingAttack) before applying the effect.
    case incomingAttack(type: SkillType)
    /// Receiver's reply once its telegraph resolves. `position` is the receiver's own
    /// position right before it dashed away — only Switch's attacker side uses it (to
    /// dash there in turn via `RaceViewModel.beginDash(to:)`); nil for every other type
    /// and for a blocked resolution. Sent for all three attack types so the protocol
    /// stays uniform.
    case attackResolved(type: SkillType, blocked: Bool, position: CGPoint?)
    /// D-063 item 3: ready-check gate. Sent every time a device toggles its own ready
    /// state (circle press), so the opponent's KAMU/LAWAN box updates immediately.
    case playerReady(Bool)
    /// Host starts a short round-trip measurement before the final ready-check countdown.
    case countdownPrepare
    /// Reply to `countdownPrepare`, used to estimate one-way transport time.
    case countdownReady
    /// Starts the receiver's countdown; the host waits half the measured round-trip time.
    case countdownGo
    /// D-063 item 3: sent right before a device disconnects on purpose (diamond at the
    /// ready-check gate) — lets the opponent show an acknowledge-required alert instead
    /// of silently reading the disconnect as a dropped connection. Reusable at any future
    /// gate with the same "both players present" requirement, e.g. the rematch-wait gate
    /// (D-063 item 6).
    case opponentQuit
    /// D-063 item 7: sent once by each device the instant it finishes (or the match ends
    /// on the timer) — the opponent has no other way to know these counts, since each
    /// device only tracks its own `RaceViewModel` state. `stuns` is obstacle hits only
    /// (unblocked); `shieldBlocks` counts successful blocks only.
    case finalStats(freezeUsed: Int, darkenUsed: Int, switchUsed: Int, shieldBlocks: Int, stuns: Int, progress: Int)
    /// D-063 item 7: sent when a device picks "main lagi" at the finish/stats screen.
    /// Once both sides have sent this, both skip straight back to `.readyCheck` — the
    /// MultipeerConnectivity session stays connected, no re-search needed.
    case rematchWant
    /// D-072 followup: content-free ping sent on a repeating timer during every gate that
    /// has no periodic traffic of its own (connected/ready-check/intro-tour/countdown/
    /// stats — `.racing`'s own `raceUpdate` broadcast already covers that phase). Real-
    /// device playtest found a real disconnect (force-quit) can take several seconds
    /// longer for `MCSession` to surface via `connectedPeers` during a silent phase than
    /// during racing's active traffic — this keeps the transport busy so a genuinely-dead
    /// peer is more likely to be noticed promptly. No payload; the receiver does nothing
    /// with it beyond decoding.
    case heartbeat
}
