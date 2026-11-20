// Independent checker for the scripted run. Built by scripts/check-run.sh with swiftc and
// used by the flows to look at a PNG the way a user's other apps would: it shares no code
// with snapit or the engine (the chunks are walked by hand, the pixels decoded by ImageIO).
//
//   png-inspect info <file>                     key=value lines: size, chunks, pHYs, iCCP
//   png-inspect verify-fixture <file> <w> <h>   compares every pixel with the fixture formula
//   png-inspect profile-sha <srgb|displayP3>    SHA-256 of the system's ICC profile
//   png-inspect verify-fixture <file> <w> <h> <full w> <full h> <x> <y>
//                                               the same for a crop: the file is the w x h pixels of the
//                                               full w x full h fixture that start at column x, row y
//   png-inspect pixel <file> <x> <y>            `r g b` of one pixel, read in sRGB
//   png-inspect overlay-windows <pid>           one line per on-screen window of the process at the
//                                               screen-saver level (the Area overlay's panels)
//   png-inspect general-pasteboard             changeCount of the general pasteboard (never its contents)
//   png-inspect windows <pid>                   one line per ordinary (layer 0) window of the process:
//                                               `<width>x<height> onscreen|offscreen`; no names, so no TCC prompt
//
// The fixture formula (see FixtureCaptureSource.swift), `w` x `h` pixels:
//   R = x * 255 / (w - 1)   G = y * 255 / (h - 1)   B = 40 if (x / 8 + y / 8) is even else 200
// Pixels are read back in the PNG's own color space, so the values are the raw components.

import AppKit
import CryptoKit
import Compression
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("png-inspect: \(message)\n".utf8))
    exit(2)
}

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

struct Chunk {
    let type: String
    let data: Data
}

func readChunks(_ file: Data) -> [Chunk] {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard file.count > 8, Array(file.prefix(8)) == signature else { fail("not a PNG") }
    var chunks: [Chunk] = []
    var at = 8
    func u32(_ offset: Int) -> Int {
        file[file.startIndex + offset ..< file.startIndex + offset + 4].reduce(0) { $0 << 8 | Int($1) }
    }
    while at + 12 <= file.count {
        let length = u32(at)
        let type = String(decoding: file[file.startIndex + at + 4 ..< file.startIndex + at + 8], as: UTF8.self)
        guard at + 12 + length <= file.count else { fail("truncated chunk \(type)") }
        chunks.append(Chunk(type: type, data: file[file.startIndex + at + 8 ..< file.startIndex + at + 8 + length]))
        at += 12 + length
    }
    return chunks
}

/// The inflated ICC profile of an iCCP chunk: name, NUL, method byte, zlib stream.
func iccProfile(_ chunk: Chunk) -> Data? {
    guard let nul = chunk.data.firstIndex(of: 0) else { return nil }
    let stream = chunk.data[(nul + 2)...]  // skip the NUL and the compression method
    guard stream.count > 6 else { return nil }
    let deflate = stream.dropFirst(2).dropLast(4)  // zlib header and Adler-32 around raw deflate
    var output = Data(count: 4 << 20)
    let written = output.withUnsafeMutableBytes { out in
        deflate.withUnsafeBytes { input in
            compression_decode_buffer(
                out.bindMemory(to: UInt8.self).baseAddress!, out.count,
                input.bindMemory(to: UInt8.self).baseAddress!, input.count, nil, COMPRESSION_ZLIB)
        }
    }
    return written > 0 ? output.prefix(written) : nil
}

