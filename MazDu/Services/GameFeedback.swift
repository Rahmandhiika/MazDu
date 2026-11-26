import AVFoundation
import UIKit

/// Owns every runtime sound and haptic. Gameplay emits events; this type owns playback,
/// fades, and the one deliberate music duck so screens never need audio plumbing.
@MainActor
final class GameFeedback {
    static let shared = GameFeedback()

    enum Music: String {
        case menu = "bgm_menu_game_boi_2"
        case race = "bgm_race_itty_bitty_8_bit"

        var volume: Float { self == .menu ? 0.24 : 0.28 }
        var fadeIn: TimeInterval { self == .menu ? 0.25 : 0.04 }
        var loops: Int { self == .menu ? -1 : 0 }
    }

    enum Effect: String, CaseIterable {
        case uiSelect = "sfx_ui_select"
        case countdownTick = "sfx_countdown_tick"
        case countdownGo = "sfx_countdown_go"
        case dicePickup = "sfx_dice_pickup"
        case rollReveal = "sfx_roll_reveal"
        case attackCast = "sfx_attack_cast"
        case attackWarning = "sfx_attack_warning"
        case freezeHit = "sfx_freeze_hit"
        case darkenImpact = "sfx_darken_impact"
        case switchResolve = "sfx_switch_resolve"
        case shieldBlock = "sfx_shield_block"
        case obstacleHit = "sfx_obstacle_hit"
        case resultWin = "sfx_result_win"
        case resultLoss = "sfx_result_loss"

        var volume: Float {
            switch self {
            case .obstacleHit, .freezeHit: 0.8
            case .darkenImpact, .switchResolve: 0.72
            default: 0.68
            }
        }
    }

    enum Haptic {
        case selection, light, medium, heavy
        case success, warning, error
        case none
    }

    private var music: Music?
    private var musicPlayer: AVAudioPlayer?
    private var effectPlayers: [Effect: AVAudioPlayer] = [:]
    private var isApplicationActive = true

    private init() {}

    /// Locking the phone moves SwiftUI through `.inactive` before `.background`; stop
    /// immediately at either point so no menu loop survives the app handoff.
    func setApplicationIsActive(_ isActive: Bool) {
        guard isApplicationActive != isActive else { return }
        isApplicationActive = isActive
        guard !isActive else { return }

        musicPlayer?.stop()
        musicPlayer = nil
        music = nil
        effectPlayers.values.forEach { $0.stop() }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func playMusic(_ next: Music?) {
        guard isApplicationActive else { return }
        guard music != next else { return }

        let outgoing = musicPlayer
        music = next

        if let outgoing {
            outgoing.setVolume(0, fadeDuration: 0.35)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak outgoing] in
                outgoing?.stop()
                guard self?.musicPlayer === outgoing else { return }
                self?.musicPlayer = nil
            }
        }

        guard let next, let player = makePlayer(named: next.rawValue) else { return }
        player.numberOfLoops = next.loops
        player.volume = 0
        player.prepareToPlay()
        player.play()
        player.setVolume(next.volume, fadeDuration: next.fadeIn)
        musicPlayer = player
    }

    /// Darken needs a short, noticeable gap in the race mix without stopping transport.
    func duckRaceMusic() {
        guard music == .race, let player = musicPlayer else { return }
        player.setVolume(0.1, fadeDuration: 0.04)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self, weak player] in
            guard self?.music == .race, self?.musicPlayer === player else { return }
            player?.setVolume(Music.race.volume, fadeDuration: 0.25)
        }
    }

    func play(_ effect: Effect, haptic: Haptic = .none) {
        guard isApplicationActive else { return }
        perform(haptic)
        let player = effectPlayers[effect] ?? makePlayer(named: effect.rawValue)
        guard let player else { return }
        effectPlayers[effect] = player
        player.stop()
        player.currentTime = 0
        player.volume = effect.volume
        player.prepareToPlay()
        player.play()
    }

    func perform(_ haptic: Haptic) {
        switch haptic {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case .light:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .medium:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .heavy:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .none:
            break
        }
    }

    private func makePlayer(named resource: String) -> AVAudioPlayer? {
        configureAudioSession()
        let url = Bundle.main.url(forResource: resource, withExtension: "wav")
            ?? Bundle.main.url(forResource: resource, withExtension: "wav", subdirectory: "Resources/Audio/processed")
        guard let url else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }
}
