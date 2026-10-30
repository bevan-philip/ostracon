import SwiftUI

struct ToastView: View {
    @Environment(AppModel.self) private var model

    let toast: Toast

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.message)
            if toast.undo != nil {
                Button("Undo", action: undo)
                    .controlSize(.small)
                    .keyboardShortcut("z")
            }
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .buttonStyle(IconButtonStyle(size: 20))
                .foregroundStyle(.secondary)
        }
        .padding(.leading)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .glassSurface(in: .capsule)
        .task(id: toast.id) {
            try? await Task.sleep(for: .seconds(5))
            model.dismissToast(toast)
        }
    }

    private func undo() {
        model.performUndo(for: toast)
    }

    private func dismiss() {
        model.dismissToast(toast)
    }
}
