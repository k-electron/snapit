import Foundation
import Security

/// What an Update checks of the bundle it staged before it swaps it in: it is snapit, it is the
/// version the Update window announced, and its signature passes a strict check that includes
/// nested code (the Editor helper). Blocks, so callers run it off the main actor.
nonisolated enum BundleCheck {
    enum Failure: Error, CustomStringConvertible {
        case identifier(found: String?)
        case version(found: String?)
        case signature(String)

        var description: String {
            switch self {
            case .identifier(let found): "the new bundle is \(found ?? "unnamed"), not snapit"
            case .version(let found): "the new bundle is version \(found ?? "unknown"), not the announced one"
            case .signature(let reason): "the new bundle's signature is not valid: \(reason)"
            }
        }
    }

    /// Throws the first check the bundle at `bundle` fails: its `CFBundleIdentifier` must be
    /// `identifier`, its `CFBundleShortVersionString` must be `version`, and its signature must pass
    /// a strict validity check of the bundle and every piece of code nested in it.
    static func verify(_ bundle: URL, identifier: String, version: String) throws {
        let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        let foundIdentifier = info?["CFBundleIdentifier"] as? String
        guard foundIdentifier == identifier else { throw Failure.identifier(found: foundIdentifier) }
        let foundVersion = info?["CFBundleShortVersionString"] as? String
        guard foundVersion == version else { throw Failure.version(found: foundVersion) }
        try verifySignature(of: bundle)
    }

    private static func verifySignature(of bundle: URL) throws {
        var code: SecStaticCode?
        let created = SecStaticCodeCreateWithPath(bundle as CFURL, SecCSFlags(rawValue: 0), &code)
        guard created == errSecSuccess, let code else { throw Failure.signature("it cannot be read (\(created))") }
        let flags = SecCSFlags(
            rawValue: UInt32(kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode))
        var error: Unmanaged<CFError>?
        let status = SecStaticCodeCheckValidityWithErrors(code, flags, nil, &error)
        guard status == errSecSuccess else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "status \(status)"
            throw Failure.signature(reason)
        }
    }
}
