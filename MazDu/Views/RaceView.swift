import SwiftUI

/// Shared with every private HUD view below `RaceView` too — kept file-scope (not a
/// static member) because `RaceView` itself is generic, where stored static properties
/// aren't allowed.
private let raceScreenGreen = Color(red: 0.878, green: 0.973, blue: 0.812)
private let raceScreenDark = Color(red: 0.027, green: 0.094, blue: 0.129)
/// D-058: a more saturated green for "this skill slot is active" — distinct from the
/// pale `raceScreenGreen` mini-screen backdrop, so an active card doesn't just blend
/// into the background it's sitting on.
private let raceAccentGreen = Color(red: 0.42, green: 0.75, blue: 0.40)

/// Maze + movement screen. Owns its own `RaceViewModel` by default (standalone
/// testing/`#Preview`), or takes one from the caller (`MatchViewModel`, once a seed is
/// agreed over the network) so both devices race the identical generated maze.
struct RaceView<TopLeftHUD: View, TopRightHUD: View>: View {
    @State private var viewModel: RaceViewModel
    @ViewBuilder private var topLeftHUD: () -> TopLeftHUD
    @ViewBuilder private var topRightHUD: () -> TopRightHUD
    private var onActivate: (SkillType) -> Void

    /// D-055 animation #4 (send/receive): a local-only flourish, no new network message.
    /// Set right when Activate dispatches a skill, cleared after the full
    /// `PlaneChoreography` plays out.
    @State private var sendingFlourish: SendFlourish?
    /// Mirrors `viewModel.pendingAttack` becoming non-nil — drives the incoming plane's
    /// fly-in/pause/drop-warning/fly-out choreography (D-060).
    @State private var incomingPlane: IncomingPlane?
    @State private var gachaReveal: GachaReveal?
    /// D-058: transient "SHIELD USED" message in the bottom shelf, triggered whenever
    /// `isShielded` flips true→false (either an incoming attack was blocked, or a local
    /// obstacle hit was) — see the `onChange` below.
    @State private var shieldUsedMessage = false

    /// D-072/D-073 finding #5: tap-vs-hold on Activate. Non-nil while the circle is
    /// physically down; a release before `GameConfig.Skills.activateHoldDuration` reads
    /// as a tap (advance the selector), reaching the threshold first fires the currently
    /// selected skill. Cleared by whichever of the two happens first, so the other is a
    /// no-op — see `handleCirclePress()`/`handleCircleRelease()`.
    @State private var circlePressStartedAt: Date?
    /// Drives the selected skill card's fill animation — true the instant the circle is
    /// pressed, false the instant it's released or the hold threshold fires.
    @State private var isHoldingCircle = false

