import SwiftUI

struct ToastView: View {
    @Environment(AppModel.self) private var model

    let toast: Toast

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.message)
            if toast.undo != nil {
                Button("Undo") { model.performUndo(for: toast) }
                    .buttonStyle(.plain)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color(hex: 0xFF7066))
                    .keyboardShortcut("z")
            }
            Button("Dismiss", systemImage: "xmark") { model.dismissToast(toast) }
                .buttonStyle(IconButtonStyle(size: 20))
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(hex: 0x202020), in: .rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(5))
            model.dismissToast(toast)
        }
    }
}
