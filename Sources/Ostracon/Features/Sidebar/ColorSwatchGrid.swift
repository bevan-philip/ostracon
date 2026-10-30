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
                        .frame(width: 22, height: 22)
                        .overlay {
                            // A tick as well as the ring, so the choice doesn't rely on colour alone.
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .opacity(selection == color ? 1 : 0)
                        }
                        .padding(2)
                        .overlay {
                            Circle()
                                .strokeBorder(Theme.color(for: color), lineWidth: 2)
                                .opacity(selection == color ? 1 : 0)
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
