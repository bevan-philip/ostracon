import OstraconCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isChoosingFolder = false
    @State private var isChoosingBackup = false
    @State private var backupToRestore: URL?

    var body: some View {
        Form {
            Section {
                LabeledContent("Database") {
                    if let url = model.databaseURL {
                        PathText(url: url)
                    } else {
                        Text("Not saved")
                    }
                }
                if let url = model.databaseURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
            } footer: {
                Text("Your tasks stay on this Mac, where Ostracon, ostracon-cli and the MCP server can all change them safely.")
                    .foregroundStyle(.secondary)
            }

            Section {
                if let folder = model.backupFolder {
                    LabeledContent("Back up to") {
                        PathText(url: folder.url)
                    }
                    LabeledContent("Last backup") {
                        if let date = model.lastBackupDate {
                            Text(date, format: .dateTime.day().month().hour().minute())
                        } else {
                            Text("Never")
                        }
                    }
                    if let error = model.backupError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Back Up Now") { model.backUpNow() }
                        Button("Change Folder…") { isChoosingFolder = true }
                        Spacer()
                        Button("Turn Off") { model.setBackupFolder(nil) }
                    }
                } else {
                    Button("Choose Folder…") { isChoosingFolder = true }
                }
                Button("Restore from Backup…") { isChoosingBackup = true }
                    .fileImporter(isPresented: $isChoosingBackup, allowedContentTypes: [Self.databaseType]) { result in
                        if case .success(let backup) = result {
                            backupToRestore = backup
                        }
                    }
                    .fileDialogDefaultDirectory(model.backupFolder?.url)
            } header: {
                Text("Backups")
            } footer: {
                Text("""
                    A minute after your tasks change, Ostracon saves a copy in this folder, keeping one a day for the \
                    last two days. Choose a folder in OneDrive or iCloud Drive to keep copies off this Mac. Changes made with \
                    ostracon-cli or the MCP server are backed up the next time Ostracon is open.
                    """)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let folder) = result {
                model.setBackupFolder(folder)
            }
        }
        .confirmationDialog(
            "Replace all your tasks with this backup?",
            isPresented: Binding(get: { backupToRestore != nil }, set: { if !$0 { backupToRestore = nil } }),
            presenting: backupToRestore
        ) { backup in
            Button("Replace Tasks", role: .destructive) { model.restore(from: backup) }
        } message: { backup in
            Text("Your tasks will be replaced with those in “\(backup.lastPathComponent)”. Your current tasks are saved first as a backup named “Ostracon before restore”, so you can restore them again.")
        }
    }

    private static let databaseType = UTType(filenameExtension: "sqlite", conformingTo: .data) ?? .data
}

/// A file path with the home folder shortened to ~, cut in the middle when it doesn't fit.
private struct PathText: View {
    let url: URL

    var body: some View {
        Text((url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(url.path(percentEncoded: false))
    }
}
