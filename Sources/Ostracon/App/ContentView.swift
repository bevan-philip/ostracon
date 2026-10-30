import OstraconCore
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 360)
        } detail: {
            TaskListView()
        }
        .sheet(item: $model.projectDraft, content: ProjectEditorSheet.init)
        .alert("Something Went Wrong", item: $model.errorMessage) { _ in
        } message: { message in
            Text(message)
        }
        .task {
            // `PRAGMA data_version` is a cheap read, so polling keeps up with the MCP server without a file watcher.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                model.reloadIfChangedElsewhere()
            }
        }
    }
}
