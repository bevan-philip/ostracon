import OstraconCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            TaskListView()
        }
        .tint(Theme.accent)
        .sheet(item: $model.projectDraft) { draft in
            ProjectEditorSheet(draft: draft)
        }
        .alert("Something went wrong", isPresented: $model.isShowingError) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
