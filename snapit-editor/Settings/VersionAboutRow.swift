import Foundation

extension SettingsControl {
    static let version = SettingsControl(
        id: "version", section: .about, title: "Version", tooltip: "The version of snapit")
}

extension AboutRow {
    /// The version snapit has in its bundle.
    static let version = AboutRow(
        control: .version,
        content: .text {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = info?["CFBundleVersion"] as? String
            return build.map { "\(version) (\($0))" } ?? version
        })
}