func loadImage(_ path: String) -> (CGImage, [CFString: Any]) {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { fail("ImageIO cannot decode \(path)") }
    return (image, properties)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else { fail("usage: png-inspect info|verify-fixture|profile-sha|general-pasteboard|windows") }

switch arguments[1] {
case "info":
    guard arguments.count == 3, let file = FileManager.default.contents(atPath: arguments[2]) else { fail("info <file>") }
    let chunks = readChunks(file)
    let ihdr = chunks.first { $0.type == "IHDR" }!.data
    func be32(_ data: Data, _ offset: Int) -> Int {
        data[data.startIndex + offset ..< data.startIndex + offset + 4].reduce(0) { $0 << 8 | Int($1) }
    }
    print("width=\(be32(ihdr, 0))")
    print("height=\(be32(ihdr, 4))")
    print("bit_depth=\(ihdr[ihdr.startIndex + 8])")
    print("color_type=\(ihdr[ihdr.startIndex + 9])")
    print("chunks=\(chunks.map(\.type).joined(separator: ","))")
    if let phys = chunks.first(where: { $0.type == "pHYs" })?.data {
        print("phys=\(be32(phys, 0)),\(be32(phys, 4)),\(phys[phys.startIndex + 8])")
    } else {
        print("phys=none")
    }
    if let chunk = chunks.first(where: { $0.type == "iCCP" }), let profile = iccProfile(chunk) {
        print("icc_bytes=\(profile.count)")
        print("icc_sha256=\(sha256(profile))")
    } else {
        print("icc_bytes=0")
        print("icc_sha256=none")
    }
    let (_, properties) = loadImage(arguments[2])
    print("profile_name=\(properties[kCGImagePropertyProfileName] ?? "none")")
    print("dpi=\(properties[kCGImagePropertyDPIWidth] ?? "none")")

case "verify-fixture":
    // verify-fixture <file> <w> <h>                     the file is the fixture, w x h pixels
    // verify-fixture <file> <w> <h> <full w> <full h> <x> <y>
    //                                                   the file is the w x h pixels of the fixture image
    //                                                   (full w x full h) that start at column x, row y
    guard arguments.count == 5 || arguments.count == 9, let width = Int(arguments[3]), let height = Int(arguments[4])
    else { fail("verify-fixture <file> <w> <h> [<full w> <full h> <x> <y>]") }
    let whole = arguments.count == 9 ? arguments[5...8].compactMap { Int($0) } : []
    guard arguments.count == 5 || whole.count == 4 else { fail("verify-fixture: the crop arguments must be numbers") }
    let fullWidth = whole.isEmpty ? width : whole[0]
    let fullHeight = whole.isEmpty ? height : whole[1]
    let originX = whole.isEmpty ? 0 : whole[2]
    let originY = whole.isEmpty ? 0 : whole[3]
    let (image, _) = loadImage(arguments[2])
    guard image.width == width, image.height == height else {
        print("size=\(image.width)x\(image.height)")
        print("mismatches=all")
        exit(0)
    }
    guard let space = image.colorSpace,
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fail("cannot read pixels in the image's color space") }
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let pixels = context.data!.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var mismatches = 0
    var first = ""
    for y in 0..<height {
        for x in 0..<width {
            let at = pixels + (y * width + x) * 4
            let sourceX = originX + x, sourceY = originY + y
            let expected = (
                UInt8(sourceX * 255 / max(fullWidth - 1, 1)), UInt8(sourceY * 255 / max(fullHeight - 1, 1)),
                UInt8((sourceX / 8 + sourceY / 8) % 2 == 0 ? 40 : 200)
            )
            if at[0] != expected.0 || at[1] != expected.1 || at[2] != expected.2 {
                if mismatches == 0 { first = "\(x),\(y) got \(at[0]),\(at[1]),\(at[2]) want \(expected)" }
                mismatches += 1
            }
        }
    }
    print("size=\(width)x\(height)")
    print("mismatches=\(mismatches)")
    if mismatches > 0 { print("first_mismatch=\(first)") }

case "profile-sha":
    guard arguments.count == 3 else { fail("profile-sha <srgb|displayP3>") }
    let name = arguments[2] == "srgb" ? CGColorSpace.sRGB : CGColorSpace.displayP3
    guard let data = CGColorSpace(name: name)?.copyICCData() as Data? else { fail("no ICC data") }
    print(sha256(data))

case "general-pasteboard":
    // The change count only: the user's clipboard contents are never read.
    print("change_count=\(NSPasteboard.general.changeCount)")

case "windows":
    guard arguments.count == 3, let pid = Int32(arguments[2]) else { fail("windows <pid>") }
    // Window server facts only (owner, layer, size, whether it is on screen): no window names
    // are read, so this needs no Screen Recording permission.
    let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]]) ?? []
    for window in list where (window[kCGWindowOwnerPID as String] as? Int32) == pid && (window[kCGWindowLayer as String] as? Int) == 0 {
        let bounds = (window[kCGWindowBounds as String] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        guard let bounds, bounds.width > 8, bounds.height > 8 else { continue }
        let onScreen = (window[kCGWindowIsOnscreen as String] as? Bool) ?? false
        print("\(Int(bounds.width))x\(Int(bounds.height)) \(onScreen ? "onscreen" : "offscreen")")
    }

case "pixel":
    // pixel <file> <x> <y>: `r g b` of one pixel, read in sRGB.
    guard arguments.count == 5, let x = Int(arguments[3]), let y = Int(arguments[4]) else { fail("pixel <file> <x> <y>") }
    let (image, _) = loadImage(arguments[2])
    guard x >= 0, y >= 0, x < image.width, y < image.height,
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fail("pixel is outside the image") }
    context.setBlendMode(.copy)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let at = context.data!.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4) + (y * image.width + x) * 4
    print("\(at[0]) \(at[1]) \(at[2])")

case "overlay-windows":
    // overlay-windows <pid>: one line per window of the process at the screen-saver level that is
    // on screen (the Area overlay's panels): `<w>x<h> @<x>,<y>`. Window server facts only.
    guard arguments.count == 3, let pid = Int32(arguments[2]) else { fail("overlay-windows <pid>") }
    let overlayLevel = Int(CGWindowLevelForKey(.screenSaverWindow))
    let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
    for window in list where (window[kCGWindowOwnerPID as String] as? Int32) == pid && (window[kCGWindowLayer as String] as? Int) == overlayLevel {
        let bounds = (window[kCGWindowBounds as String] as? [String: Any]).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        guard let bounds else { continue }
        print("\(Int(bounds.width))x\(Int(bounds.height)) @\(Int(bounds.minX)),\(Int(bounds.minY))")
    }

default:
    fail("unknown command \(arguments[1])")
}
