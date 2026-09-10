import SwiftUI

@main
struct SwiftDependencyGraphExplorerApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 980, minHeight: 640)
        }
        .defaultSize(width: 1280, height: 780)
    }
}
