import Foundation
import UIKit
import CoreGraphics
import MultipeerConnectivity

@Observable
final class MatchViewModel {
    enum Phase: Equatable {
        case menu
        case searching
        case connected
        case readyCheck
        case introTour
        case secondReady
        case countdown
        case racing
        case finished
        case stats
    }

    enum MatchOutcome: Equatable { case won, lost, draw }

    /// D-063 item 7: one device's final counters, exchanged via `NetworkMessage
    /// .finalStats` at finish time (each device only knows its own directly).
    struct MatchStats: Equatable {
        var freezeUsed: Int
        var darkenUsed: Int
        var switchUsed: Int
        var shieldBlocks: Int
        var stuns: Int
        var progress: Int
    }

    let multipeer = MultipeerManager()

    private(set) var phase: Phase = .menu
    private(set) var showFoundMoment = false
    /// D-063 item 3: this device's own ready toggle at the ready-check gate.
    private(set) var localReady = false
    /// D-063 item 3: the opponent's ready toggle, mirrored from `.playerReady` messages.
    private(set) var opponentReady = false
    /// D-063 item 3: true while the reusable "opponent quit" alert is up — checked ahead
    /// of `phase` in ContentView so it can interrupt any gate it applies to.
    private(set) var showOpponentQuitAlert = false
    private(set) var raceViewModel: RaceViewModel?
    private(set) var opponentProgress = 0
    /// Latest known live position from the periodic `raceUpdate` broadcast (up to ~0.5s
    /// stale) — Switch's dash target. `.zero` until the first broadcast arrives, which
    /// is fine since Switch can't resolve before then (the race has barely started).
    private(set) var opponentPosition: CGPoint = .zero
    private(set) var timeRemaining: Double = GameConfig.Match.raceDuration
    private(set) var resultText: String?
    /// D-063 item 7: nil for a disconnect-triggered `endMatch` (no real winner, no stats
    /// to show) — non-nil is what gates the `.finished` → `.stats` auto-transition.
    private(set) var matchOutcome: MatchOutcome?
    private(set) var ownStats: MatchStats?
    private(set) var opponentStats: MatchStats?
    /// D-063 item 7: one-shot choices at the stats screen (not a toggle, like ready-check's
    /// switch — picking "main lagi" locks in immediately, matching the main menu's PLAY
    /// confirm pattern).
    private(set) var localWantsRematch = false
    private(set) var opponentWantsRematch = false

    private var matchTimer: Timer?
    /// D-072 followup: keeps the transport busy from the moment of connection until back
    /// at the menu, so `MCSession` notices a genuinely-dead peer faster during phases with
    /// no traffic of their own (see `NetworkMessage.heartbeat`). Runs alongside `matchTick`
    /// during `.racing` too — harmless duplicate traffic, not worth special-casing out.
    private var heartbeatTimer: Timer?
    /// D-062: wall-clock moment this device's own race started locally — the reference
    /// point for `.finishedAt`'s elapsed value. Set fresh in `startRacing`.
    private var raceStartTime: Date?
    /// D-062: nil until this device (resp. the opponent) actually finishes. Comparing
    /// the two elapsed values (not which finish message arrived first) is what fixes
    /// the near-simultaneous-finish bug — see `resolveFinish`.
    private var ownFinishedElapsed: TimeInterval?
    private var opponentFinishedElapsed: TimeInterval?
    private var countdownPreparedAt: Date?

    var connectionStatusText: String {
        guard multipeer.isConnected else { return "Finding enemy..." }
        return showFoundMoment ? "Enemy found!" : "Setting up maze..."
    }

    /// D-063 item 3: opponent's name for "LAWAN KAMU: ...", with the random `#NNNN`
    /// per-launch suffix (`MultipeerManager.peerID`) stripped — that suffix only exists
    /// to keep host election unambiguous, it's noise on screen.
    var opponentDisplayName: String {
        let full = multipeer.connectedPeers.first?.displayName ?? "?"
        return full.split(separator: "#").first.map(String.init) ?? full
    }

    /// D-063 item 7: same per-launch `#NNNN` suffix stripped as `opponentDisplayName`,
    /// for the stats screen's "WINNER <name>" title when this device won.
    var localDisplayName: String {
        let full = multipeer.localDisplayName
        return full.split(separator: "#").first.map(String.init) ?? full
    }

