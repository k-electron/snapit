import SwiftUI

extension PermissionGuideModel {
    /// Does what the button with this id does.
    func press(_ id: String) async -> Bool {
        switch id {
        case openSystemSettingsButton.id: openSystemSettings()
        case relaunchButton.id: await relaunch()
        case replayButton.id: replay()
        default: return false
        }
        return true
    }
}

/// The Permission guide: the drawing, what to do, and its buttons. Onboarding's Screen Recording
/// step and the guide's own window both show it.
struct PermissionGuideView: View {
    let model: PermissionGuideModel

    var body: some View {
        VStack(spacing: 14) {
            picture
            Text(model.headline)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(model.message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 440)
            if let error = model.relaunchError {
                Text(error).foregroundStyle(.red).font(.callout)
            }
            HStack(spacing: 10) {
                ForEach(model.buttons, id: \.id) { button in
                    Button {
                        Task { _ = await model.press(button.id) }
                    } label: {
                        Text(button.title)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(ChromeButtonStyle(look: button.id == model.openSystemSettingsButton.id ? .prominent : .plain, radius: 12))
                    .help(button.tooltip)
                }
            }
        }
    }

    @ViewBuilder private var picture: some View {
        if model.isGranted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
                .frame(width: GuideTimeline.size.width + 24, height: GuideTimeline.size.height + 24)
                .chromeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            GuideDrawing(
                progress: model.animation.progress, isPlaying: model.animation.state == .playing, variant: model.variant
            )
            .id(model.animation.epoch)
            .padding(12)
            .chromeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
