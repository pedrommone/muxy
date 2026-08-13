import SwiftUI

struct ExtensionHomeSurfaceView: View {
    let state: ExtensionHomeState

    @Environment(AppState.self) private var appState
    @Environment(ProjectStore.self) private var projectStore
    @Environment(WorktreeStore.self) private var worktreeStore
    @Environment(ProjectGroupStore.self) private var projectGroupStore

    var body: some View {
        if let binding = ExtensionStore.shared.homeView(
            extensionID: state.extensionID,
            homeViewID: state.homeViewID
        ), let entryURL = ExtensionWebView.entryURL(
            for: binding.muxyExtension,
            entry: binding.homeView.entry
        ) {
            ExtensionWebView(
                extensionID: state.extensionID,
                instanceID: state.id.uuidString,
                surfaceKind: .home,
                entryURL: entryURL,
                initialData: state.data,
                appState: appState,
                projectStore: projectStore,
                worktreeStore: worktreeStore,
                projectGroupStore: projectGroupStore,
                focused: true,
                surfaceStore: state.surfaceStore
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
                .onAppear { appState.dismissExtensionHome(instanceID: state.id.uuidString) }
        }
    }
}
