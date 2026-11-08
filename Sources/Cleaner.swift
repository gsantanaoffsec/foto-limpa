import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

enum OutputFormat: String, CaseIterable { case jpeg = "JPEG", png = "PNG"
    var ext: String { self == .jpeg ? "jpg" : "png" }
    var type: UTType { self == .jpeg ? .jpeg : .png }
}
struct CleanResult { let data: Data; let width: Int; let height: Int; var passes: Int = 1 }
enum CleanError: LocalizedError {
    case invalid, multipleFrames, tooLarge, encode, verification, original, invalidPasses
    var errorDescription: String? {
        switch self {
        case .invalid: return "Não foi possível ler esta foto. Escolha um JPEG, PNG, HEIC ou TIFF válido."
        case .multipleFrames: return "O arquivo contém várias imagens ou uma animação. Exporte uma foto estática primeiro."
        case .tooLarge: return "Esta foto ultrapassa o limite de 100 megapixels ou 250 MB."
        case .encode: return "Não foi possível gerar a cópia."
        case .verification: return "O arquivo não passou na verificação. Não use a cópia se ela tiver sido salva."
        case .invalidPasses: return "Escolha de 1 a 5 passagens."
        case .original: return "Escolha outro nome ou outra pasta para preservar a foto original."
        }
    }
}
enum PhotoCleaner {
    static func process(_ data: Data, format: OutputFormat, passes: Int) throws -> CleanResult {
        guard (1...5).contains(passes) else { throw CleanError.invalidPasses }
        var current = data
        var result: CleanResult?
        for pass in 1...passes {
            var next = try autoreleasepool { try clean(current, format: format) }
            next.passes = pass
            current = next.data
            result = next
        }
        return result!
    }
    static func clean(_ data: Data, format: OutputFormat) throws -> CleanResult {
        guard data.count <= 250_000_000 else { throw CleanError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw CleanError.invalid }
        guard CGImageSourceGetCount(source) == 1 else { throw CleanError.multipleFrames }
        guard width <= 100_000_000 / height else { throw CleanError.tooLarge }
        // A fresh raster carries pixels, never the source container's metadata or manifests.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height),
            kCGImageSourceShouldCacheImmediately: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CleanError.invalid }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        if format == .jpeg {
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(rect)
        }
        context.draw(image, in: rect)
        guard let raster = context.makeImage() else { throw CleanError.encode }
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output, format.type.identifier as CFString, 1, nil) else { throw CleanError.encode }
        let settings: [CFString: Any] = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.95] : [:]
        CGImageDestinationAddImage(dest, raster, settings as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw CleanError.encode }
        let bytes = try stripContainerMetadata(output as Data, format: format)
        guard let check = CGImageSourceCreateWithData(bytes as CFData, nil),
              let fields = CGImageSourceCopyPropertiesAtIndex(check, 0, nil) as? [CFString: Any] else { throw CleanError.verification }
        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
                    kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary] {
            if fields[key] != nil { throw CleanError.verification }
        }
        // Since ImageIO generates this file from a fresh CGImage, it does not copy
        // unknown source blocks (XMP, APP11/JUMBF, caBX, text chunks, or trailing data).
        guard !(try MetadataAudit.inspect(bytes)).hasSensitiveMetadata else { throw CleanError.verification }
        return CleanResult(data: bytes, width: raster.width, height: raster.height)
    }
    private static func stripContainerMetadata(_ data: Data, format: OutputFormat) throws -> Data {
        let bytes = [UInt8](data)
        if format == .jpeg {
            guard bytes.count > 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { throw CleanError.encode }
            var out = Data(bytes[0..<2])
            var index = 2
            while index + 3 < bytes.count {
                guard bytes[index] == 0xff else { throw CleanError.encode }
                let marker = bytes[index + 1]
                if marker == 0xda { out.append(contentsOf: bytes[index...]); return out }
                let length = Int(bytes[index + 2]) * 256 + Int(bytes[index + 3])
                guard length >= 2, index + 2 + length <= bytes.count else { throw CleanError.encode }
                let appOrComment = (0xe0...0xef).contains(marker) || marker == 0xfe
                // Keep only JFIF and generic ICC profile; drop EXIF, XMP, IPTC, JUMBF and comments.
                if !appOrComment || marker == 0xe0 || marker == 0xe2 {
                    out.append(contentsOf: bytes[index..<(index + 2 + length)])
                }
                index += 2 + length
            }
            throw CleanError.encode
        }
        guard bytes.count >= 8 else { throw CleanError.encode }
        var out = Data(bytes[0..<8])
        var index = 8
        let allowed: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "tRNS", "sRGB", "gAMA", "cHRM", "iCCP"]
        while index + 12 <= bytes.count {
            let length = bytes[index..<(index + 4)].reduce(0) { ($0 << 8) | Int($1) }
            guard length <= bytes.count - index - 12 else { throw CleanError.encode }
            let name = String(bytes: bytes[(index + 4)..<(index + 8)], encoding: .ascii) ?? ""
            if allowed.contains(name) { out.append(contentsOf: bytes[index..<(index + length + 12)]) }
            index += length + 12
            if name == "IEND" { return out }
        }
        throw CleanError.encode
    }
    static func save(_ result: CleanResult, to destination: URL, original: URL) throws {
        let src = original.resolvingSymlinksInPath().standardizedFileURL
        let dst = destination.resolvingSymlinksInPath().standardizedFileURL
        guard src != dst else { throw CleanError.original }
        if let a = try? original.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
           let b = try? destination.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
           (a as? NSObject)?.isEqual(b) == true { throw CleanError.original }
        try result.data.write(to: destination, options: .atomic)
        let written = try Data(contentsOf: destination)
        guard written == result.data, !(try MetadataAudit.inspect(written)).hasSensitiveMetadata else { throw CleanError.verification }
    }
}
