import Foundation

enum ExtensionHomePreference {
    static let storageKey = "muxy.launchHomeView"

    static func value(extensionID: String, homeViewID: String) -> String {
        "\(extensionID):\(homeViewID)"
    }

    static func parse(_ value: String) -> (extensionID: String, homeViewID: String)? {
        guard let separator = value.firstIndex(of: ":") else { return nil }
        let extensionID = String(value[..<separator])
        let homeViewID = String(value[value.index(after: separator)...])
        guard !extensionID.isEmpty, !homeViewID.isEmpty else { return nil }
        return (extensionID, homeViewID)
    }
}
