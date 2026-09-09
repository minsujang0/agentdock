// Checking GitHub for a newer release.
//
// The app is ad-hoc signed and built from this checkout, so an update is a
// pull and a rebuild rather than a downloaded bundle. Shipping the .app as a
// release asset would mean signing and notarising it — without that Gatekeeper
// refuses anything the browser marked as downloaded, and telling people to
// strip the quarantine attribute is worse advice than telling them to build.
//
// So only a version string comes off the network. The tag it names is checked
// against a strict shape before it can reach git, and the code itself comes
// from the remote this checkout already had.

import Foundation

enum Update {
    static let repo = "minsujang0/agentdock"
    /// What this build calls itself. Read from the bundle so there is one
    /// place to change it: build.sh writes it into the Info.plist.
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    struct Release {
        let tag: String
        let version: String
        let notes: String
        let page: URL?
        var isNewer: Bool { Update.outranks(version, Update.current) }
    }

    enum Failure: LocalizedError {
        case noRelease
        case unreachable(String)
        case oddTag(String)

        var errorDescription: String? {
            switch self {
            case .noRelease: return "아직 공개된 릴리스가 없습니다"
            case .unreachable(let why): return "릴리스 정보를 못 읽었습니다: \(why)"
            case .oddTag(let tag): return "태그 형식이 올바르지 않습니다: \(tag)"
            }
        }
    }

    /// A version as numbers, so 0.10 sorts above 0.9 rather than below it.
    static func rank(_ version: String) -> [Int] {
        let core = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let head = core.split(separator: "-", maxSplits: 1).first.map(String.init) ?? core
        let parts = head.split(separator: ".").compactMap { Int($0) }
        return parts.isEmpty ? [0] : parts
    }

    /// Element by element, so [0, 10] beats [0, 9] and a shorter run of the
    /// same numbers is the older one.
    static func outranks(_ lhs: String, _ rhs: String) -> Bool {
        let left = rank(lhs), right = rank(rhs)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    /// A tag is about to become a git argument, so it is held to the shape a
    /// release tag has rather than to whatever came back.
    static func looksLikeTag(_ tag: String) -> Bool {
        let pattern = "^v?[0-9]+(\\.[0-9]+){0,3}(-[0-9A-Za-z.]+)?$"
        return tag.range(of: pattern, options: .regularExpression) != nil
    }

    static func latest() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("SessionDock/\(current)", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure.unreachable(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw Failure.noRelease }
            guard http.statusCode == 200 else {
                throw Failure.unreachable("HTTP \(http.statusCode)")
            }
        }
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = body["tag_name"] as? String else {
            throw Failure.unreachable("응답을 읽지 못했습니다")
        }
        guard looksLikeTag(tag) else { throw Failure.oddTag(String(tag.prefix(40))) }
        return Release(
            tag: tag,
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            notes: (body["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            page: URL(string: body["html_url"] as? String ?? ""))
    }
}
