import SwiftUI

/// The Welcome step's picture: the top right of a menu bar, with snapit's icon circled and an arrow
/// pointing at it. Static: nothing in it moves.
struct WelcomeDrawing: View {
    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 1))
                HStack(spacing: 16) {
                    Capsule().fill(Color.primary.opacity(0.2)).frame(width: 18, height: 8)
                    Capsule().fill(Color.primary.opacity(0.2)).frame(width: 26, height: 8)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(5)
                        .background(Circle().stroke(Color.accentColor, lineWidth: 2))
                    Capsule().fill(Color.primary.opacity(0.2)).frame(width: 18, height: 8)
                    Text("9:41").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                .padding(.trailing, 14)
            }
            .frame(width: 330, height: 36)
            HStack {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    Text("snapit lives here")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.trailing, 62)
            }
            .frame(width: 330)
            .padding(.top, 8)
        }
        .accessibilityLabel("The snapit icon in the menu bar")
    }
}
