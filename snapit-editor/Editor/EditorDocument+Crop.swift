import CoreGraphics

extension EditorDocument {
    /// The applied crop in image points; nil for the whole Capture.
    var crop: CGRect? { history.state.crop }

    /// The applied crop as the device pixels of the Capture it keeps; nil when nothing is cropped.
    /// The canvas and the Export both take their rectangle from here (`CropGeometry.pixelRect`).
    var cropPixels: PixelRect? {
        guard let crop else { return nil }
        let info = capture.info
        guard let area = CropGeometry.pixelRect(crop, scale: info.scale, width: info.width, height: info.height),
            area != PixelRect(x: 0, y: 0, width: info.width, height: info.height)
        else { return nil }
        return area
    }
}
