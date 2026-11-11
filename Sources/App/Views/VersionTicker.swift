import Foundation

/// Monospace version ticker formatter (MJ-103): `vX.Y.Z · B<build> · <sha>`,
/// read from the app's Info.plist. Pure formatter; the view layer only
/// supplies the dictionary.
enum VersionTicker {
    static func text(info: [String: Any]) -> String {
        let version = clean(info["CFBundleShortVersionString"]) ?? "0.0.0"
        let build = clean(info["CFBundleVersion"]) ?? "0"
        var parts = ["v\(version)", "B\(build)"]
        if let sha = clean(info["GitCommitSHA"]) { parts.append(sha) }
        return parts.joined(separator: " · ")
    }

    private static func clean(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }
}
