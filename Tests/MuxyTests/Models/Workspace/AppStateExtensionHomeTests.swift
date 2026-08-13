import Foundation
import Testing

@testable import Muxy

@Suite("AppState extension home", .serialized)
@MainActor
struct AppStateExtensionHomeTests {
    @Test("presenting home preserves workspace and workspace actions dismiss it")
    func presentationPreservesWorkspace() throws {
        let appState = makeAppState()
        let projectID = UUID()
        let worktreeID = UUID()
        appState.dispatch(.selectWorktree(
            projectID: projectID,
            worktreeID: worktreeID,
            worktreePath: "/tmp/project"
        ))
        appState.dispatch(.createTab(projectID: projectID, areaID: nil))
        let root = try #require(appState.workspaceRoots[WorktreeKey(
            projectID: projectID,
            worktreeID: worktreeID
        )])
        let tabID = try #require(root.allAreas().first?.activeTabID)
        let home = ExtensionHomeView(
            id: "overview",
            title: "Overview",
            icon: nil,
            entry: "index.html",
            defaultData: nil
        )

        appState.presentExtensionHome(extensionID: "demo", homeView: home)

        #expect(appState.activeExtensionHome?.homeViewID == "overview")
        #expect(appState.activeProjectID == projectID)
        #expect(appState.activeWorktreeID[projectID] == worktreeID)
        #expect(root.allAreas().first?.activeTabID == tabID)

        appState.dispatch(.selectTab(
            projectID: projectID,
            areaID: try #require(root.allAreas().first?.id),
            tabID: tabID
        ))

        #expect(appState.activeExtensionHome == nil)
        #expect(root.allAreas().first?.activeTabID == tabID)
    }

    @Test("pane navigation leaves home and focuses its owning workspace")
    func paneNavigationFocusesOwningWorkspace() throws {
        let appState = makeAppState()
        let firstProjectID = UUID()
        let firstWorktreeID = UUID()
        let secondProjectID = UUID()
        let secondWorktreeID = UUID()
        appState.dispatch(.selectWorktree(
            projectID: firstProjectID,
            worktreeID: firstWorktreeID,
            worktreePath: "/tmp/first"
        ))
        appState.dispatch(.createTab(projectID: firstProjectID, areaID: nil))
        let firstPane = try #require(MuxyAPI.Panes.list(appState: appState).first)
        appState.dispatch(.selectWorktree(
            projectID: secondProjectID,
            worktreeID: secondWorktreeID,
            worktreePath: "/tmp/second"
        ))
        appState.dispatch(.createTab(projectID: secondProjectID, areaID: nil))
        appState.presentExtensionHome(
            extensionID: "demo",
            homeView: ExtensionHomeView(
                id: "overview",
                title: "Overview",
                icon: nil,
                entry: "index.html",
                defaultData: nil
            )
        )

        let result = MuxyAPI.Navigation.focus(
            paneIDString: firstPane.id.uuidString,
            appState: appState
        )

        #expect({
            if case .success = result { return true }
            return false
        }())
        #expect(appState.activeExtensionHome == nil)
        #expect(appState.activeProjectID == firstProjectID)
        #expect(appState.activeWorktreeID[firstProjectID] == firstWorktreeID)
        #expect(NotificationNavigator.activePaneID(appState: appState) == firstPane.id)
        #expect(firstPane.projectID == firstProjectID)
        #expect(firstPane.worktreeID == firstWorktreeID)
    }

    @Test("explicit close honors a lifecycle veto")
    func explicitCloseHonorsLifecycleVeto() async throws {
        let appState = makeAppState()
        appState.presentExtensionHome(
            extensionID: "demo",
            homeView: ExtensionHomeView(
                id: "overview",
                title: "Overview",
                icon: nil,
                entry: "index.html",
                defaultData: nil
            )
        )
        let activeHome = try #require(appState.activeExtensionHome)
        let surfaceKey = LifecycleSurfaceKey(kind: .home, instanceID: activeHome.id.uuidString)
        let bridge = ExtensionHomeBeforeCloseStub(verdict: .prevent)
        ExtensionSurfaceBridgeRegistry.shared.register(bridge, for: surfaceKey)
        defer { ExtensionSurfaceBridgeRegistry.shared.unregister(surfaceKey) }

        appState.requestDismissExtensionHome()
        for _ in 0 ..< 50 { await Task.yield() }

        #expect(appState.activeExtensionHome?.id == activeHome.id)
        #expect(bridge.askCount == 1)
    }

    @Test("forward navigation honors a lifecycle veto")
    func forwardNavigationHonorsLifecycleVeto() async throws {
        let appState = makeAppState()
        let firstProjectID = UUID()
        let firstWorktreeID = UUID()
        appState.dispatch(.selectWorktree(
            projectID: firstProjectID,
            worktreeID: firstWorktreeID,
            worktreePath: "/tmp/first"
        ))
        appState.dispatch(.createTab(projectID: firstProjectID, areaID: nil))
        let firstArea = try #require(appState.workspaceRoots[WorktreeKey(
            projectID: firstProjectID,
            worktreeID: firstWorktreeID
        )]?.allAreas().first)

        let secondProjectID = UUID()
        let secondWorktreeID = UUID()
        appState.dispatch(.selectWorktree(
            projectID: secondProjectID,
            worktreeID: secondWorktreeID,
            worktreePath: "/tmp/second"
        ))
        appState.dispatch(.createTab(projectID: secondProjectID, areaID: nil))
        let secondArea = try #require(appState.workspaceRoots[WorktreeKey(
            projectID: secondProjectID,
            worktreeID: secondWorktreeID
        )]?.allAreas().first)

        appState.navigation.removeEntries { _ in true }
        appState.navigation.record(NavigationEntry(
            projectID: firstProjectID,
            worktreeID: firstWorktreeID,
            areaID: firstArea.id,
            tabID: firstArea.activeTabID
        ))
        appState.navigation.record(NavigationEntry(
            projectID: secondProjectID,
            worktreeID: secondWorktreeID,
            areaID: secondArea.id,
            tabID: secondArea.activeTabID
        ))
        appState.navigation.setCursor(0)
        appState.presentExtensionHome(
            extensionID: "demo",
            homeView: ExtensionHomeView(
                id: "overview",
                title: "Overview",
                icon: nil,
                entry: "index.html",
                defaultData: nil
            )
        )
        let activeHome = try #require(appState.activeExtensionHome)
        let surfaceKey = LifecycleSurfaceKey(kind: .home, instanceID: activeHome.id.uuidString)
        let bridge = ExtensionHomeBeforeCloseStub(verdict: .prevent)
        ExtensionSurfaceBridgeRegistry.shared.register(bridge, for: surfaceKey)
        defer { ExtensionSurfaceBridgeRegistry.shared.unregister(surfaceKey) }

        appState.goForward()
        for _ in 0 ..< 50 { await Task.yield() }

        #expect(appState.activeExtensionHome?.id == activeHome.id)
        #expect(appState.navigation.cursor == 0)
        #expect(bridge.askCount == 1)
    }

    private func makeAppState() -> AppState {
        AppState(
            selectionStore: ExtensionHomeSelectionStoreStub(),
            terminalViews: ExtensionHomeTerminalViewRemovingStub(),
            workspacePersistence: ExtensionHomeWorkspacePersistenceStub()
        )
    }
}