    /// D-063 item 7: the stats screen's title line — names the actual winner (not just
    /// "kamu/lawan") per the mockup's "WINNER xxxxxx", or "SERI" with no winner name.
    var finishTitle: String {
        switch matchOutcome {
        case .won: return "WINNER\n\(localDisplayName.uppercased())"
        case .lost: return "WINNER\n\(opponentDisplayName.uppercased())"
        case .draw: return "DRAW"
        case nil: return ""
        }
    }

    /// PRD 4.3: comparison only, not exact position. Opponent's progress *below* yours
    /// means they've descended further (ahead), so they read as visually "below" you.
    var opponentIndicatorText: String {
        guard let own = raceViewModel?.bestProgress else { return "" }
        if opponentProgress > own { return "Enemy is ahead" }
        if opponentProgress < own { return "Enemy is behind" }
        return "Tied"
    }

    enum OpponentStanding: Equatable { case ahead, behind, level }

    /// D-055 topRightHole icon (`vs_arrow_icon`): drives which way the arrow points
    /// (see `RaceView`'s vs-arrow HUD) — same comparison `opponentIndicatorText` already
    /// makes, just typed for the icon instead of formatted as Indonesian text.
    var opponentStanding: OpponentStanding {
        guard let own = raceViewModel?.bestProgress else { return .level }
        if opponentProgress > own { return .ahead }
        if opponentProgress < own { return .behind }
        return .level
    }

    init() {
        multipeer.onMessage = { [weak self] message in self?.handleReceived(message) }
    }

    /// D-063 item 1: the main menu's "PLAY" confirm — searching (and the multipeer
    /// advertise/browse it starts) no longer fires on app launch, only once the user
    /// actually picks Play.
    func selectPlay() {
        phase = .searching
        startSearching()
    }

    func startSearching() {
        multipeer.startAutoConnect()
    }

    /// Diamond at the matchmaking screen — only reachable while still `.searching`
    /// (no peer yet, so nothing to notify); once `.connected` the diamond/CANCEL affordance
    /// is hidden entirely (see `ContentView.lobbyScreen`), matching the ready-check gate's
    /// diamond which *does* notify the opponent because a peer already exists by then.
    func backToMenuFromSearching() {
        guard phase == .searching else { return }
        multipeer.stopAutoConnect()
        resetToMenu()
    }

