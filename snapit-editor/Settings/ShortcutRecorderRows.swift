import SwiftUI

/// One row per Shortcut of `ShortcutCatalog`: its recorder button, a button that unassigns it, and
/// under it the hint for a key that cannot be a Shortcut and the flag for one macOS also uses.
/// Settings and Onboarding's Shortcuts step both show these rows, driven by a `SettingsModel`.
struct ShortcutRecorderRows: View {
    let model: SettingsModel

    var body: some View {
        ForEach(ShortcutCatalog.entries, id: \.shortcut.id) { entry in
            LabeledContent(entry.title) {
                HStack(spacing: 8) {
                    recorderButton(entry)
                    if model.combo(for: entry) != nil && model.recordingID != entry.shortcut.id {
                        Button {
                            model.record(nil, for: entry)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 28, height: 28)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help(SettingsControl.clearShortcutTooltip)
                    }
                }
            }
            if model.recordingID == entry.shortcut.id, let hint = model.recordingHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if let note = model.note(for: entry) {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        if let error = model.shortcutError {
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func recorderButton(_ entry: ShortcutCatalog.Entry) -> some View {
        let control = SettingsControl.shortcut(entry)
        let recording = model.recordingID == entry.shortcut.id
        return Button {
            if recording { model.cancelRecording() } else { model.beginRecording(entry) }
        } label: {
            Text(
                !model.shortcutsLoaded ? "…" : recording ? "Type a Shortcut" : model.combo(for: entry)?.displayString ?? "Record Shortcut"
            )
            .frame(minWidth: 130)
            .padding(.vertical, 2)
        }
        .buttonStyle(.glass)
        .disabled(!model.shortcutsLoaded)
        .tint(recording ? .accentColor : nil)
        .help(control.tooltip)
    }
}
