import SwiftUI

/// The Settings page: one scrolling form with a section each for General, Capturing, Editor,
/// Shortcuts, Export and About. Every button is a glass button whose whole capsule is the hit
/// area, and every control has a hover tooltip.
struct SettingsView: View {
    let model: SettingsModel
    /// The Settings window, which the folder chooser slides down from.
    let window: () -> NSWindow?

    var body: some View {
        Form {
            general
            capturing
            editor
            shortcuts
            export
            about
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, idealWidth: 520, minHeight: 360, idealHeight: 760)
    }

    // MARK: General

    private var general: some View {
        Section(SettingsSection.general.rawValue) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    SettingsControl.openAtLogin.title,
                    isOn: Binding(
                        get: { model.login == .on },
                        set: { on in Task { await model.setOpenAtLogin(on) } }))
                    .toggleStyle(.switch)
                    .disabled(model.login == .unknown)
                    .help(SettingsControl.openAtLogin.tooltip)
                loginNote
            }
            LabeledContent(SettingsControl.saveLocation.title) {
                HStack(spacing: 10) {
                    Text(Self.abbreviated(model.saveLocation))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(model.saveLocation.path)
                    Button(SettingsControl.chooseSaveLocation.title) { model.chooseSaveLocation(from: window()) }
                        .buttonStyle(.glass)
                        .help(SettingsControl.chooseSaveLocation.tooltip)
                }
            }
            .help(SettingsControl.saveLocation.tooltip)
        }
    }

    @ViewBuilder private var loginNote: some View {
        switch model.login {
        case .needsApproval:
            HStack {
                Text("macOS needs your approval before snapit can open at login.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Login Items") { model.openLoginItems() }
                    .buttonStyle(.glass)
                    .help("Open System Settings to approve snapit")
            }
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private static func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    // MARK: Capturing

    private var capturing: some View {
        Section(SettingsSection.capturing.rawValue) {
            Picker(
                SettingsControl.afterSelectingArea.title,
                selection: Binding(get: { model.afterSelectingArea }, set: { model.setAfterSelectingArea($0) })
            ) {
                ForEach(AfterSelectingArea.allCases, id: \.self) { choice in
                    Text(choice.settingsTitle)
                        .contentShape(Rectangle())
                        .help(choice.settingsTooltip)
                        .tag(choice)
                }
            }
            .pickerStyle(.radioGroup)
            .help(SettingsControl.afterSelectingArea.tooltip)
        }
    }

    // MARK: Editor

    private var editor: some View {
        Section(SettingsSection.editor.rawValue) {
            switchRow(
                SettingsControl.closeAfterCopy, isOn: Binding(get: { model.closeAfterCopy }, set: model.setCloseAfterCopy))
            switchRow(
                SettingsControl.closeAfterSave, isOn: Binding(get: { model.closeAfterSave }, set: model.setCloseAfterSave))
        }
    }

    // MARK: Shortcuts

    private var shortcuts: some View {
        Section(SettingsSection.shortcuts.rawValue) {
            ShortcutRecorderRows(model: model)
            VStack(alignment: .leading, spacing: 8) {
                Text("To use ⌘⇧3, ⌘⇧4 or ⌘⇧5 for snapit, turn them off in Keyboard Shortcuts… › Screenshots.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(SettingsControl.openScreenshotShortcuts.title) { model.openScreenshotShortcuts() }
                    .buttonStyle(.glass)
                    .help(SettingsControl.openScreenshotShortcuts.tooltip)
            }
        }
    }

    // MARK: Export

    private var export: some View {
        Section(SettingsSection.export.rawValue) {
            switchRow(
                SettingsControl.standardResolution,
                isOn: Binding(get: { model.standardResolution }, set: model.setStandardResolution))
        }
    }

    // MARK: About

    private var about: some View {
        Section(SettingsSection.about.rawValue) {
            ForEach(AboutRows.all, id: \.control.id) { row in
                switch row.content {
                case .text(let text):
                    LabeledContent(row.control.title, value: text())
                        .help(row.control.tooltip)
                case .button(let action):
                    Button(row.control.title) { action(model) }
                        .buttonStyle(.glass)
                        .help(row.control.tooltip)
                }
            }
        }
    }

    private func switchRow(_ control: SettingsControl, isOn: Binding<Bool>) -> some View {
        Toggle(control.title, isOn: isOn)
            .toggleStyle(.switch)
            .contentShape(Rectangle())
            .help(control.tooltip)
    }
}
