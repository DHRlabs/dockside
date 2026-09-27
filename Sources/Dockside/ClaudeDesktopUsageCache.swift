import Foundation
import Darwin

struct ClaudeResponse: Decodable, Sendable {
    let fiveHour: ClaudeWindow?
    let sevenDay: ClaudeWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct ClaudeWindow: Decodable, Sendable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ClaudeDesktopUsageCache: Sendable {
    struct Reading: Sendable {
        let response: ClaudeResponse
        let savedAt: Date
    }

    struct Scan: Sendable {
        let reading: Reading?
        let filesScanned: Int
    }

    static let defaultDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/Cache/Cache_Data",
                                isDirectory: true)

    static let headerBytes = 24
    static let maxEntryBytes = 512 * 1024
    static let maxEntriesExamined = 400
    static let maxKeyBytes = 8 * 1024
    static let maxDecompressedBytes = 256 * 1024

    private static let entryMagic: UInt64 = 0xfcfb_6d1b_a772_5c30
    private static let eofMagic: UInt64 = 0xf4fa_6f45_970d_41d8
    private static let zstdMagic: [UInt8] = [0x28, 0xb5, 0x2f, 0xfd]
    private static let eofBytes = 24
    private static let keySHA256Bytes = 32

    let directory: URL

    init(directory: URL = ClaudeDesktopUsageCache.defaultDirectory) {
        self.directory = directory
    }

    func read() -> Scan {
        let entries = recentEntries()
        for (index, entry) in entries.enumerated() {
            if let reading = reading(from: entry) {
                return Scan(reading: reading, filesScanned: index + 1)
            }
        }
        return Scan(reading: nil, filesScanned: entries.count)
    }

    private func recentEntries() -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        return files.compactMap { url -> (URL, Date)? in
            guard url.lastPathComponent.hasSuffix("_0"),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  size > Self.headerBytes, size <= Self.maxEntryBytes,
                  let modified = values.contentModificationDate
            else { return nil }
            return (url, modified)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(Self.maxEntriesExamined)
        .map(\.0)
    }

    private func reading(from entry: URL) -> Reading? {
        guard let handle = try? FileHandle(forReadingFrom: entry) else { return nil }
        defer { try? handle.close() }

        var originalInfo = stat()
        guard fstat(handle.fileDescriptor, &originalInfo) == 0,
              originalInfo.st_size >= off_t(Self.headerBytes),
              originalInfo.st_size <= off_t(Self.maxEntryBytes)
        else { return nil }

        // Read exactly the fixed header and its declared key; a short key must
        // never make this prefix read spill into an unrelated response body.
        guard let headerData = try? handle.read(upToCount: Self.headerBytes),
              headerData.count == Self.headerBytes,
              let keyLength = Self.keyLength(in: [UInt8](headerData)),
              let keyData = try? handle.read(upToCount: keyLength),
              keyData.count == keyLength,
              let key = String(bytes: keyData, encoding: .utf8),
              Self.isUsageEndpoint(key)
        else { return nil }

        let bodyStart = Self.headerBytes + keyLength
        do {
            try handle.seek(toOffset: UInt64(originalInfo.st_size - off_t(Self.eofBytes)))
        } catch {
            return nil
        }
        guard let eofData = try? handle.read(upToCount: Self.eofBytes),
              eofData.count == Self.eofBytes
        else { return nil }

        let eof = [UInt8](eofData)
        let flags = Self.readUInt32(eof, at: 8)
        let headerStreamSize = Int(Self.readUInt32(eof, at: 16))
        let hashSize = flags & 2 == 0 ? 0 : Self.keySHA256Bytes
        let bodyLength = Int(originalInfo.st_size) - bodyStart - 2 * Self.eofBytes
            - headerStreamSize - hashSize
        guard Self.readUInt64(eof, at: 0) == Self.eofMagic,
              flags & ~UInt32(3) == 0,
              Self.readUInt32(eof, at: 20) == 0
        else { return nil }
        let response: ClaudeResponse
        do {
            guard bodyLength > Self.zstdMagic.count,
                  bodyLength <= Self.maxEntryBytes,
                  (try? handle.seek(toOffset: UInt64(bodyStart))) != nil,
                  let data = try? handle.read(upToCount: bodyLength),
                  data.count == bodyLength
            else { return nil }

            let bytes = [UInt8](data)
            guard Array(bytes[..<Self.zstdMagic.count]) == Self.zstdMagic,
                  let body = ZstdDecoder.decompress(bytes),
                  let decoded = try? JSONDecoder().decode(ClaudeResponse.self, from: body)
            else { return nil }
            response = decoded
        }

        guard [response.fiveHour, response.sevenDay].contains(where: { window in
            guard let window, window.utilization.isFinite, let resetsAt = window.resetsAt else { return false }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return fractional.date(from: resetsAt) != nil || plain.date(from: resetsAt) != nil
        }) else { return nil }

        var finalInfo = stat()
        guard fstat(handle.fileDescriptor, &finalInfo) == 0,
              finalInfo.st_size == originalInfo.st_size,
              finalInfo.st_mtimespec.tv_sec == originalInfo.st_mtimespec.tv_sec,
              finalInfo.st_mtimespec.tv_nsec == originalInfo.st_mtimespec.tv_nsec,
              finalInfo.st_ctimespec.tv_sec == originalInfo.st_ctimespec.tv_sec,
              finalInfo.st_ctimespec.tv_nsec == originalInfo.st_ctimespec.tv_nsec
        else { return nil }
        let savedAt = Date(timeIntervalSince1970:
            TimeInterval(originalInfo.st_mtimespec.tv_sec)
            + TimeInterval(originalInfo.st_mtimespec.tv_nsec) / 1_000_000_000)
        return Reading(response: response, savedAt: savedAt)
    }

