import CoreGraphics
import Foundation

nonisolated extension PixelBuffer {
    /// A `CGImage` that reads these pixels in place, with no copy. The image keeps the buffer
    /// (and so its mapping) alive until the image itself is released.
    func makeCGImage() -> CGImage? {
        let retained = Unmanaged.passRetained(self)
        let release: CGDataProviderReleaseDataCallback = { info, _, _ in
            if let info { Unmanaged<PixelBuffer>.fromOpaque(info).release() }
        }
        let size = stride * height
        let provider = withReadOnlyPixels { base, _ in
            CGDataProvider(dataInfo: retained.toOpaque(), data: base, size: size, releaseData: release)
        }
        guard let provider else {
            retained.release()
            return nil
        }
        let bitmapInfo = CGBitmapInfo(
            rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
            space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)
    }
}
