import SwiftUI

/// The Screen Recording guide's picture: a simplified drawing of macOS's own screens, made of
/// SwiftUI shapes (no video, no image). It is a pure function of `progress`, so SwiftUI plays the
/// animation by interpolating that one number, and nothing runs when it does not change.
///
/// `progress` counts loops: its fraction is the position in the current loop. Not playing, the
/// drawing rests on the last pose of a loop, with snapit's switch on.
struct GuideDrawing: View, Animatable {
    var progress: Double
    var isPlaying: Bool
    var variant: PermissionGuideModel.Variant

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var timeline: GuideTimeline {
        GuideTimeline(t: isPlaying ? progress - progress.rounded(.down) : 1, variant: variant)
    }

    var body: some View {
        let line = timeline
        ZStack(alignment: .topLeading) {
            settingsWindow(line)
                .opacity(line.listOpacity)
            if line.promptOpacity > 0 { promptDialog(line).opacity(line.promptOpacity) }
            if line.quitDialog > 0 { quitDialog(line) }
            if let ripple = line.ripple {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 12 + 30 * ripple, height: 12 + 30 * ripple)
                    .opacity(1 - ripple)
                    .position(GuideTimeline.toggle)
            }
            cursor(line)
        }
        .frame(width: GuideTimeline.size.width, height: GuideTimeline.size.height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    // MARK: System Settings

    private func settingsWindow(_ line: GuideTimeline) -> some View {
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
            // The sidebar: placeholder rows, and Privacy & Security chosen.
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
            Text("Screen & System Audio Recording")
                .font(.system(size: 11, weight: .semibold))
                .position(x: 238, y: 52)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 250, height: 120)
                .position(x: 247, y: 130)
            appRow(y: 90, name: nil, on: 1)
            appRow(y: 130, name: "snapit", on: line.switchOn)
            appRow(y: 170, name: nil, on: 0)
        }
    }

    private func appRow(y: CGFloat, name: String?, on: Double) -> some View {
        ZStack {
            if let name {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor)
                    .frame(width: 20, height: 20)
                    .overlay(Image(systemName: "camera.viewfinder").font(.system(size: 11)).foregroundStyle(.white))
                    .position(x: 146, y: y)
                Text(name).font(.system(size: 11, weight: .medium)).position(x: 182, y: y)
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.16))
                    .frame(width: 20, height: 20)
                    .position(x: 146, y: y)
                Capsule().fill(Color.primary.opacity(0.14)).frame(width: 70, height: 7).position(x: 192, y: y)
            }
            switchControl(on: on).position(x: GuideTimeline.toggle.x, y: y)
        }
    }

    private func switchControl(on: Double) -> some View {
        ZStack {
            Capsule().fill(Color.primary.opacity(0.22)).frame(width: 34, height: 20)
            Capsule().fill(Color.accentColor).frame(width: 34, height: 20).opacity(on)
            Circle().fill(Color.white).frame(width: 16, height: 16)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .offset(x: -7 + 14 * on)
        }
    }

    // MARK: macOS's messages

    private func message(_ text: String, size: CGSize) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                Text(text)
                    .font(.system(size: 9.5, weight: .medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
            }
    }

    private func messageButton(_ title: String, center: CGPoint, width: CGFloat, prominent: Bool, pressed: Bool) -> some View {
        Text(title)
            .font(.system(size: 9.5, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(width: width, height: 20)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? Color.accentColor : Color.primary.opacity(0.12))
                    .brightness(pressed ? -0.18 : 0)
            )
            .position(center)
    }

    private func promptDialog(_ line: GuideTimeline) -> some View {
        ZStack {
            message(
                "“snapit” would like to record this computer's screen and audio.",
                size: CGSize(width: 250, height: 126)
            )
            .position(x: 200, y: 120)
            messageButton(
                "Open System Settings", center: GuideTimeline.promptButton, width: 190, prominent: true,
                pressed: line.promptButtonPressed)
            messageButton("Don't Allow", center: CGPoint(x: 200, y: 164), width: 190, prominent: false, pressed: false)
        }
    }

    private func quitDialog(_ line: GuideTimeline) -> some View {
        ZStack {
            message("“snapit” may not be able to record until it is quit.", size: CGSize(width: 200, height: 104))
                .position(x: 200, y: 126)
            messageButton("Later", center: CGPoint(x: 160, y: GuideTimeline.quitAndReopen.y), width: 70, prominent: false, pressed: false)
            messageButton(
                "Quit & Reopen", center: GuideTimeline.quitAndReopen, width: 84, prominent: true,
                pressed: line.quitButtonPressed)
        }
        .scaleEffect(0.92 + 0.08 * line.quitDialog)
        .opacity(line.quitDialog)
    }

    // MARK: Cursor

    private func cursor(_ line: GuideTimeline) -> some View {
        CursorShape()
            .fill(Color.white)
            .overlay(CursorShape().stroke(Color.black, lineWidth: 1))
            .frame(width: 13, height: 20)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .scaleEffect(line.cursorPressed ? 0.86 : 1, anchor: .topLeading)
            .position(x: line.cursor.x + 6.5, y: line.cursor.y + 10)
    }
}

/// The arrow pointer, tip at the top left.
nonisolated struct CursorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.width / 13
        let y = rect.height / 20
        let points = [(0, 0), (0, 16), (4, 12.5), (7, 19), (10, 18), (7.2, 11.6), (12, 11.6)]
        for (index, point) in points.enumerated() {
            let location = CGPoint(x: point.0 * x, y: point.1 * y)
            if index == 0 { path.move(to: location) } else { path.addLine(to: location) }
        }
        path.closeSubpath()
        return path
    }
}
