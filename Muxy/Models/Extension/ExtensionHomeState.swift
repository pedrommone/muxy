import Foundation

@MainActor
@Observable
final class ExtensionHomeState: Identifiable {
    let id = UUID()
    let extensionID: String
    let homeViewID: String
    let title: String
    @ObservationIgnored let surfaceStore = ExtensionWebViewSurfaceStore()
    var data: ExtensionJSON?

    init(
        extensionID: String,
        homeViewID: String,
        title: String,
        data: ExtensionJSON?
    ) {
        self.extensionID = extensionID
        self.homeViewID = homeViewID
        self.title = title
        self.data = data
    }
}