    init(
        viewModel: RaceViewModel = RaceViewModel(),
        onActivate: @escaping (SkillType) -> Void = { _ in },
        @ViewBuilder topLeftHUD: @escaping () -> TopLeftHUD = { EmptyView() },
        @ViewBuilder topRightHUD: @escaping () -> TopRightHUD = { EmptyView() }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onActivate = onActivate
        self.topLeftHUD = topLeftHUD
        self.topRightHUD = topRightHUD
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            DeviceShellView {
                ZStack(alignment: .top) {
                    MazeView(
                        maze: viewModel.maze,
                        cameraPosition: viewModel.cameraPosition,
                        spriteCell: viewModel.spriteCell,
                        elapsedTime: viewModel.elapsedTime,
                        isPlayerVisible: viewModel.isSpriteVisible,
                        isItemAvailable: viewModel.isItemAvailable,
                        isDarkened: viewModel.isDarkened
                    )

                    Text("↓ \(viewModel.bestProgress)")
                        .font(.pixel(11))
                        .foregroundStyle(raceScreenGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(raceScreenDark.opacity(0.7))

                    if viewModel.hasFinished {
                        VStack {
                            Spacer()
                            Text("FINISH!")
                                .font(.pixel(18))
                                .foregroundStyle(raceScreenDark)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(raceScreenGreen)
                            Spacer()
                        }
                    }
                }
            } topLeftContent: {
                topLeftHUD()
            } topRightContent: {
                topRightHUD()
            } miniScreenContent: {
                miniScreenHUD
            } controls: { scale in
                DPadControl(
                    scale: scale,
                    activeDirection: viewModel.activeDirection,
                    onPress: { direction in viewModel.press(direction) },
                    onRelease: { viewModel.release() }
                )
                TapButtonControl(hole: ShellLayout.diamondHole, scale: scale) {
                    performRoll()
                }
                HoldButtonControl(hole: ShellLayout.circleHole, scale: scale) {
                    handleCirclePress()
                } onRelease: {
                    handleCircleRelease()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .onAppear { viewModel.startLoop() }
        .onDisappear { viewModel.stopLoop() }
        .onChange(of: viewModel.pendingAttack) { previous, current in
            guard previous == nil, current != nil else { return }
            let plane = IncomingPlane(startedAt: Date())
            incomingPlane = plane
            DispatchQueue.main.asyncAfter(deadline: .now() + PlaneChoreography.totalDuration) {
                if incomingPlane?.startedAt == plane.startedAt { incomingPlane = nil }
            }
        }
        .onChange(of: viewModel.isShielded) { was, isNow in
            guard was, !isNow else { return }
            shieldUsedMessage = true
            DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.HUD.shieldUsedMessageDuration) {
                shieldUsedMessage = false
            }
        }
    }

    /// Rolls immediately (gameplay timing/cooldown untouched) then plays a cosmetic
    /// "which skill did I get" reveal over the real result — see `GachaReveal`. The top
    /// shelf hides this roll's actual effect (queue bump or Shield turning on) for the
    /// reveal's whole duration — see `effectiveCount`/`effectiveIsShielded` — so it
    /// doesn't spoil the roulette before it finishes cycling.
    private func performRoll() {
        guard viewModel.canRoll else { return }
        let previousCount = viewModel.heldSkills.count
        let wasShielded = viewModel.isShielded
        viewModel.rollSkill()
        let grew = viewModel.heldSkills.count > previousCount
        let becameShielded = !wasShielded && viewModel.isShielded
        let rolled: SkillType = grew ? viewModel.heldSkills.last! : .shield
        let reveal = GachaReveal(result: rolled, startedAt: Date(), changedState: grew || becameShielded)
        gachaReveal = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.HUD.gachaCycleDuration) {
            guard gachaReveal?.startedAt == reveal.startedAt else { return }
            GameFeedback.shared.play(.rollReveal, haptic: .medium)
        }
    }

    /// Starts the hold timer. If the circle is still down when it fires, this *is* the
    /// activation — no separate release-triggered path, so a long hold doesn't need to
    /// wait for the finger to lift.
    private func handleCirclePress() {
        let startedAt = Date()
        circlePressStartedAt = startedAt
        isHoldingCircle = true
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConfig.Skills.activateHoldDuration) {
            guard circlePressStartedAt == startedAt else { return } // released early, or already fired
            circlePressStartedAt = nil
            isHoldingCircle = false
            guard let skill = viewModel.activateSelectedSkill() else { return }
            onActivate(skill)
            let flourish = SendFlourish(skill: skill, startedAt: Date())
            sendingFlourish = flourish
            DispatchQueue.main.asyncAfter(deadline: .now() + PlaneChoreography.totalDuration) {
                if sendingFlourish?.startedAt == flourish.startedAt { sendingFlourish = nil }
            }
        }
    }

    /// Released before the hold threshold fired (`circlePressStartedAt` still set). A
    /// short release (≤ `tapMaxDuration`) reads as a deliberate tap → advance the
    /// selector. A longer release (between `tapMaxDuration` and `activateHoldDuration`)
    /// was a failed hold attempt, not a tap — does nothing, so a near-miss at activating
    /// doesn't get punished by silently cycling to a different skill. `nil` means the
    /// hold already fired and activated a skill, so there's nothing left to do here.
    private func handleCircleRelease() {
        guard let startedAt = circlePressStartedAt else { return }
        let heldFor = Date().timeIntervalSince(startedAt)
        circlePressStartedAt = nil
        isHoldingCircle = false
        guard heldFor <= GameConfig.Skills.tapMaxDuration else { return }
        let previousSelector = viewModel.selectorType
        viewModel.advanceSelector()
        if viewModel.selectorType != previousSelector {
            GameFeedback.shared.play(.uiSelect, haptic: .selection)
        }
    }

