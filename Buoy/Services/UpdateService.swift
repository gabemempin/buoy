import Foundation

actor UpdateService {
    static let shared = UpdateService()
    private let feedURL = URL(string: "https://raw.githubusercontent.com/gabemempin/buoy/main/version.json")!

    enum UpdateResult {
        case upToDate(version: String)
        case available(version: String, url: URL)
        case error
    }

    func checkForUpdates() async -> UpdateResult {
        guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
            return .error
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: feedURL)
            let payload = try JSONDecoder().decode(VersionPayload.self, from: data)
            if payload.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                return .available(version: payload.version, url: payload.installURL)
            }
            return .upToDate(version: currentVersion)
        } catch {
            return .error
        }
    }

    private struct VersionPayload: Decodable {
        let version: String
        let url: String
        var installURL: URL { URL(string: url)! }
    }
}
