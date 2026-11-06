import SwiftUI

/// The look, shared with EyeCue: charcoal ground, sand and mauve accents, Avenir Next
/// with light headings and regular section titles.
enum Theme {
    static let ground = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let panel = Color(red: 0.078, green: 0.086, blue: 0.098)
    static let raised = Color(red: 0.118, green: 0.129, blue: 0.145)
    static let line = Color.white.opacity(0.08)
    static let paper = Color(red: 0.949, green: 0.933, blue: 0.914)
    static let quiet = Color(red: 0.635, green: 0.663, blue: 0.682)
    static let sand = Color(red: 0.863, green: 0.761, blue: 0.698)
    static let mauve = Color(red: 0.690, green: 0.553, blue: 0.533)
    static let live = Color(red: 0.42, green: 0.80, blue: 0.55)
    static let warn = Color(red: 0.93, green: 0.70, blue: 0.36)
    static let danger = Color(red: 0.90, green: 0.45, blue: 0.42)

    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .ultraLight, .thin, .light: name = "AvenirNext-UltraLight"
        case .medium: name = "AvenirNext-Medium"
        case .semibold: name = "AvenirNext-DemiBold"
        case .bold, .heavy, .black: name = "AvenirNext-Bold"
        default: name = "AvenirNext-Regular"
        }
        return .custom(name, size: size)
    }

    /// Large headings: Avenir Next at its lightest.
    static func heading(_ size: CGFloat) -> Font { .custom("AvenirNext-UltraLight", size: size) }

    /// Small caps labels in mauve, like EyeCue's section labels.
    static let label = Font.custom("AvenirNext-DemiBold", size: 10.5)
}

/// A pill button in sand, the main action on a screen.
struct PillButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(13, .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .foregroundColor(prominent ? Theme.ground : Theme.paper)
            .background(Capsule().fill(prominent ? Theme.sand : Theme.raised))
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.label)
            .tracking(2.4)
            .foregroundColor(Theme.mauve)
    }
}
