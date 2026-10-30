import Foundation

/// The Todoist project colour palette.
public enum ProjectColor: String, CaseIterable, Identifiable, Sendable {
    case berryRed, red, orange, yellow, oliveGreen, limeGreen, green, mintGreen, teal
    case skyBlue, lightBlue, blue, grape, violet, lavender, magenta, salmon, charcoal, grey, taupe

    public var id: String { rawValue }

    /// The colour as a 24-bit RGB value.
    public var hex: UInt32 {
        switch self {
        case .berryRed: 0xB8255F
        case .red: 0xDC4C3E
        case .orange: 0xC77100
        case .yellow: 0xB29104
        case .oliveGreen: 0x949C31
        case .limeGreen: 0x65A33A
        case .green: 0x369307
        case .mintGreen: 0x42A393
        case .teal: 0x148FAD
        case .skyBlue: 0x319DC0
        case .lightBlue: 0x6988A4
        case .blue: 0x4180FF
        case .grape: 0x692EC2
        case .violet: 0xCA3FEE
        case .lavender: 0xA4698C
        case .magenta: 0xE05095
        case .salmon: 0xC9766F
        case .charcoal: 0x808080
        case .grey: 0x999999
        case .taupe: 0x8F7A69
        }
    }

    public var displayName: String {
        switch self {
        case .berryRed: "Berry Red"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .oliveGreen: "Olive Green"
        case .limeGreen: "Lime Green"
        case .green: "Green"
        case .mintGreen: "Mint Green"
        case .teal: "Teal"
        case .skyBlue: "Sky Blue"
        case .lightBlue: "Light Blue"
        case .blue: "Blue"
        case .grape: "Grape"
        case .violet: "Violet"
        case .lavender: "Lavender"
        case .magenta: "Magenta"
        case .salmon: "Salmon"
        case .charcoal: "Charcoal"
        case .grey: "Grey"
        case .taupe: "Taupe"
        }
    }
}