    /// How many of `skill` are actually visible in the top shelf right now — the real
    /// count, minus 1 while a still-playing `gachaReveal` covers this exact skill (so
    /// the roulette doesn't get spoiled by the card bumping before it settles).
    private func effectiveCount(for skill: SkillType) -> Int {
        let real = viewModel.heldSkills.filter { $0 == skill }.count
        if let reveal = gachaReveal, reveal.result == skill, reveal.changedState, skill != .shield {
            return max(0, real - 1)
        }
        return real
    }

    private var effectiveIsShielded: Bool {
        if let reveal = gachaReveal, reveal.result == .shield, reveal.changedState {
            return false
        }
        return viewModel.isShielded
    }

    // MARK: - Mini-screen (D-055/D-058 miniScreenHole)

    /// Its own little LCD (bright green, dark content) — this is the HUD element
    /// players look at most (every Roll/Activate), split into a top "shelf" of 4 fixed
    /// skill-state cards (D-058: replaces the old growing icon queue, which used to
    /// visually spam and squeeze the roll counter) and a bottom status row for
    /// incoming-attack/shield-used messages.
    ///
    /// Plain SwiftUI points, not scaled — `DeviceShellView`'s `hole()` already turns
    /// `ShellLayout.miniScreenHole`'s 62×24 *canvas* units into this container's real
    /// size, so the container itself already scales with the device (D-019: modern
    /// non-SE iPhones share close enough aspect ratios that this varies only a few
    /// percent). Multiplying content sizes by that same `scale` a second time (tried
    /// briefly this session) double-counted it — icon boxes came out ~2.5x too tall,
    /// blowing past the container and clipping to slivers. Every size below is tuned to
    /// actually fit within the real ~152×60pt container, verified live in Simulator.
    private var miniScreenHUD: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 3) {
                topShelf
                Spacer(minLength: 0)
                bottomShelf
            }
            .padding(.horizontal, 5)
            .padding(.top, 5)
            .padding(.bottom, 5) // was 3 (D-059) — user found the bottom row touching the screen edge

            if let reveal = gachaReveal {
                GachaRevealView(reveal: reveal) {
                    withAnimation(.interpolatingSpring(stiffness: 260, damping: 18)) {
                        gachaReveal = nil
                    }
                }
            }

            if let flourish = sendingFlourish {
                sendFlourishOverlay(flourish)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(raceScreenGreen)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// 5 fixed-width elements (die badge + 4 skill cards) packed into a narrow real
    /// width (`ShellLayout.miniScreenHole` is only 62 canvas units wide). Every element
    /// here uses an explicit `.frame`/fixed layout — the one time something didn't
    /// (the roll count `Text`, first cut of D-058), it silently got squeezed to zero
    /// width instead of wrapping or truncating, since it was the row's only flexible
    /// child. Kept deliberately compact for that reason; sizes here aren't casual.
    private var topShelf: some View {
        HStack(alignment: .top, spacing: 3) {
            rollBadge
            ForEach(SkillType.allCases, id: \.self) { skill in
                skillSlotCard(skill)
            }
        }
    }

    /// One of the 4 fixed skill slots. D-059: the fill always stays dark now — D-058's
    /// "active = fill turns green" made the icon itself harder to read at this size (the
    /// user's own complaint), so "active" is a glowing green border instead, keeping the
    /// icon on the same dark backing the gacha-reveal card already proved legible on.
    /// The 3 non-Shield skills also carry a small count badge (top-trailing) when more
    /// than 1 is held; Shield has no count, just on/off.
    ///
    /// D-072/D-073 finding #5: also carries the selector triangle + hold-fill (Shield is
    /// never selectable — it auto-applies on Roll, never enters `heldSkills`).
    private func skillSlotCard(_ skill: SkillType) -> some View {
        let count = effectiveCount(for: skill)
        let isActive = skill == .shield ? effectiveIsShielded : count > 0
        let isSelected = skill != .shield && viewModel.selectorType == skill
        return ZStack(alignment: .topTrailing) {
            Image(skill.iconName)
                .resizable()
                .interpolation(.none)
                .frame(width: 17, height: 17)
                .opacity(isActive ? 1 : 0.45)
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 3).fill(raceScreenDark))
                .overlay(alignment: .bottom) {
                    // Fills upward while Activate is held with this skill selected —
                    // reset to empty the instant the hold ends (fired or released).
                    if isSelected {
                        Rectangle()
                            .fill(raceAccentGreen.opacity(0.55))
                            .frame(height: isHoldingCircle ? 23 : 0)
                            .clipShape(RoundedRectangle(cornerRadius: 3))
                            .animation(.linear(duration: GameConfig.Skills.activateHoldDuration), value: isHoldingCircle)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(raceAccentGreen, lineWidth: isActive ? 2 : 0)
                )
                .shadow(color: isActive ? raceAccentGreen.opacity(0.8) : .clear, radius: 2)
                // Selector triangle: an overlay (not a layout sibling) so it doesn't grow
                // the shelf row's height — pinned flush to the card's bottom edge, tip
                // pointing up into it, per the user's "nempel" request.
                .overlay(alignment: .bottom) {
                    if isSelected {
                        Image(systemName: "arrowtriangle.up.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(raceAccentGreen)
                            .offset(y: 9)
                    }
                }

            if skill != .shield, count > 1 {
                Text("\(count)")
                    .font(.pixel(10))
                    .foregroundStyle(raceScreenGreen)
                    .padding(2)
                    .background(Circle().fill(raceScreenDark))
                    .offset(x: 5, y: -5)
            }
        }
        .fixedSize()
        .animation(.easeOut(duration: 0.2), value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(skill.displayName): \(isActive ? "active" : "inactive")\(count > 1 ? ", ×\(count)" : "")\(isSelected ? ", selected" : "")")
    }

    private var rollBadge: some View {
        HStack(spacing: 2) {
            RollDieIcon(elapsedTime: viewModel.elapsedTime)
                .frame(width: 19, height: 19)
            Text("×\(viewModel.rollCharges)")
                .font(.pixel(10))
                .foregroundStyle(raceScreenDark)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Roll charges: \(viewModel.rollCharges)")
    }

    // MARK: - Bottom shelf (incoming-attack warning / shield-used status)

    private var bottomShelf: some View {
        ZStack {
            if let pending = viewModel.pendingAttack {
                warningBadge(type: pending, countdown: viewModel.pendingAttackCountdown)
            } else if shieldUsedMessage {
                Text("SHIELD USED")
                    .font(.pixel(10))
                    .foregroundStyle(raceScreenDark)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(raceScreenDark.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: shieldUsedMessage)
        .frame(maxWidth: .infinity)
        .frame(height: 25) // was a mismatched 26/30 split between this and warningBadge — unified
    }

    /// D-060: the plane flies in from off-screen left, holds at center, "drops" the
    /// warning icon into place (a real fall-and-settle, not a fade), then accelerates
    /// off toward the right — mirrors `sendFlourishOverlay`'s choreography so both
    /// directions read as the same visual language.
    private func warningBadge(type: SkillType, countdown: Double) -> some View {
        GeometryReader { geo in
            let centerX = geo.size.width / 2
            let enterX: CGFloat = -30
            let exitX = geo.size.width + 30
            let planeDrop: CGFloat = 4 // user: "pesawatnya bisa diturunin dikit"

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                let blinkPhase = Int(context.date.timeIntervalSinceReferenceDate / GameConfig.HUD.warningBlinkInterval) % 2 == 0
                let elapsed = incomingPlane.map { context.date.timeIntervalSince($0.startedAt) }
                // No active plane (shouldn't happen while `pendingAttack` is set, but a
                // stale render right at the boundary shouldn't hide the warning) reads
                // as "already delivered".
                let transfer = elapsed.map { PlaneChoreography.transferProgress($0) } ?? 1

                ZStack {
                    HStack(spacing: 4) {
                        Image("warning_icon")
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 20, height: 20)
                            .opacity(blinkPhase ? 1 : 0.35)
                        Text("\(Int(countdown.rounded(.up)))")
                            .font(.pixel(11))
                            .foregroundStyle(raceScreenDark)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(raceScreenDark.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .opacity(transfer)
                    .offset(y: (1 - transfer) * -10) // falls into place from above

                    if let elapsed, elapsed < PlaneChoreography.totalDuration {
                        PlaneIcon(elapsedTime: viewModel.elapsedTime)
                            .frame(width: 32, height: 12)
                            .padding(4)
                            .background(RoundedRectangle(cornerRadius: 3).fill(raceScreenDark))
                            .offset(
                                x: PlaneChoreography.planeX(elapsed: elapsed, enterX: enterX, stopX: centerX, exitX: exitX) - centerX,
                                y: planeDrop
                            )
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(type.displayName) attack incoming in \(Int(countdown.rounded(.up))) seconds")
            }
        }
        .frame(height: 25)
    }

    /// D-058 point 4 / D-060: the send animation originates from the actual skill card's
    /// shelf position (roll + 4 fixed cards = 5 equal-width slots, so the x-offset per
    /// skill is just its index — no need for full geometry/anchor tracking). The plane
    /// flies in from off-screen left, holds under the card, the icon drops down into it
    /// (real motion, not a fade), then the plane accelerates off toward the right.
    private func sendFlourishOverlay(_ flourish: SendFlourish) -> some View {
        GeometryReader { geo in
            let slotCount = 5.0 // roll badge + 4 skill cards, all roughly equal width
            let skillIndex = Double(SkillType.allCases.firstIndex(of: flourish.skill) ?? 0)
            let stopX = geo.size.width * (1.0 + skillIndex + 0.5) / slotCount
            let enterX: CGFloat = -30
            let exitX = geo.size.width + 30
            let shelfY: CGFloat = 17
            let dropDistance: CGFloat = 12

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                let elapsed = context.date.timeIntervalSince(flourish.startedAt)
                let transfer = PlaneChoreography.transferProgress(elapsed)
                let planeX = PlaneChoreography.planeX(elapsed: elapsed, enterX: enterX, stopX: stopX, exitX: exitX)

                ZStack {
                    if transfer < 1 {
                        Image(flourish.skill.iconName)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 16, height: 16)
                            .opacity(1 - transfer)
                            .position(x: stopX, y: shelfY + transfer * dropDistance)
                    }

                    PlaneIcon(elapsedTime: viewModel.elapsedTime)
                        .frame(width: 32, height: 12)
                        .padding(4)
                        // D-059: dark chip — `plane_icon` is itself green-toned, so it
                        // had almost no contrast sitting directly on the mini-screen.
                        .background(RoundedRectangle(cornerRadius: 3).fill(raceScreenDark))
                        .position(x: planeX, y: shelfY + dropDistance)
                }
            }
        }
    }
}

/// D-060: the shared 4-beat timing (fly in → pause → transfer cargo → fly out) behind
/// both the send flourish and the incoming-attack plane — only the actual on-screen x
/// coordinates differ between the two (send targets a specific shelf slot; receive just
/// enters/exits center), so that math lives at each call site while the timing lives
/// here once instead of being duplicated.
private enum PlaneChoreography {
    private static let flyInEnd = GameConfig.HUD.planeFlyInDuration
    private static let pauseEnd = flyInEnd + GameConfig.HUD.planePauseDuration
    private static let transferEnd = pauseEnd + GameConfig.HUD.planeTransferDuration
    static let totalDuration = transferEnd + GameConfig.HUD.planeFlyOutDuration

    /// 0 before the cargo transfer starts, 1 once it's finished settling — drives both
    /// "drops in" (send: cargo fades out as this rises to 1) and "drops out" (receive:
    /// cargo fades in as this rises to 1), since both are just this same progress read
    /// in whichever sense the caller needs.
    static func transferProgress(_ elapsed: Double) -> Double {
        if elapsed < pauseEnd { return 0 }
        if elapsed >= transferEnd { return 1 }
        return (elapsed - pauseEnd) / (transferEnd - pauseEnd)
    }

    /// The plane's own x, interpolated across 3 fixed points: `enterX` (off-screen at
    /// the start), `stopX` (held through the transfer), `exitX` (off-screen at the end).
    /// Fly-out eases in (accelerates) for a "gas tancap" departure instead of a flat
    /// constant-speed exit.
    static func planeX(elapsed: Double, enterX: CGFloat, stopX: CGFloat, exitX: CGFloat) -> CGFloat {
        if elapsed < flyInEnd {
            let t = elapsed / flyInEnd
            return enterX + (stopX - enterX) * t
        }
        if elapsed < transferEnd {
            return stopX
        }
        let t = min(1, (elapsed - transferEnd) / (totalDuration - transferEnd))
        return stopX + (exitX - stopX) * (t * t)
    }
}

private struct SendFlourish {
    let skill: SkillType
    let startedAt: Date
}

private struct IncomingPlane {
    let startedAt: Date
}

/// One cosmetic Roll reveal: rapid-cycles the 4 skill icons, decelerating, then locks
/// onto the real `result` with a scale flourish. Purely a view-layer flourish — the
/// actual roll (`RaceViewModel.rollSkill`) already happened by the time this starts.
private struct GachaReveal: Equatable {
    let result: SkillType
    let startedAt: Date
    /// True when this roll actually changed `result`'s held state (queue grew, or
    /// Shield newly turned on) — false for a wasted Shield re-roll, where nothing
    /// changed and there's nothing to hide. `RaceView.effectiveCount`/
    /// `effectiveIsShielded` use this to keep the top shelf's reveal from spoiling the
    /// roulette still cycling on top of it.
    let changedState: Bool
}

private struct GachaRevealView: View {
    let reveal: GachaReveal
    let onFinished: () -> Void

    private static let cycleIcons = SkillType.allCases

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
            let elapsed = context.date.timeIntervalSince(reveal.startedAt)
            let cycleDuration = GameConfig.HUD.gachaCycleDuration
            let totalDuration = cycleDuration + GameConfig.HUD.gachaLockHoldDuration

            if elapsed >= cycleDuration {
                Image(reveal.result.iconName)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 26, height: 26)
                    .scaleEffect(lockScale(elapsedSinceLock: elapsed - cycleDuration))
                    .accessibilityLabel("Got skill \(reveal.result.displayName)")
                    .onChange(of: elapsed >= totalDuration) { _, done in
                        if done { onFinished() }
                    }
            } else {
                // Decelerating cycle: starts fast (~60ms/frame), slows toward cycleDuration.
                let progress = elapsed / cycleDuration
                let cycleCount = 10.0
                let eased = 1 - pow(1 - progress, 2)
                let index = Int(eased * cycleCount) % Self.cycleIcons.count
                Image(Self.cycleIcons[index].iconName)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 26, height: 26)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(raceScreenDark)
        )
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    /// Quick overshoot-then-settle pop right as the result locks in.
    private func lockScale(elapsedSinceLock: Double) -> CGFloat {
        let t = min(1, elapsedSinceLock / 0.25)
        guard t < 1 else { return 1 }
        return 1 + 0.4 * sin(t * .pi)
    }
}

/// 4-frame die-face spin, reused verbatim from `MazeView`'s in-maze pickup animation so
/// the mini-screen badge and the world-space item stay visually identical.
private struct RollDieIcon: View {
    let elapsedTime: Double

    private static let frames: [UIImage] = {
        let sheet = UIImage(named: "roll_item") ?? UIImage()
        return (0..<4).map { sheet.croppedCell(col: $0, row: 0, cellSize: 16) }
    }()

    var body: some View {
        let frame = Int(elapsedTime / GameConfig.Camera.itemFrameDuration) % Self.frames.count
        Image(uiImage: Self.frames[frame])
            .resizable()
            .interpolation(.none)
    }
}

/// 2-frame flap cycle from `plane_icon` (32x12, two 16x12 poses side by side) — the
/// D-055 send/receive flourish.
private struct PlaneIcon: View {
    let elapsedTime: Double

    private static let frames: [UIImage] = {
        let sheet = UIImage(named: "plane_icon") ?? UIImage()
        return (0..<2).map { sheet.croppedCell(col: $0, row: 0, width: 16, height: 12) }
    }()

    var body: some View {
        let frame = Int(elapsedTime / GameConfig.HUD.planeFrameDuration) % Self.frames.count
        Image(uiImage: Self.frames[frame])
            .resizable()
            .interpolation(.none)
    }
}

#Preview {
    RaceView()
}
