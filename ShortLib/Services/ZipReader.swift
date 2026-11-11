import Foundation
import Compression

/// Минимальный читатель ZIP-архивов (EPUB — это ZIP).
/// Поддерживает методы 0 (stored) и 8 (deflate) — этого достаточно для EPUB.
struct ZipReader {
    enum ZipError: LocalizedError {
        case notZip, unsupportedMethod(UInt16), corrupted, missing(String)

        var errorDescription: String? {
            switch self {
            case .notZip: return "Файл не похож на EPUB: это не ZIP-архив."
            case .unsupportedMethod(let m): return "Формат сжатия \(m) не поддерживается."
            case .corrupted: return "Файл повреждён. Попробуйте скачать его заново."
            case .missing(let path): return "В книге нет файла \(path)."
            }
        }
    }

    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let archive: Data
    private var entries: [String: Entry] = [:]

    init(url: URL) throws {
        archive = try Data(contentsOf: url, options: .mappedIfSafe)
        try readCentralDirectory()
    }

    var paths: [String] { Array(entries.keys) }

    func contains(_ path: String) -> Bool { entries[path] != nil }

    func data(at path: String) throws -> Data {
        guard let e = entries[path] else { throw ZipError.missing(path) }
        guard archive.count >= e.localHeaderOffset + 30, u32(e.localHeaderOffset) == 0x04034b50 else { throw ZipError.corrupted }
        let nameLen = Int(u16(e.localHeaderOffset + 26))
        let extraLen = Int(u16(e.localHeaderOffset + 28))
        let start = e.localHeaderOffset + 30 + nameLen + extraLen
        guard start + e.compressedSize <= archive.count else { throw ZipError.corrupted }
        let compressed = archive.subdata(in: start..<(start + e.compressedSize))

        switch e.method {
        case 0:
            return compressed
        case 8:
            return try inflate(compressed, expectedSize: e.uncompressedSize)
        default:
            throw ZipError.unsupportedMethod(e.method)
        }
    }

    // MARK: - Private

    private mutating func readCentralDirectory() throws {
        // End of central directory: сигнатура 0x06054b50, ищем с конца.
        guard archive.count >= 22 else { throw ZipError.notZip }
        var eocd = -1
        let lower = max(0, archive.count - 65_557)
        var i = archive.count - 22
        while i >= lower {
            if u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notZip }

        let count = Int(u16(eocd + 10))
        var offset = Int(u32(eocd + 16))

        for _ in 0..<count {
            guard offset + 46 <= archive.count, u32(offset) == 0x02014b50 else { throw ZipError.corrupted }
            let method = u16(offset + 10)
            let compSize = Int(u32(offset + 20))
            let uncompSize = Int(u32(offset + 24))
            let nameLen = Int(u16(offset + 28))
            let extraLen = Int(u16(offset + 30))
            let commentLen = Int(u16(offset + 32))
            let localOffset = Int(u32(offset + 42))
            let nameData = archive.subdata(in: (offset + 46)..<(offset + 46 + nameLen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            entries[name] = Entry(method: method, compressedSize: compSize,
                                  uncompressedSize: uncompSize, localHeaderOffset: localOffset)
            offset += 46 + nameLen + extraLen + commentLen
        }
    }

    private func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        // COMPRESSION_ZLIB в Apple Compression — это «сырой» DEFLATE, как в ZIP.
        let capacity = max(expectedSize, 1)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let d = dst.bindMemory(to: UInt8.self).baseAddress,
                      let s = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(d, capacity, s, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 || expectedSize == 0 else { throw ZipError.corrupted }
        output.count = written
        return output
    }

    private func u16(_ at: Int) -> UInt16 {
        UInt16(archive[archive.startIndex + at]) | UInt16(archive[archive.startIndex + at + 1]) << 8
    }

    private func u32(_ at: Int) -> UInt32 {
        UInt32(u16(at)) | UInt32(u16(at + 2)) << 16
    }
}
