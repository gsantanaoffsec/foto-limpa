import Foundation
import ImageIO
import CryptoKit

struct MetadataSnapshot: Codable {
    let fields: [String: String]
    let sha256: String
    let byteCount: Int
    let format: String
    let coverage: String
    let embeddedMetadataBlocks: [String: Int]
    var hasSensitiveMetadata: Bool {
        let groups = ["{Exif}", "{GPS}", "{IPTC}", "{TIFF}", "XMP/"]
        return !embeddedMetadataBlocks.isEmpty || fields.keys.contains { key in groups.contains { key.contains($0) } }
    }
}
struct MetadataChange: Identifiable, Encodable {
    let key: String
    let before: String?
    let after: String?
    var id: String { key }
    var status: String { before == after ? "Mantido" : before == nil ? "Adicionado" : after == nil ? "Removido" : "Alterado" }
    enum CodingKeys: String, CodingKey { case key, before, after, status }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(key, forKey: .key)
        try container.encode(before, forKey: .before)
        try container.encode(after, forKey: .after)
        try container.encode(status, forKey: .status)
    }
}
struct AuditReport: Encodable {
    let application = "Foto Limpa 1.1"
    let generatedAt: Date
    let passes: Int
    let limitations: String
    let before: MetadataSnapshot
    let after: MetadataSnapshot
    let changes: [MetadataChange]
}
enum MetadataAudit {
    static let limitations = "Leitura local de metadados e estrutura de arquivo, sem validação de assinatura C2PA. Não detecta nem remove SynthID ou outras marcas nos pixels, não consulta registros externos e não prevê o selo do Instagram. SHA-256 diferente não prova que uma imagem ficou irreconhecível."
    static func inspect(_ data: Data) throws -> MetadataSnapshot {
        guard data.count <= 250_000_000 else { throw CleanError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) else { throw CleanError.invalid }
        var fields: [String: String] = [:]
        flatten(properties, path: "Imagem", into: &fields)
        if let general = CGImageSourceCopyProperties(source, nil) {
            flatten(general, path: "Arquivo/Propriedades", into: &fields)
        }
        if let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) {
            CGImageMetadataEnumerateTagsUsingBlock(metadata, nil,
                [kCGImageMetadataEnumerateRecursively: true] as CFDictionary) { path, tag in
                if let value = CGImageMetadataTagCopyValue(tag) {
                    flatten(value, path: "XMP/" + (path as String), into: &fields)
                }
                return true
            }
        }
        let type = (CGImageSourceGetType(source) as String?) ?? "desconhecido"
        let structural = try scan(data, type: type)
        for (key, count) in structural.blocks { fields["Blocos/" + key] = "\(count)" }
        fields["Arquivo/Formato"] = type
        fields["Arquivo/Bytes"] = String(data.count)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        fields["Arquivo/SHA-256"] = hash
        return MetadataSnapshot(fields: fields, sha256: hash, byteCount: data.count,
            format: type, coverage: structural.coverage, embeddedMetadataBlocks: structural.blocks)
    }
    static func compare(_ before: MetadataSnapshot, _ after: MetadataSnapshot) -> [MetadataChange] {
        Set(before.fields.keys).union(after.fields.keys).sorted().map {
            MetadataChange(key: $0, before: before.fields[$0], after: after.fields[$0])
        }
    }
    static func report(before: MetadataSnapshot, after: MetadataSnapshot, passes: Int) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(AuditReport(generatedAt: Date(), passes: passes,
            limitations: limitations, before: before, after: after, changes: compare(before, after)))
    }
    private static func flatten(_ value: Any, path: String, into fields: inout [String: String]) {
        if let dict = value as? NSDictionary {
            for (key, child) in dict { flatten(child, path: path + "/" + String(describing: key), into: &fields) }
        } else if let list = value as? NSArray {
            for (index, child) in list.enumerated() { flatten(child, path: path + "/[\(index)]", into: &fields) }
        } else if let data = value as? Data {
            fields[path] = "Dado binário · \(data.count) bytes · SHA-256 " + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } else { fields[path] = String(describing: value) }
    }
    private static func scan(_ data: Data, type: String) throws -> (blocks: [String: Int], coverage: String) {
        let bytes = [UInt8](data)
        var blocks: [String: Int] = [:]
        func record(_ name: String) { blocks[name, default: 0] += 1 }
        if type == "public.jpeg" {
            guard bytes.count >= 4, bytes[0] == 0xff, bytes[1] == 0xd8 else { throw CleanError.invalid }
            var index = 2
            var inScan = false
            while index < bytes.count {
                if bytes[index] != 0xff {
                    guard inScan else { throw CleanError.invalid }
                    index += 1; continue
                }
                while index < bytes.count && bytes[index] == 0xff { index += 1 }
                guard index < bytes.count else { throw CleanError.invalid }
                let marker = bytes[index]; index += 1
                if marker == 0x00 { guard inScan else { throw CleanError.invalid }; continue }
                if marker == 0xd9 {
                    if index < bytes.count { blocks["Dados após o fim da imagem"] = bytes.count - index }
                    return (blocks, "JPEG: propriedades e XMP legíveis, segmentos e dados após EOI. APP11/JUMBF é um indício estrutural; assinaturas C2PA não são validadas.")
                }
                if (0xd0...0xd7).contains(marker) || marker == 0x01 { continue }
                guard index + 2 <= bytes.count else { throw CleanError.invalid }
                let length = Int(bytes[index]) * 256 + Int(bytes[index + 1])
                guard length >= 2, length <= bytes.count - index else { throw CleanError.invalid }
                if marker == 0xe1 {
                    let head = String(decoding: bytes[(index + 2)..<min(index + length, index + 90)], as: UTF8.self)
                    if head.hasPrefix("Exif") { record("EXIF") }
                    else if head.contains("adobe.com/xap") || head.contains("adobe.com/xmp") { record("XMP") }
                    else { record("APP1 adicional") }
                } else if marker == 0xed { record("APP13/IPTC ou Photoshop") }
                else if marker == 0xeb { record("APP11/JUMBF · possível C2PA") }
                else if marker == 0xfe { record("Comentários JPEG") }
                else if (0xe0...0xef).contains(marker) && marker != 0xe0 && marker != 0xe2 { record("APP adicional \(marker)") }
                else if marker == 0xe2 {
                    let prefix = Array("ICC_PROFILE\0".utf8)
                    if !bytes[(index + 2)..<(index + length)].starts(with: prefix) { record("APP2 adicional") }
                }
                if marker == 0xda { inScan = true }
                index += length
            }
            throw CleanError.invalid
        }
        if type == "public.png" {
            guard bytes.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw CleanError.invalid }
            var index = 8
            let allowed: Set<String> = ["IHDR", "PLTE", "IDAT", "IEND", "tRNS", "sRGB", "gAMA", "cHRM", "iCCP"]
            while index + 12 <= bytes.count {
                let length = bytes[index..<(index + 4)].reduce(0) { ($0 << 8) | Int($1) }
                guard length <= bytes.count - index - 12 else { throw CleanError.invalid }
                let name = String(bytes: bytes[(index + 4)..<(index + 8)], encoding: .ascii) ?? "????"
                if !allowed.contains(name) { record(name == "caBX" ? "caBX/C2PA" : "PNG/" + name) }
                index += length + 12
                if name == "IEND" {
                    if index < bytes.count { blocks["Dados após o fim da imagem"] = bytes.count - index }
                    return (blocks, "PNG: propriedades e XMP legíveis, blocos e dados após IEND. Assinaturas C2PA não são validadas.")
                }
            }
            throw CleanError.invalid
        }
        return (blocks, "Leitura parcial: propriedades e XMP disponíveis ao ImageIO. Blocos de procedência e estrutura deste formato não foram auditados; ausência de campos não significa ausência de C2PA.")
    }
}
