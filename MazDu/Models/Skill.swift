/// The 4-skill pool players Roll from. Effects (Darken's circle-vision, Freeze, Switch's
/// position swap, Shield's reactive block) are wired up separately — this type is just the
/// shared vocabulary between the Roll/Activate queue, the network protocol, and the UI.
enum SkillType: Codable, CaseIterable, Equatable {
    case darken
    case freeze
    case switchPlace
    case shield

    /// D-055 mini-screen queue + gacha reveal icon — matches this codebase's
    /// `Assets.xcassets/<name>.imageset` convention (see `roll_item`, `obstacle_tree`).
    var iconName: String {
        switch self {
        case .darken: return "skill_darken_icon"
        case .freeze: return "skill_freeze_icon"
        case .switchPlace: return "skill_switch_icon"
        case .shield: return "skill_shield_icon"
        }
    }

    var displayName: String {
        switch self {
        case .darken: return "Darken"
        case .freeze: return "Freeze"
        case .switchPlace: return "Switch"
        case .shield: return "Shield"
        }
    }
}
