import OstraconCore
import SwiftUI

struct ColorSwatchGrid: View {
    @Binding var selection: ProjectColor

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 10), spacing: 8) {
            ForEach(ProjectColor.allCases) { color in
                Button {
                    selection = color
                } label: {
                    Circle()
                        .fill(Theme.color(for: color))
                        .frame(width: 20, height: 20)
                        .padding(3)
                        .overlay {
                            if selection == color {
                                Circle().strokeBorder(Theme.color(for: color), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.displayName)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(selection == color ? .isSelected : [])
            }
        }
    }
}
