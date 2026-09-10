import SwiftUI

struct ProjectPickerView: View {
    let onChooseProject: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text("Swift Dependency Graph Explorer")
                    .font(.title2.weight(.semibold))
                Text("Choose a project folder to index its Swift source files.")
                    .foregroundStyle(.secondary)
            }

            Button(action: onChooseProject) {
                Label("Choose Project Folder", systemImage: "folder.badge.plus")
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
