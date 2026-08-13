import Foundation
import Testing

@testable import Muxy

@Suite("MuxyAPI project management permissions")
struct MuxyAPIProjectManagementPermissionTests {
    @Test("management verbs require projects:write", arguments: [
        "projects.add",
        "projects.rename",
        "projects.setColor",
        "projects.setIcon",
        "projects.setLogo",
        "projects.reorder",
    ])
    func managementVerbsRequireProjectsWrite(verb: String) {
        #expect(MuxyAPI.Permissions.required(for: verb) == .projectsWrite)
        #expect(MuxyAPI.Permissions.verbNames.contains(verb))
    }

    @Test("projects.changed event requires projects:read")
    func changedEventRequiresProjectsRead() {
        #expect(MuxyAPI.Permissions.required(forEvent: ExtensionEventName.projectsChanged) == .projectsRead)
    }
}

@Suite("MuxyAPI project management routing")
@MainActor
struct MuxyAPIProjectManagementRoutingTests {
    @Test("switch resolves remote projects and activates their workspace")
    func switchResolvesRemoteProject() throws {
        let env = ProjectManagementEnvironment()
        let workspace = env.projectGroupStore.addRemoteWorkspace(name: "Remote", deviceID: UUID())
        let remote = try #require(env.projectGroupStore.addRemoteProject(
            name: "API",
            path: "/srv/api",
            toGroup: workspace.id
        ))
        let project = remote.asProject(workspaceID: workspace.id, sortOrder: 0)
        env.worktreeStore.ensurePrimary(for: project)

        let result = MuxyAPI.Projects.switchTo(
            identifier: project.id.uuidString,
            appState: env.appState,
            projectStore: env.projectStore,
            worktreeStore: env.worktreeStore,
            projectGroupStore: env.projectGroupStore
        )

        #expect(isSuccess(result))
        #expect(env.projectGroupStore.activeGroupID == workspace.id)
        #expect(env.appState.activeProjectID == project.id)
    }

    @Test("worktree navigation resolves a remote project returned by aggregate APIs")
    func worktreeNavigationResolvesRemoteProject() throws {
        let env = ProjectManagementEnvironment()
        let workspace = env.projectGroupStore.addRemoteWorkspace(name: "Remote", deviceID: UUID())
        let remote = try #require(env.projectGroupStore.addRemoteProject(
            name: "API",
            path: "/srv/api",
            toGroup: workspace.id
        ))
        let project = remote.asProject(workspaceID: workspace.id, sortOrder: 0)
        env.worktreeStore.ensurePrimary(for: project)

        let result = MuxyAPI.Worktrees.list(
            projectIdentifier: project.id.uuidString,
            appState: env.appState,
            projectStore: env.projectStore,
            worktreeStore: env.worktreeStore,
            projectGroupStore: env.projectGroupStore
        )

        guard case let .success(worktrees) = result else {
            Issue.record("expected remote worktrees")
            return
        }
        #expect(worktrees.count == 1)
        let worktree = try #require(worktrees.first)
        #expect(worktree.projectID == project.id)

        let switchResult = MuxyAPI.Worktrees.switchTo(
            identifier: worktree.id.uuidString,
            projectIdentifier: project.id.uuidString,
            appState: env.appState,
            projectStore: env.projectStore,
            worktreeStore: env.worktreeStore,
            projectGroupStore: env.projectGroupStore
        )

        #expect(isSuccess(switchResult))
        #expect(env.projectGroupStore.activeGroupID == workspace.id)
        #expect(env.appState.activeProjectID == project.id)
        #expect(env.appState.activeWorktreeID[project.id] == worktree.id)
    }

    @Test("aggregate lists include local and remote workspace context")
    func aggregateListsIncludeWorkspaceContext() throws {
        let local = Project(name: "Local", path: "/tmp/local")
        let env = ProjectManagementEnvironment(projects: [local])
        env.projectGroupStore.addGroup(name: "Local Workspace")
        let localWorkspace = try #require(env.projectGroupStore.groups.first)
        #expect(env.projectGroupStore.addProject(projectID: local.id, toGroup: localWorkspace.id))

        let remoteWorkspace = env.projectGroupStore.addRemoteWorkspace(name: "Remote Workspace", deviceID: UUID())
        let remote = try #require(env.projectGroupStore.addRemoteProject(
            name: "Remote",
            path: "/srv/remote",
            toGroup: remoteWorkspace.id
        )).asProject(workspaceID: remoteWorkspace.id, sortOrder: 0)
        env.worktreeStore.ensurePrimary(for: local)
        env.worktreeStore.ensurePrimary(for: remote)
        let localWorktree = try #require(env.worktreeStore.primary(for: local.id))
        env.appState.selectWorktree(projectID: local.id, worktree: localWorktree)

        let projects = MuxyAPI.Projects.listAll(
            appState: env.appState,
            projectStore: env.projectStore,
            projectGroupStore: env.projectGroupStore
        )
        let worktrees = MuxyAPI.Worktrees.listAll(
            appState: env.appState,
            projectStore: env.projectStore,
            worktreeStore: env.worktreeStore,
            projectGroupStore: env.projectGroupStore
        )

        let localInfo = try #require(projects.first { $0.id == local.id })
        #expect(localInfo.workspaceID == localWorkspace.id)
        #expect(localInfo.workspaceName == "Local Workspace")
        #expect(localInfo.workspaceKind == .local)
        let remoteInfo = try #require(projects.first { $0.id == remote.id })
        #expect(remoteInfo.workspaceID == remoteWorkspace.id)
        #expect(remoteInfo.workspaceName == "Remote Workspace")
        #expect(remoteInfo.workspaceKind == .ssh)
        #expect(worktrees.first { $0.projectID == local.id }?.isOpen == true)
        #expect(worktrees.first { $0.projectID == remote.id }?.isOpen == false)
    }

    @Test("rename mutates the resolved project and persists")
    func renameMutatesProject() {
        let project = Project(name: "Repo", path: "/tmp/muxy-rename-\(UUID().uuidString)")
        let env = ProjectManagementEnvironment(projects: [project])

        let result = MuxyAPI.Projects.rename(identifier: project.id.uuidString, name: "Renamed", context: env.context)

        #expect(isSuccess(result))
        #expect(env.projectStore.storedProjects.first { $0.id == project.id }?.name == "Renamed")
    }

    @Test("setColor / setIcon / setLogo mutate the resolved project")
    func metadataMutatesProject() {
        let project = Project(name: "Repo", path: "/tmp/muxy-meta-\(UUID().uuidString)")
        let env = ProjectManagementEnvironment(projects: [project])
        let id = project.id.uuidString

        #expect(isSuccess(MuxyAPI.Projects.setColor(identifier: id, color: "#E5484D", context: env.context)))
        #expect(isSuccess(MuxyAPI.Projects.setIcon(identifier: id, icon: "star.fill", context: env.context)))
        #expect(isSuccess(MuxyAPI.Projects.setLogo(
            identifier: id,
            logo: "\(project.id.uuidString).png",
            context: env.context
        )))

        let stored = env.projectStore.storedProjects.first { $0.id == project.id }
        #expect(stored?.iconColor == "#E5484D")
        #expect(stored?.icon == "star.fill")
        #expect(stored?.logo == "\(project.id.uuidString).png")
    }

    @Test("setLogo rejects path traversal")
    func setLogoRejectsPathTraversal() {
        var project = Project(name: "Repo", path: "/tmp/muxy-logo-\(UUID().uuidString)")
        project.logo = "\(project.id.uuidString).png"
        let env = ProjectManagementEnvironment(projects: [project])

        let result = MuxyAPI.Projects.setLogo(
            identifier: project.id.uuidString,
            logo: "../projects.json",
            context: env.context
        )

        guard case .failure(.invalidArguments) = result else {
            Issue.record("expected invalidArguments for an unsafe logo path")
            return
        }
        #expect(env.projectStore.storedProjects.first { $0.id == project.id }?.logo == "\(project.id.uuidString).png")
    }

    @Test("setColor with nil clears the color")
    func setColorNilClears() {
        var project = Project(name: "Repo", path: "/tmp/muxy-clear-\(UUID().uuidString)")
        project.iconColor = "#E5484D"
        let env = ProjectManagementEnvironment(projects: [project])

        #expect(isSuccess(MuxyAPI.Projects.setColor(identifier: project.id.uuidString, color: nil, context: env.context)))
        #expect(env.projectStore.storedProjects.first { $0.id == project.id }?.iconColor == nil)
    }

    @Test("reorder reindexes sortOrder to match the given identifier order")
    func reorderReindexes() {
        let first = Project(name: "A", path: "/tmp/a", sortOrder: 0)
        let second = Project(name: "B", path: "/tmp/b", sortOrder: 1)
        let third = Project(name: "C", path: "/tmp/c", sortOrder: 2)
        let env = ProjectManagementEnvironment(projects: [first, second, third])

        let result = MuxyAPI.Projects.reorder(
            identifiers: [third.id.uuidString, first.id.uuidString, second.id.uuidString],
            context: env.context
        )

        #expect(isSuccess(result))
        #expect(env.projectStore.storedProjects.map(\.id) == [third.id, first.id, second.id])
        #expect(env.projectStore.storedProjects.map(\.sortOrder) == [0, 1, 2])
    }

    @Test("reorder rejects an empty identifier list")
    func reorderRejectsEmpty() {
        let project = Project(name: "A", path: "/tmp/a", sortOrder: 0)
        let env = ProjectManagementEnvironment(projects: [project])

        let result = MuxyAPI.Projects.reorder(identifiers: [], context: env.context)

        guard case .failure = result else {
            Issue.record("expected failure for an empty identifier list")
            return
        }
    }

    @Test("reorder rejects a partial list and leaves order untouched")
    func reorderRejectsPartial() {
        let first = Project(name: "A", path: "/tmp/a", sortOrder: 0)
        let second = Project(name: "B", path: "/tmp/b", sortOrder: 1)
        let env = ProjectManagementEnvironment(projects: [first, second])

        let result = MuxyAPI.Projects.reorder(identifiers: [second.id.uuidString], context: env.context)

        guard case .failure(.invalidArguments) = result else {
            Issue.record("expected invalidArguments for a partial list")
            return
        }
        #expect(env.projectStore.storedProjects.map(\.id) == [first.id, second.id])
    }

    @Test("reorder rejects a duplicated identifier and leaves order untouched")
    func reorderRejectsDuplicate() {
        let first = Project(name: "A", path: "/tmp/a", sortOrder: 0)
        let second = Project(name: "B", path: "/tmp/b", sortOrder: 1)
        let env = ProjectManagementEnvironment(projects: [first, second])

        let result = MuxyAPI.Projects.reorder(
            identifiers: [first.id.uuidString, first.id.uuidString, second.id.uuidString],
            context: env.context
        )

        guard case .failure(.invalidArguments) = result else {
            Issue.record("expected invalidArguments for a duplicated identifier")
            return
        }
        #expect(env.projectStore.storedProjects.map(\.id) == [first.id, second.id])
    }

    @Test("reorder ignores remote projects")
    func reorderIgnoresRemoteProjects() {
        let first = Project(name: "A", path: "/tmp/a", sortOrder: 0)
        let remote = Project(name: "Remote", path: "/remote/repo", sortOrder: 1, remoteWorkspaceID: UUID())
        let second = Project(name: "B", path: "/tmp/b", sortOrder: 2)
        let env = ProjectManagementEnvironment(projects: [first, remote, second])

        let result = MuxyAPI.Projects.reorder(
            identifiers: [second.id.uuidString, first.id.uuidString],
            context: env.context
        )

        #expect(isSuccess(result))
        #expect(env.projectStore.storedProjects.map(\.id) == [second.id, remote.id, first.id])
        #expect(env.projectStore.storedProjects.map(\.sortOrder) == [0, 1, 2])
    }

    @Test("rename rejects an empty or whitespace-only name")
    func renameRejectsEmptyName() {
        let project = Project(name: "Repo", path: "/tmp/muxy-empty-\(UUID().uuidString)")
        let env = ProjectManagementEnvironment(projects: [project])

        let result = MuxyAPI.Projects.rename(identifier: project.id.uuidString, name: "   ", context: env.context)

        guard case .failure(.invalidArguments) = result else {
            Issue.record("expected invalidArguments for an empty name")
            return
        }
        #expect(env.projectStore.storedProjects.first { $0.id == project.id }?.name == "Repo")
    }

    @Test("rename trims surrounding whitespace from the new name")
    func renameTrimsName() {
        let project = Project(name: "Repo", path: "/tmp/muxy-trim-\(UUID().uuidString)")
        let env = ProjectManagementEnvironment(projects: [project])

        #expect(isSuccess(MuxyAPI.Projects.rename(identifier: project.id.uuidString, name: "  Renamed  ", context: env.context)))
        #expect(env.projectStore.storedProjects.first { $0.id == project.id }?.name == "Renamed")
    }

    @Test("markActive does not broadcast a change")
    func markActiveDoesNotNotify() {
        let project = Project(name: "Repo", path: "/tmp/muxy-active-\(UUID().uuidString)")
        let store = ProjectStore(persistence: ProjectManagementPersistenceStub(initial: [project]))
        var changes = 0
        store.onProjectsChanged = { changes += 1 }

        store.markActive(id: project.id)

        #expect(changes == 0)
    }

    @Test("home project cannot be modified")
    func homeProjectRejected() {
        let env = ProjectManagementEnvironment()
        let result = MuxyAPI.Projects.rename(identifier: Project.homeID.uuidString, name: "Nope", context: env.context)

        guard case .failure(.invalidArguments) = result else {
            Issue.record("expected invalidArguments for the home project")
            return
        }
    }

    @Test("remote project cannot be modified")
    func remoteProjectRejected() {
        let remote = Project(name: "Remote", path: "/remote/repo", remoteWorkspaceID: UUID())
        let env = ProjectManagementEnvironment(projects: [remote])

        let result = MuxyAPI.Projects.rename(identifier: remote.id.uuidString, name: "Nope", context: env.context)

        guard case .failure(.invalidArguments) = result else {
            Issue.record("expected invalidArguments for a remote project")
            return
        }
        #expect(env.projectStore.storedProjects.first { $0.id == remote.id }?.name == "Remote")
    }

    @Test("unknown project is rejected")
    func unknownProjectRejected() {
        let env = ProjectManagementEnvironment()
        let result = MuxyAPI.Projects.setIcon(identifier: "does-not-exist", icon: "star", context: env.context)

        guard case .failure(.projectNotFound) = result else {
            Issue.record("expected projectNotFound for an unknown identifier")
            return
        }
    }

    @Test("onProjectsChanged fires once per mutation")
    func changeCallbackFires() {
        let project = Project(name: "Repo", path: "/tmp/muxy-cb-\(UUID().uuidString)")
        let env = ProjectManagementEnvironment(projects: [project])
        var changes = 0
        env.projectStore.onProjectsChanged = { changes += 1 }

        _ = MuxyAPI.Projects.rename(identifier: project.id.uuidString, name: "Renamed", context: env.context)

        #expect(changes == 1)
    }

    @Test("add with an invalid path returns invalidArguments")
    func addInvalidPathRejected() {
        let env = ProjectManagementEnvironment()
        let result = MuxyAPI.Projects.add(
            path: "/path/that/does/not/exist-\(UUID().uuidString)",
            context: env.context
        )

        guard case .failure(.invalidArguments) = result else {
            Issue.record("expected invalidArguments for an invalid path")
            return
        }
    }

    @Test("list surfaces sortOrder, iconColor and worktreesEnabled")
    func listSurfacesMetadata() {
        let first = Project(name: "A", path: "/tmp/a", sortOrder: 0)
        let second = Project(name: "B", path: "/tmp/b", sortOrder: 1)
        let env = ProjectManagementEnvironment(projects: [first, second])

        _ = MuxyAPI.Projects.setColor(identifier: first.id.uuidString, color: "#E5484D", context: env.context)
        _ = MuxyAPI.Projects.reorder(
            identifiers: [second.id.uuidString, first.id.uuidString],
            context: env.context
        )

        let list = MuxyAPI.Projects.list(appState: env.appState, projectStore: env.projectStore)
        let firstInfo = list.first { $0.id == first.id }
        #expect(firstInfo?.iconColor == "#E5484D")
        #expect(firstInfo?.sortOrder == 1)
        #expect(firstInfo?.worktreesEnabled == false)
    }

    @Test("add enables worktrees on a newly added project")
    func addEnablesWorktrees() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("muxy-add-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let env = ProjectManagementEnvironment()

        #expect(isSuccess(MuxyAPI.Projects.add(path: dir.path, context: env.context)))

        let added = env.projectStore.storedProjects.first { $0.path == dir.standardizedFileURL.path }
        #expect(added?.worktreesEnabled == true)
    }

    @Test("add does not override worktreesEnabled on an existing project")
    func addPreservesExistingWorktreesSetting() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("muxy-existing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let existing = Project(name: "Existing", path: dir.standardizedFileURL.path)
        let env = ProjectManagementEnvironment(projects: [existing])

        let result = MuxyAPI.Projects.add(path: dir.path, context: env.context)
        #expect((try? result.get()) == existing.id)

        #expect(env.projectStore.storedProjects.first { $0.id == existing.id }?.worktreesEnabled == false)
    }

    private func isSuccess(_ result: Result<some Any, APIError>) -> Bool {
        if case .success = result { return true }
        return false
    }
}
