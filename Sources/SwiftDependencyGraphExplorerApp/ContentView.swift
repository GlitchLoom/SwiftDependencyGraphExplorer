import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        Group {
            if model.selectedFolderURL == nil {
                ProjectPickerView(onChooseProject: model.chooseProject)
            } else {
                HSplitView {
                    FileSidebarView(model: model)
                        .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

                    OptionsPanelView(model: model)
                        .frame(minWidth: 250, idealWidth: 280, maxWidth: 340)

                    GraphWorkspaceView(model: model)
                        .frame(minWidth: 480)
                }
            }
        }
        .toolbar {
            if model.selectedFolderURL != nil {
                ToolbarItem(placement: .navigation) {
                    Button(action: model.chooseProject) {
                        Label("Choose Project", systemImage: "folder")
                    }
                    .help("Choose a different project folder")
                }
            }
        }
    }
}
