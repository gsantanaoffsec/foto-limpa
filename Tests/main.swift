import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { print("FAIL: \(message)"); exit(1) }
}
func fixture(_ type: UTType = .jpeg, orientation: Int = 6, frames: Int = 1) -> Data {
    let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.5))
    context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
    let out = NSMutableData()
    let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, frames, nil)!
    for _ in 0..<frames {
        CGImageDestinationAddImage(dest, context.makeImage()!, [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "secret-ai-editor"],
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 23.5, kCGImagePropertyGPSLatitudeRef: "S"],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCaptionAbstract: "secret-caption"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: "secret-editor"]
        ] as CFDictionary)
    }
    expect(CGImageDestinationFinalize(dest), "fixture creation")
    return out as Data
}
let source = fixture()
let props = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(source as CFData, nil)!, 0, nil)! as NSDictionary
expect(props[kCGImagePropertyGPSDictionary] != nil, "fixture has GPS")
for format in OutputFormat.allCases {
    let result = try PhotoCleaner.clean(source, format: format)
    let imageSource = CGImageSourceCreateWithData(result.data as CFData, nil)!
    let p = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)! as NSDictionary
    expect(p[kCGImagePropertyGPSDictionary] == nil, "GPS removed from \(format)")
    expect(p[kCGImagePropertyIPTCDictionary] == nil, "IPTC removed")
    expect(p[kCGImagePropertyExifDictionary] == nil, "EXIF removed")
    expect(result.width == 20 && result.height == 40, "orientation baked into dimensions")
    expect((p[kCGImagePropertyPixelWidth] as? Int) == 20, "encoded dimensions")
    expect(!String(decoding: result.data, as: UTF8.self).contains("secret-"), "metadata strings removed")
    expect(CGImageSourceGetType(imageSource)! as String == format.type.identifier, "correct encoding")
    print("PASS: \(format) removes metadata and preserves orientation")
}
let alphaResult = try PhotoCleaner.clean(fixture(.png, orientation: 1), format: .png)
let alphaSource = CGImageSourceCreateWithData(alphaResult.data as CFData, nil)!
let alphaImage = CGImageSourceCreateImageAtIndex(alphaSource, 0, nil)!
let alphaBytes = alphaImage.dataProvider!.data! as Data
expect(alphaBytes.contains(where: { $0 > 100 && $0 < 150 }), "semi transparency preserved")
print("PASS: PNG alpha")
do { _ = try PhotoCleaner.clean(Data("bad file".utf8), format: .jpeg); expect(false, "invalid rejected") } catch { print("PASS: invalid file rejected") }
do { _ = try PhotoCleaner.clean(fixture(.gif, frames: 2), format: .jpeg); expect(false, "animated rejected") } catch { print("PASS: multiple frames rejected") }
print("ALL TESTS PASSED")
let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temp) }
let originalURL = temp.appendingPathComponent("original.jpg")
try source.write(to: originalURL)
let ready = try PhotoCleaner.clean(source, format: .jpeg)
do { try PhotoCleaner.save(ready, to: originalURL, original: originalURL); expect(false, "original protected") } catch { print("PASS: original cannot be overwritten") }
let symlink = temp.appendingPathComponent("alias.jpg")
try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: originalURL)
do { try PhotoCleaner.save(ready, to: symlink, original: originalURL); expect(false, "symlink protected") } catch { print("PASS: symlink cannot overwrite original") }
let copyURL = temp.appendingPathComponent("copy.jpg")
try PhotoCleaner.save(ready, to: copyURL, original: originalURL)
expect(try! Data(contentsOf: originalURL) == source, "source bytes unchanged")
expect(try! Data(contentsOf: copyURL) == ready.data, "copy written")
print("PASS: saves copy while preserving original")
// A synthetic APP11 block tests preservation isolation, not C2PA signature validation.
var tagged = Data(source.prefix(2))
let payload = Array("JP-secret-c2pa-jumbf".utf8)
tagged.append(contentsOf: [0xff, 0xeb, 0, UInt8(payload.count + 2)])
tagged.append(contentsOf: payload)
tagged.append(source.dropFirst(2))
let sanitized = try PhotoCleaner.clean(tagged, format: .jpeg)
expect(!String(decoding: sanitized.data, as: UTF8.self).contains("secret-c2pa"), "APP11 source block removed")
print("PASS: source APP11 metadata block not copied")
if let fixturePath = ProcessInfo.processInfo.environment["FOTO_LIMPA_FIXTURE"] { try source.write(to: URL(fileURLWithPath: fixturePath)) }
print("FULL SUITE PASSED")
let beforeAudit = try MetadataAudit.inspect(source)
expect(beforeAudit.fields.keys.contains(where: { $0.contains("GPS") }), "audit shows GPS values before")
expect(beforeAudit.sha256.count == 64, "audit computes SHA-256")
let afterAudit = try MetadataAudit.inspect(ready.data)
let changes = MetadataAudit.compare(beforeAudit, afterAudit)
expect(changes.contains(where: { $0.key.contains("GPS") && $0.status == "Removido" }), "comparison marks removed GPS")
expect(changes.contains(where: { $0.status == "Alterado" }), "comparison shows changed dimensions")
expect(beforeAudit.sha256 != afterAudit.sha256, "before and after hashes differ")
expect(!afterAudit.fields.values.contains(where: { $0.contains("secret-") }), "audit output has no private marker")
print("PASS: metadata audit and comparison")
let repeated = try PhotoCleaner.process(source, format: .jpeg, passes: 3)
expect(repeated.passes == 3, "three processing passes executed")
expect(repeated.width == 20 && repeated.height == 40, "repeated processing retains orientation")
expect(!(try! MetadataAudit.inspect(repeated.data)).hasSensitiveMetadata, "repeated result has no audited metadata")
for count in [0, 6] {
    do { _ = try PhotoCleaner.process(source, format: .png, passes: count); expect(false, "invalid pass count rejected") }
    catch { print("PASS: invalid pass count \(count) rejected") }
}
let decodedReport = try JSONSerialization.jsonObject(with: MetadataAudit.report(before: beforeAudit, after: afterAudit, passes: 3)) as! [String: Any]
expect(decodedReport["passes"] as? Int == 3, "report records pass count")
expect(decodedReport["limitations"] as? String != nil, "report includes inspection limitations")
print("PASS: pass count and audit report")
var withTrailing = source
withTrailing.append(Data("secret-trailing-note".utf8))
expect((try! MetadataAudit.inspect(withTrailing)).embeddedMetadataBlocks["Dados após o fim da imagem"] != nil, "detect trailing data")
expect(!(try! MetadataAudit.inspect(try! PhotoCleaner.clean(withTrailing, format: .png).data)).hasSensitiveMetadata, "trailing data discarded")
expect((try! MetadataAudit.inspect(tagged)).embeddedMetadataBlocks["APP11/JUMBF · possível C2PA"] != nil, "APP11 detected without claiming signature validation")
print("PASS: structural metadata inspection")
let reportChanges = decodedReport["changes"] as! [[String: Any]]
expect(reportChanges.contains(where: { $0["status"] as? String == "Removido" }), "exported report includes explicit change status")
let pngFive = try PhotoCleaner.process(fixture(.png, orientation: 1), format: .png, passes: 5)
expect(pngFive.passes == 5 && pngFive.width == 40 && pngFive.height == 20, "five PNG passes preserve dimensions")
expect(!(try! MetadataAudit.inspect(pngFive.data)).hasSensitiveMetadata, "five PNG passes verified")
print("PASS: five PNG passes")
func pngChunk(_ name: String, _ payload: Data) -> Data {
    var out = Data()
    let size = UInt32(payload.count)
    out.append(contentsOf: [UInt8((size >> 24) & 255), UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255)])
    var content = Data(name.utf8); content.append(payload)
    var crc: UInt32 = 0xffffffff
    for byte in content { crc ^= UInt32(byte); for _ in 0..<8 { crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0) } }
    crc ^= 0xffffffff
    out.append(content)
    out.append(contentsOf: [UInt8((crc >> 24) & 255), UInt8((crc >> 16) & 255), UInt8((crc >> 8) & 255), UInt8(crc & 255)])
    return out
}
let plainPNG = fixture(.png, orientation: 1)
var taggedPNG = Data(plainPNG.prefix(33))
taggedPNG.append(pngChunk("tEXt", Data("Comment\0secret-png-comment".utf8)))
taggedPNG.append(pngChunk("caBX", Data("synthetic-c2pa-block-not-a-signed-manifest".utf8)))
taggedPNG.append(plainPNG.dropFirst(33))
let pngAudit = try MetadataAudit.inspect(taggedPNG)
expect(pngAudit.embeddedMetadataBlocks["PNG/tEXt"] == 1, "PNG text block detected")
expect(pngAudit.embeddedMetadataBlocks["caBX/C2PA"] == 1, "PNG caBX block detected structurally")
let pngStripped = try PhotoCleaner.clean(taggedPNG, format: .png)
expect(!(try! MetadataAudit.inspect(pngStripped.data)).hasSensitiveMetadata, "PNG extra chunks removed")
expect(!String(decoding: pngStripped.data, as: UTF8.self).contains("secret-png"), "PNG comment content removed")
print("PASS: PNG text and caBX metadata blocks")
print("VERSION 1.1 SUITE PASSED")
