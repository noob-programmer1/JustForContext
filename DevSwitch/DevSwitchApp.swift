import SwiftUI

@main
struct DevSwitchApp: App {
    @State private var workspaceList: WorkspaceListViewModel

    init() {
        let vm = WorkspaceListViewModel()
        vm.start()
        _workspaceList = State(initialValue: vm)
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(viewModel: workspaceList)
        } label: {
            MenuBarLabel(viewModel: workspaceList)
        }
        .menuBarExtraStyle(.window)

        Window("JustForContext", id: "main") {
            MainWindow(viewModel: workspaceList)
        }
        .defaultSize(width: 900, height: 640)

        // Save Context is now shown inline as a sheet in the popover
    }
}
