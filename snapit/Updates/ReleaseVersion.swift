import Foundation

/// A version of exactly three integers, `X.Y.Z`, compared number by number (so 0.10.0 is newer
/// than 0.9.0). A leading `v` is tolerated, as in a release tag. Anything else is not a version:
/// `1.2`, `1.2.3.4`, `1.2.3-beta`, `+1.2.3`, `1.2.x`, an empty string.
nonisolated struct ReleaseVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespacesAndNewlines))
        if rest.first == "v" || rest.first == "V" { rest.removeFirst() }
        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers = [Int]()
        for part in parts {
            // ASCII digits only: `Int("+1")` is 1, and other scripts' digits are not versions.
            guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), let number = Int(part)
            else { return nil }
            numbers.append(number)
        }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