@MainActor
private final class ExtensionHomeBeforeCloseStub: BeforeCloseAsking {
    let verdict: LifecycleVerdict
    private(set) var askCount = 0

    init(verdict: LifecycleVerdict) {
        self.verdict = verdict
    }

    func requestBeforeClose(reason _: LifecycleSurfaceKind, instanceID _: String) async -> LifecycleVerdict {
        askCount += 1
        return verdict
    }

    func failPendingLifecycle() {}
}

private final class ExtensionHomeWorkspacePersistenceStub: WorkspacePersisting {
    func loadWorkspaces() throws -> [WorkspaceSnapshot] { [] }
    func saveWorkspaces(_: [WorkspaceSnapshot]) throws {}
}

@MainActor
private final class ExtensionHomeSelectionStoreStub: ActiveProjectSelectionStoring {
    func loadActiveProjectID() -> UUID? { nil }
    func saveActiveProjectID(_: UUID?) {}
    func loadActiveWorktreeIDs() -> [UUID: UUID] { [:] }
    func saveActiveWorktreeIDs(_: [UUID: UUID]) {}
}

@MainActor
private final class ExtensionHomeTerminalViewRemovingStub: TerminalViewRemoving {
    func removeView(for _: UUID) {}
    func needsConfirmQuit(for _: UUID) -> Bool { false }
}
