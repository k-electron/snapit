import SwiftUI

extension FolderGuideModel {
    func makeView() -> AnyView { AnyView(FolderGuideView(model: self)) }
}

/// The folder Permission guide: the drawing (or, for a cause that is not about macOS access, an
/// icon), what went wrong, and its buttons.
struct FolderGuideView: View {
    let model: FolderGuideModel

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
            // Up to four buttons: in one row when they fit, else in a column.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons }
                VStack(spacing: 8) { buttons }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        ForEach(model.buttons, id: \.id) { button in
            Button {
                Task { _ = await model.press(button.id) }
            } label: {
                Text(button.title)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(ChromeButtonStyle(look: button.id == model.openSystemSettingsButton.id ? .prominent : .plain, radius: 12))
            .help(button.tooltip)
            .disabled(model.isRetrying)
        }
    }

    @ViewBuilder private var picture: some View {
        if let category = model.category, model.showsSettingsSwitch {
            FolderGuideDrawing(
                progress: model.animation.progress, isPlaying: model.animation.state == .playing,
                rowName: category.title
            )
            .id(model.animation.epoch)
            .padding(12)
            .chromeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            Image(systemName: model.cause == .diskFull ? "externaldrive.badge.xmark" : "folder.badge.minus")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
                .frame(width: GuideTimeline.size.width + 24, height: GuideTimeline.size.height + 24)
                .chromeGlass(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// The picture for a folder macOS refused: System Settings' Files & Folders list, snapit's row with the
/// category's switch off, and the cursor turning it on. Like `GuideDrawing` it is a pure function of
/// `progress` (a loop counter whose fraction is the position in the loop), so nothing runs when it is
/// not changing, and a play is one finite animation.
struct FolderGuideDrawing: View, Animatable {
    var progress: Double
    var isPlaying: Bool
    /// The switch's label in System Settings (`FolderCategory.title`).
    var rowName: String

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private static let toggle = CGPoint(x: 338, y: 150)
    private static let cursorStart = CGPoint(x: 352, y: 214)

    private var t: Double { isPlaying ? progress - progress.rounded(.down) : 1 }
    private func ramp(_ from: Double, _ to: Double) -> Double { min(1, max(0, (t - from) / (to - from))) }
    private func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    var body: some View {
        let on = ease(ramp(0.38, 0.48))
        let travel = ease(ramp(0.05, 0.36))
        let cursor = CGPoint(
            x: Self.cursorStart.x + (Self.toggle.x - Self.cursorStart.x) * travel,
            y: Self.cursorStart.y + (Self.toggle.y - Self.cursorStart.y) * travel)
        let pressed = (0.34...0.42).contains(t)
        ZStack(alignment: .topLeading) {
            window
            row(y: 150, on: on)
            if (0.34...0.5).contains(t) {
                let ripple = ramp(0.34, 0.5)
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 12 + 30 * ripple, height: 12 + 30 * ripple)
                    .opacity(1 - ripple)
                    .position(Self.toggle)
            }
            CursorShape()
                .fill(Color.white)
                .overlay(CursorShape().stroke(Color.black, lineWidth: 1))
                .frame(width: 13, height: 20)
                .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                .scaleEffect(pressed ? 0.86 : 1, anchor: .topLeading)
                .position(x: cursor.x + 6.5, y: cursor.y + 10)
        }
        .frame(width: GuideTimeline.size.width, height: GuideTimeline.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private var window: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.18), lineWidth: 1))
                .frame(width: 360, height: 212)
                .position(x: 200, y: 120)
            ForEach(0..<3, id: \.self) { index in
                Circle().fill([Color.red, .yellow, .green][index].opacity(0.8))
                    .frame(width: 8, height: 8)
                    .position(x: 36 + CGFloat(index) * 14, y: 28)
            }
            ForEach(0..<5, id: \.self) { index in
                if index == 3 {
                    Text("Privacy & Security")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 82, height: 15)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor))
                        .position(x: 66, y: 62 + CGFloat(index) * 22)
                } else {
                    Capsule().fill(Color.primary.opacity(0.14))
                        .frame(width: 56, height: 7)
                        .position(x: 56, y: 62 + CGFloat(index) * 22)
                }
            }
            Text("Files & Folders")
                .font(.system(size: 11, weight: .semibold))
                .position(x: 218, y: 52)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 250, height: 110)
                .position(x: 247, y: 130)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor)
                    .frame(width: 18, height: 18)
                    .overlay(Image(systemName: "camera.viewfinder").font(.system(size: 10)).foregroundStyle(.white))
                Text("snapit").font(.system(size: 11, weight: .medium))
            }
            .position(x: 178, y: 104)
        }
    }

    /// The folder's row under snapit, with its switch.
    private func row(y: CGFloat, on: Double) -> some View {
        ZStack {
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
                .position(x: 162, y: y)
            Text(rowName)
                .font(.system(size: 10.5, weight: .medium))
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
                .position(x: 232, y: y)
            ZStack {
                Capsule().fill(Color.primary.opacity(0.22)).frame(width: 34, height: 20)
                Capsule().fill(Color.accentColor).frame(width: 34, height: 20).opacity(on)
                Circle().fill(Color.white).frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .offset(x: -7 + 14 * on)
            }
            .position(x: Self.toggle.x, y: y)
        }
    }
}
