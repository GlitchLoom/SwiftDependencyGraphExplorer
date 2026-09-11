import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppViewModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if model.selectedFolderURL == nil {
                ProjectPickerView(onChooseProject: model.chooseProject)
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    FileSidebarView(model: model)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
                } content: {
                    OptionsPanelView(model: model)
                        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
                } detail: {
                    GraphWorkspaceView(model: model)
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .toolbar {
            if model.selectedFolderURL != nil {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: { Task { await model.navigateBack() } }) {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!model.canNavigateBack)
                    .help("Go back to the previous graph")

                    Button(action: { Task { await model.navigateForward() } }) {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!model.canNavigateForward)
                    .help("Go forward to the next graph")

                    Button(action: model.chooseProject) {
                        Label("Choose Project", systemImage: "folder")
                    }
                    .help("Choose a different project folder")
                }
            }
        }
    }
}
