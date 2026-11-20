import SwiftUI

/// The Onboarding window's content: the step's picture and words, then Back and Continue. Every
/// button is a chrome button whose whole tile is the hit area and has a hover tooltip.
struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.bottom, 18)
            VStack(spacing: 16) { content }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
                .padding(.top, 14)
        }
        .padding(.horizontal, 32)
        .padding(.top, 40)
        .padding(.bottom, 24)
        .frame(width: 600, height: 640)
        .background(.regularMaterial)
    }

    // MARK: Header and footer

    private var progress: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.number <= model.step.number ? Color.accentColor : Color.primary.opacity(0.15))
                        .frame(width: step == model.step ? 28 : 10, height: 6)
                }
            }
            Text("Step \(model.step.number) of \(OnboardingStep.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            ForEach(model.navigation, id: \.id) { button in
                if button.id != "back" { Spacer() }
                Button {
                    Task { _ = await model.press(button.id) }
                } label: {
                    label(button.title)
                }
                .windowButton(prominent: button.id != "back")
                .help(button.tooltip)
            }
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .frame(minWidth: 90)
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch model.step {
        case .welcome:
            heading
            WelcomeDrawing()
                .padding(20)
                .chromeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            body(model.text)
        case .screenRecording:
            PermissionGuideView(model: model.guide)
        case .saveLocation:
            heading
            body(model.text)
            saveLocation
        case .shortcuts:
            heading
            body(model.text)
            shortcuts
        case .openAtLogin:
            heading
            body(model.text)
            openAtLogin
        case .done:
            done
        }
    }

    private var heading: some View {
        Text(model.heading)
            .font(.largeTitle.weight(.semibold))
            .multilineTextAlignment(.center)
    }

    private func body(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 460)
    }

    private var saveLocation: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text((model.settings.saveLocation.path as NSString).abbreviatingWithTildeInPath)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.settings.saveLocation.path)
            Spacer()
            Button {
                Task { _ = await model.press(model.chooseSaveLocationButton.id) }
            } label: {
                label(model.chooseSaveLocationButton.title)
            }
            .windowButton(prominent: false)
            .help(model.chooseSaveLocationButton.tooltip)
        }
        .padding(16)
        .frame(width: 480)
        .chromeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            ShortcutRecorderRows(model: model.settings)
            Button {
                Task { _ = await model.press(model.screenshotShortcutsButton.id) }
            } label: {
                label(model.screenshotShortcutsButton.title)
            }
            .windowButton(prominent: false)
            .help(model.screenshotShortcutsButton.tooltip)
        }
        .padding(16)
        .frame(width: 480)
        .chromeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var openAtLogin: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                model.openAtLoginSwitch.title,
                isOn: Binding(
                    get: { model.settings.login == .on },
                    set: { on in Task { await model.settings.setOpenAtLogin(on) } })
            )
            .toggleStyle(.switch)
            .disabled(model.settings.login == .unknown)
            .contentShape(Rectangle())
            .help(model.openAtLoginSwitch.tooltip)
            switch model.settings.login {
            case .needsApproval:
                HStack {
                    Text("macOS needs your approval before snapit can open at login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items") { model.settings.openLoginItems() }
                        .buttonStyle(.glass)
                        .help("Open System Settings to approve snapit")
                }
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red)
            default:
                EmptyView()
            }
        }
        .padding(16)
        .frame(width: 480)
        .chromeGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var done: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 64))
            .foregroundStyle(.green)
        heading
        body(model.text)
        Text(model.tryIt)
            .font(.title3.weight(.medium))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .chromeGlass(Capsule())
        if UserGuideLink.open != nil {
            Button {
                Task { _ = await model.press(model.userGuideButton.id) }
            } label: {
                label(model.userGuideButton.title)
            }
            .windowButton(prominent: false)
            .help(model.userGuideButton.tooltip)
        }
    }
}