    /// Called once, right when MultipeerConnectivity actually connects. The connection
    /// itself is near-instant with no physical "bring devices together" moment to react
    /// to, so this fakes one: haptic fires immediately, then a transient "found" message
    /// holds for a beat before settling into the ready-check gate (D-063 item 3) — racing
    /// no longer starts automatically here, only once both sides press ready.
    func handlePeerFound() async {
        GameFeedback.shared.perform(.success)
        showFoundMoment = true
        phase = .connected
        startHeartbeat()
        try? await Task.sleep(for: .seconds(1.5))
        showFoundMoment = false
        phase = .readyCheck
        localReady = false
        opponentReady = false
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.multipeer.send(.heartbeat)
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    /// Fires when `multipeer.isConnected` drops — most realistically mid-race (WiFi/
    /// Bluetooth congestion, a device carried out of range) or an unexpected drop while
    /// waiting at the ready-check gate. Treated as an unconditional cancelled match (no
    /// winner/loser, no stats) reusing the same `OpponentQuitAlertView` pattern as a
    /// deliberate quit — the previous `endMatch`-into-`resultScreen` path had no controls
    /// and no auto-transition, leaving the surviving device stuck until force-quit.
    /// Ignored once the match has already legitimately ended (`.finished`), hasn't started
    /// yet (`.searching`), or the disconnect was already explained by the `.opponentQuit`
    /// alert (deliberate quit — that flow owns the return-to-menu itself).
    func handlePeerLost() {
        guard phase == .racing || phase == .connected || phase == .readyCheck || phase == .introTour || phase == .secondReady || phase == .countdown || phase == .stats else { return }
        guard !showOpponentQuitAlert else { return }
        matchTimer?.invalidate()
        matchTimer = nil
        raceViewModel?.stopLoop()
        GameFeedback.shared.playMusic(nil)
        GameFeedback.shared.play(.resultLoss, haptic: .error)
        showOpponentQuitAlert = true
    }

    /// D-063 item 3: circle at the ready-check gate — toggles local ready like a switch,
    /// broadcasts it so the opponent's box updates, then checks whether both sides are
    /// now ready.
    func toggleReady() {
        guard phase == .readyCheck || phase == .secondReady else { return }
        localReady.toggle()
        multipeer.send(.playerReady(localReady))
        checkBothReady()
    }

    /// D-063 item 3: diamond at the ready-check gate — notify the opponent explicitly
    /// (so it shows the acknowledge-required alert instead of a silent drop), then
    /// disconnect and return to the main menu. This device returns to the menu
    /// immediately; the disconnect itself is delayed slightly (see below).
    func backToMenuFromReadyCheck() {
        guard phase == .readyCheck || phase == .secondReady else { return }
        multipeer.send(.opponentQuit)
        resetToMenu()
        disconnectAfterQuitMessage()
    }

    /// D-063 item 3: circle on the opponent-quit alert — acknowledge and return home.
    func acknowledgeOpponentQuit() {
        showOpponentQuitAlert = false
        multipeer.disconnect()
        resetToMenu()
    }

    /// D-063 item 7: circle-confirm on "main lagi" at the stats screen — a one-shot
    /// choice (not a toggle), matching the main menu's PLAY confirm. Locks in
    /// immediately; the "menunggu pemain lain" wait state is just this device sitting at
    /// `.stats` with `localWantsRematch == true` while `opponentWantsRematch` catches up.
    func chooseRematch() {
        guard phase == .stats, !localWantsRematch else { return }
        localWantsRematch = true
        multipeer.send(.rematchWant)
        checkBothWantRematch()
    }

    /// D-063 item 7: circle-confirm on "main menu" at the stats screen — same reusable
    /// opponent-quit pattern as the ready-check gate's diamond (D-063 item 3).
    func chooseMainMenuFromStats() {
        guard phase == .stats else { return }
        multipeer.send(.opponentQuit)
        resetToMenu()
        disconnectAfterQuitMessage()
    }

    private func checkBothWantRematch() {
        guard phase == .stats, localWantsRematch, opponentWantsRematch else { return }
        beginRematch()
    }

    /// D-063 item 7: "main lagi" is an instant rematch — the MultipeerConnectivity
    /// session stays connected, skipping straight back to ready-check instead of a full
    /// re-search. `raceViewModel` must go back to nil so `beginIntroTour`'s own
    /// `raceViewModel == nil` guard doesn't silently no-op the next race.
    private func beginRematch() {
        raceViewModel = nil
        countdownPreparedAt = nil
        resultText = nil
        matchOutcome = nil
        ownStats = nil
        opponentStats = nil
        localWantsRematch = false
        opponentWantsRematch = false
        localReady = false
        opponentReady = false
        phase = .readyCheck
    }

    /// `MCSession.send` hands data to the transport asynchronously — disconnecting the
    /// session right after calling it can tear down the connection before `.opponentQuit`
    /// actually transmits, so the opponent sees a generic connection drop
    /// (`handlePeerLost`'s "LAWAN TERPUTUS") instead of the intended quit alert. Confirmed
    /// live in Simulator: without this delay, that's exactly what happened. A short delay
    /// gives the message a moment to actually go out first.
    private func disconnectAfterQuitMessage() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.multipeer.disconnect()
        }
    }

    private func resetToMenu() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        countdownPreparedAt = nil
        phase = .menu
        localReady = false
        opponentReady = false
        showFoundMoment = false
        localWantsRematch = false
        opponentWantsRematch = false
        matchOutcome = nil
        resultText = nil
        ownStats = nil
        opponentStats = nil
        raceViewModel = nil
    }

    /// Electing the host is safe to call from either side, any number of times, once
    /// both are known ready — `electHostAndStart` only acts on the winning side, and
    /// `beginIntroTour`'s own `raceViewModel == nil` guard makes a second call a no-op.
    private func checkBothReady() {
        guard localReady, opponentReady else { return }
        switch phase {
        case .readyCheck: electHostAndStart()
        case .secondReady: startCountdownHandshake()
        default: break
        }
    }

    private var isHost: Bool {
        guard let opponent = multipeer.connectedPeers.first else { return false }
        return multipeer.localDisplayName < opponent.displayName
    }

    /// Both devices auto-connect symmetrically (D-021) — there's no pre-assigned
    /// host/joiner. Deterministic tie-break instead of a handshake: whichever peer's
    /// display name sorts first generates the seed and sends it; the other waits for
    /// `.matchStart`. Relies on the two test devices having distinct names, true for
    /// this jam's actual hardware (D-020).
    private func electHostAndStart() {
        if isHost {
            let seed = UInt64.random(in: UInt64.min...UInt64.max)
            multipeer.send(.matchStart(seed: seed))
            beginIntroTour(seed: seed)
        }
    }

    /// D-063 item 4: generates the real maze and shows the intro tour before racing
    /// starts for real. Split from the old `beginRace` — this half creates the
    /// `RaceViewModel` (so the tour has real maze/obstacle/finish data to fly through)
    /// but doesn't start its loop or the match timer yet; `startRacing` does that once
    /// the second ready-check and countdown (D-063 item 6) both finish.
    private func beginIntroTour(seed: UInt64) {
        guard raceViewModel == nil else { return }
        let vm = RaceViewModel(seed: seed)
        vm.onAttackResolved = { [weak self] type, blocked, position in
            self?.playAttackResolution(type, blocked: blocked)
            self?.multipeer.send(.attackResolved(type: type, blocked: blocked, position: position))
        }
        vm.onItemCollected = {
            GameFeedback.shared.play(.dicePickup, haptic: .light)
        }
        vm.onObstacleResolved = { blocked in
            GameFeedback.shared.play(blocked ? .shieldBlock : .obstacleHit, haptic: blocked ? .success : .heavy)
        }
        vm.onDashCompleted = {
            GameFeedback.shared.play(.switchResolve, haptic: .medium)
        }
        vm.opponentPositionProvider = { [weak self] in self?.opponentPosition ?? .zero }
        vm.onFinished = { [weak self] in self?.handleOwnFinish() }
        raceViewModel = vm
        // Clear the first ready-check's flags here, not in `finishIntroTour` — both
        // devices pass through this moment close together (same handoff as
        // `electHostAndStart`/`.matchStart`), so any `.playerReady` received from this
        // point on is unambiguously a fresh D-063 item 6 signal. Resetting on the way
        // *out* of the tour instead let a device that reaches the second gate slower
        // wipe out a ready signal the faster device had already sent — the slower
        // device would then wait forever for a re-send that never comes, since
        // `toggleReady()` only fires on an actual tap.
        localReady = false
        opponentReady = false
        phase = .introTour
    }

    /// Called once, either when the intro tour's own scripted duration elapses or the
    /// player skips it (circle button) — both routes converge here. D-063 item 6: moves
    /// to a second ready-check (reusing `ReadyCheckView`/`toggleReady`) instead of
    /// straight to racing — both sides confirm they're actually paying attention again
    /// before the synced countdown starts.
    func finishIntroTour() {
        guard phase == .introTour else { return }
        countdownPreparedAt = nil
        phase = .secondReady
    }

    private func startCountdownHandshake() {
        guard isHost, countdownPreparedAt == nil else { return }
        countdownPreparedAt = Date()
        multipeer.send(.countdownPrepare)
    }

    private func beginCountdown() {
        guard phase == .secondReady else { return }
        phase = .countdown
    }

    /// Called once the countdown view's own scripted duration finishes — starts the
    /// race for real (movement/timer). This is the second half of the old `beginRace`
    /// (see D-070's `beginIntroTour`, which built the `RaceViewModel` earlier so the
    /// tour had real maze data — that instance is reused here unchanged).
    func startRacing() {
        guard phase == .countdown, let vm = raceViewModel else { return }
        vm.startLoop()
        opponentProgress = 0
        raceStartTime = Date()
        ownFinishedElapsed = nil
        opponentFinishedElapsed = nil
        timeRemaining = GameConfig.Match.raceDuration
        phase = .racing
        startMatchTimer()
    }

    /// D-062: fires once, immediately, the instant this device's own `RaceViewModel`
    /// detects a finish — not on the next 0.5s tick, so the `.finishedAt` message reaches
    /// the opponent as fast as possible. Sends right away either way; only the *decision*
    /// waits (see `resolveFinishAfterGrace`) so an opponent finish that already happened
    /// but hasn't arrived yet gets a chance to be seen before this device locks in "MENANG".
    private func handleOwnFinish() {
        guard phase == .racing, ownFinishedElapsed == nil, let start = raceStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        ownFinishedElapsed = elapsed
        multipeer.send(.finishedAt(elapsed: elapsed))
        if let opponentElapsed = opponentFinishedElapsed {
            resolveFinish(ownElapsed: elapsed, opponentElapsed: opponentElapsed)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.Match.finishGraceWindow) { [weak self] in
                self?.resolveFinishAfterGrace()
            }
        }
    }

    /// Grace window elapsed with no opponent `.finishedAt` — this device genuinely
    /// finished first (or the opponent hasn't finished at all yet).
    private func resolveFinishAfterGrace() {
        guard phase == .racing, let ownElapsed = ownFinishedElapsed else { return }
        if let opponentElapsed = opponentFinishedElapsed {
            resolveFinish(ownElapsed: ownElapsed, opponentElapsed: opponentElapsed)
        } else {
            endMatch(resultText: "YOU WIN! You reached the finish first.", outcome: .won)
        }
    }

    /// Mirrors `resolveFinishAfterGrace` for the other side of the race: the opponent's
    /// `.finishedAt` arrived while this device was still racing. Without this, a device
    /// that hasn't reached the finish tile itself would keep racing indefinitely instead
    /// of stopping as soon as the opponent legitimately won.
    private func resolveOpponentFinishAfterGrace() {
        guard phase == .racing, let opponentElapsed = opponentFinishedElapsed else { return }
        if let ownElapsed = ownFinishedElapsed {
            resolveFinish(ownElapsed: ownElapsed, opponentElapsed: opponentElapsed)
        } else {
            endMatch(resultText: "YOU LOSE. Enemy reached the finish first.", outcome: .lost)
        }
    }

    /// The actual tie-break: whichever device measured a smaller elapsed-since-its-own-
    /// race-start wins, regardless of which `.finishedAt` message physically arrived
    /// first. Both devices run this same comparison once they know both elapsed values,
    /// so they always agree on the result.
    private func resolveFinish(ownElapsed: TimeInterval, opponentElapsed: TimeInterval) {
        guard phase == .racing else { return }
        if ownElapsed < opponentElapsed {
            endMatch(resultText: "YOU WIN! You reached the finish first.", outcome: .won)
        } else if ownElapsed > opponentElapsed {
            endMatch(resultText: "YOU LOSE. Enemy reached the finish first.", outcome: .lost)
        } else {
            endMatch(resultText: "DRAW. You reached the finish together.", outcome: .draw)
        }
    }

    private func startMatchTimer() {
        matchTimer?.invalidate()
        // See RaceViewModel.startLoop — `.scheduledTimer` alone stalls during touch
        // tracking (holding the D-pad), which would pause the position broadcast to the
        // opponent at exactly the moment movement is happening. `.common` keeps it live.
        let newTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.matchTick()
        }
        RunLoop.main.add(newTimer, forMode: .common)
        matchTimer = newTimer
    }

    private func matchTick() {
        guard phase == .racing, let vm = raceViewModel else { return }
        multipeer.send(.raceUpdate(progress: vm.bestProgress, position: vm.playerPosition))
        timeRemaining = max(0, timeRemaining - 0.5)

        if timeRemaining <= 0 {
            if vm.bestProgress > opponentProgress {
                endMatch(resultText: "YOU WIN! You got further when time ran out.", outcome: .won)
            } else if vm.bestProgress < opponentProgress {
                endMatch(resultText: "YOU LOSE. Enemy got further when time ran out.", outcome: .lost)
            } else {
                endMatch(resultText: "DRAW. Same progress when time ran out.", outcome: .draw)
            }
        }
    }

    /// A real match outcome (win/lose/draw only — disconnects go through `handlePeerLost`
    /// instead and never reach here). Packages this device's own counters, sends them (the
    /// opponent has no other way to learn them), and schedules the D-063 item 7 hand-off
    /// to the stats screen after a short beat on the plain text.
    private func endMatch(resultText: String, outcome: MatchOutcome) {
        matchTimer?.invalidate()
        matchTimer = nil
        raceViewModel?.stopLoop()
        phase = .finished
        self.resultText = resultText
        matchOutcome = outcome
        GameFeedback.shared.playMusic(nil)
        switch outcome {
        case .won:
            GameFeedback.shared.play(.resultWin, haptic: .success)
        case .lost:
            GameFeedback.shared.play(.resultLoss, haptic: .error)
        case .draw:
            GameFeedback.shared.perform(.medium)
        }
        guard let vm = raceViewModel else { return }
        let stats = MatchStats(
            freezeUsed: vm.freezeUsedCount,
            darkenUsed: vm.darkenUsedCount,
            switchUsed: vm.switchUsedCount,
            shieldBlocks: vm.shieldBlockCount,
            stuns: vm.obstacleHitCount,
            progress: vm.bestProgress
        )
        ownStats = stats
        multipeer.send(.finalStats(
            freezeUsed: stats.freezeUsed,
            darkenUsed: stats.darkenUsed,
            switchUsed: stats.switchUsed,
            shieldBlocks: stats.shieldBlocks,
            stuns: stats.stuns,
            progress: stats.progress
        ))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.transitionToStats()
        }
    }

    /// Guarded on both `phase` and `matchOutcome` — if a real disconnect happened during
    /// the 2s beat (unlikely, `handlePeerLost`'s guard already excludes `.finished`, but
    /// cheap to double-check), don't advance into a stats screen with a stale outcome.
    private func transitionToStats() {
        guard phase == .finished, matchOutcome != nil else { return }
        phase = .stats
        localWantsRematch = false
        opponentWantsRematch = false
    }

    /// Circle-button dispatch: Darken/Freeze/Switch telegraph on the opponent's device.
    /// Shield never reaches here — it auto-applies at roll time (RaceViewModel.rollSkill)
    /// and never enters the Activate queue, so `.shield` is unreachable but kept for an
    /// exhaustive switch.
    func handleActivate(_ type: SkillType) {
        switch type {
        case .shield:
            break
        case .darken, .freeze, .switchPlace:
            GameFeedback.shared.play(.attackCast, haptic: .medium)
            multipeer.send(.incomingAttack(type: type))
        }
    }

    private func playAttackResolution(_ type: SkillType, blocked: Bool) {
        if blocked {
            GameFeedback.shared.play(.shieldBlock, haptic: .success)
            return
        }
        switch type {
        case .freeze:
            GameFeedback.shared.play(.freezeHit, haptic: .heavy)
        case .darken:
            GameFeedback.shared.play(.darkenImpact, haptic: .medium)
            GameFeedback.shared.duckRaceMusic()
        case .switchPlace, .shield:
            break // Switch has its own cue after each local dash ends.
        }
    }

    private func handleReceived(_ message: NetworkMessage) {
        switch message {
        case .matchStart(let seed):
            beginIntroTour(seed: seed)
        case .raceUpdate(let progress, let position):
            opponentProgress = progress
            opponentPosition = position
        case .finishedAt(let elapsed):
            opponentFinishedElapsed = elapsed
            if let ownElapsed = ownFinishedElapsed {
                resolveFinish(ownElapsed: ownElapsed, opponentElapsed: elapsed)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.Match.finishGraceWindow) { [weak self] in
                    self?.resolveOpponentFinishAfterGrace()
                }
            }
        case .incomingAttack(let type):
            guard let raceViewModel else { return }
            GameFeedback.shared.play(.attackWarning, haptic: .warning)
            raceViewModel.beginIncomingAttack(type)
        case .attackResolved(let type, let blocked, let position):
            // Only Switch's attacker side acts on this — the receiver's pre-dash
            // position to dash to in turn. Darken/Freeze have no attacker-side effect.
            guard type == .switchPlace, !blocked, let position else { return }
            raceViewModel?.beginDash(to: position)
        case .playerReady(let ready):
            opponentReady = ready
            checkBothReady()
        case .countdownPrepare:
            guard phase == .secondReady else { return }
            multipeer.send(.countdownReady)
        case .countdownReady:
            guard phase == .secondReady, isHost, let preparedAt = countdownPreparedAt else { return }
            countdownPreparedAt = nil
            let estimatedOneWayDelay = Date().timeIntervalSince(preparedAt) / 2
            multipeer.send(.countdownGo)
            DispatchQueue.main.asyncAfter(deadline: .now() + estimatedOneWayDelay) { [weak self] in
                self?.beginCountdown()
            }
        case .countdownGo:
            beginCountdown()
        case .opponentQuit:
            guard phase == .readyCheck || phase == .stats else { return }
            GameFeedback.shared.playMusic(nil)
            GameFeedback.shared.play(.resultLoss, haptic: .error)
            showOpponentQuitAlert = true
        case .finalStats(let freezeUsed, let darkenUsed, let switchUsed, let shieldBlocks, let stuns, let progress):
            opponentStats = MatchStats(
                freezeUsed: freezeUsed,
                darkenUsed: darkenUsed,
                switchUsed: switchUsed,
                shieldBlocks: shieldBlocks,
                stuns: stuns,
                progress: progress
            )
        case .rematchWant:
            guard phase == .stats else { return }
            opponentWantsRematch = true
            checkBothWantRematch()
        case .heartbeat:
            break
        }
    }
}