    private static func isUsageEndpoint(_ key: String) -> Bool {
        let prefix = "1/0/https://claude.ai/api/organizations/"
        guard key.hasPrefix(prefix) else { return false }
        let suffix = key.dropFirst(prefix.count)
        let path = suffix.prefix { $0 != "?" && $0 != "#" }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let remainder = suffix.dropFirst(path.count)
        return components.count == 2 && !components[0].isEmpty && components[1] == "usage"
            && (remainder.isEmpty || remainder.first == "?")
    }

    private static func keyLength(in header: [UInt8]) -> Int? {
        guard header.count == headerBytes, readUInt64(header, at: 0) == entryMagic else { return nil }
        let length = Int(readUInt32(header, at: 12))
        return length > 0 && length <= maxKeyBytes ? length : nil
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        for index in (0..<4).reversed() { value = value << 8 | UInt32(bytes[offset + index]) }
        return value
    }

    private static func readUInt64(_ bytes: [UInt8], at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        for index in (0..<8).reversed() { value = value << 8 | UInt64(bytes[offset + index]) }
        return value
    }
}

private enum ZstdDecoder {
    private typealias FindFrameSize = @convention(c) (UnsafeRawPointer?, Int) -> Int
    private typealias GetFrameContentSize = @convention(c) (UnsafeRawPointer?, Int) -> UInt64
    private typealias Decompress = @convention(c) (UnsafeMutableRawPointer?, Int, UnsafeRawPointer?, Int) -> Int
    private typealias IsError = @convention(c) (Int) -> UInt32

    private struct Functions: @unchecked Sendable {
        let library: UnsafeMutableRawPointer
        let findFrameSize: FindFrameSize
        let getFrameContentSize: GetFrameContentSize
        let decompress: Decompress
        let isError: IsError
    }

    // ponytail: use an already-installed zstd dylib; bundle a decoder if Dockside must run without it.
    private static let functions = loadFunctions()

    static func decompress(_ frame: [UInt8]) -> Data? {
        guard let functions, !frame.isEmpty else { return nil }
        return frame.withUnsafeBytes { source -> Data? in
            guard let pointer = source.baseAddress else { return nil }
            let frameSize = functions.findFrameSize(pointer, source.count)
            guard functions.isError(frameSize) == 0, frameSize > 0,
                  frameSize == source.count
            else { return nil }

            let declaredSize = functions.getFrameContentSize(pointer, frameSize)
            if declaredSize != UInt64.max, declaredSize != UInt64.max - 1,
               declaredSize > UInt64(ClaudeDesktopUsageCache.maxDecompressedBytes) {
                return nil
            }

            var output = [UInt8](repeating: 0, count: ClaudeDesktopUsageCache.maxDecompressedBytes)
            let written = output.withUnsafeMutableBytes { destination in
                functions.decompress(destination.baseAddress, destination.count, pointer, frameSize)
            }
            guard functions.isError(written) == 0, written > 0, written <= output.count else { return nil }
            return Data(output.prefix(written))
        }
    }

    private static func loadFunctions() -> Functions? {
        // Codenotch vendors a decoder because macOS has no system zstd library.
        // This reader reuses the one already installed on this Mac instead.
        let paths = [
            "/opt/homebrew/opt/zstd/lib/libzstd.1.dylib",
            "/opt/homebrew/lib/libzstd.1.dylib",
            "/usr/local/opt/zstd/lib/libzstd.1.dylib",
            "/usr/local/lib/libzstd.1.dylib"
        ]
        for path in paths {
            guard let library = path.withCString({ dlopen($0, RTLD_NOW | RTLD_LOCAL) }) else { continue }
            func symbol<T>(_ name: String, as type: T.Type) -> T? {
                guard let address = name.withCString({ dlsym(library, $0) }) else { return nil }
                return unsafeBitCast(address, to: type)
            }
            guard let findFrameSize = symbol("ZSTD_findFrameCompressedSize", as: FindFrameSize.self),
                  let getFrameContentSize = symbol("ZSTD_getFrameContentSize", as: GetFrameContentSize.self),
                  let decompress = symbol("ZSTD_decompress", as: Decompress.self),
                  let isError = symbol("ZSTD_isError", as: IsError.self)
            else {
                dlclose(library)
                continue
            }
            return Functions(library: library, findFrameSize: findFrameSize,
                             getFrameContentSize: getFrameContentSize,
                             decompress: decompress, isError: isError)
        }
        return nil
    }
}
