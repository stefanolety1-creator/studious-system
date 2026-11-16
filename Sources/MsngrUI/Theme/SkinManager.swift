import SwiftUI
import Foundation
import Compression
#if canImport(zlib)
import zlib
#endif

/// Primary `@MainActor` coordinator for application-wide theme, skin manifests, scenes, and palettes.
@MainActor
public final class SkinManager: ObservableObject {
    public static let shared = SkinManager()

    // MARK: - Published Properties

    @Published public private(set) var currentSkin: SkinConfig
    @Published public private(set) var currentScene: WlmScene
    @Published public var isDarkMode: Bool {
        didSet {
            colorPalette = currentSkin.resolvedColors(isDarkMode: isDarkMode)
        }
    }
    @Published public private(set) var colorPalette: SkinColors
    @Published public private(set) var availableSkins: [SkinConfig]

    // MARK: - Private Constants

    private let skinStorageKey = "msngr_selected_skin_id"
    private let sceneStorageKey = "msngr_selected_scene_id"

    // MARK: - Initialization

    public init(
        initialSkin: SkinConfig = .wlm2009,
        initialScene: WlmScene = .sky,
        isDarkMode: Bool = false
    ) {
        let skins = [SkinConfig.wlm2009, SkinConfig.msn75, SkinConfig.standard]
        self.availableSkins = skins

        let savedSkinId = UserDefaults.standard.string(forKey: skinStorageKey) ?? initialSkin.id
        let activeSkin = skins.first(where: { $0.id.lowercased() == savedSkinId.lowercased() }) ?? initialSkin
        self.currentSkin = activeSkin

        let savedSceneId = UserDefaults.standard.string(forKey: sceneStorageKey) ?? initialScene.id
        self.currentScene = WlmScene.fromId(savedSceneId)

        self.isDarkMode = isDarkMode
        self.colorPalette = activeSkin.resolvedColors(isDarkMode: isDarkMode)
    }

    // MARK: - Public Actions

    /// Switches the active skin by ID, falling back to WLM 2009 if ID is unknown.
    public func applySkin(id: String) {
        let target = availableSkins.first(where: { $0.id.lowercased() == id.lowercased() }) ?? .wlm2009
        self.currentSkin = target
        self.colorPalette = target.resolvedColors(isDarkMode: isDarkMode)
        UserDefaults.standard.set(target.id, forKey: skinStorageKey)
    }

    /// Sets the active header scene.
    public func setScene(_ scene: WlmScene) {
        self.currentScene = scene
        UserDefaults.standard.set(scene.id, forKey: sceneStorageKey)
    }

    /// Sets dark mode directly and refreshes the color palette.
    public func setDarkMode(_ isDark: Bool) {
        self.isDarkMode = isDark
    }

    /// Loads and registers a custom skin from a JSON or ZIP file URL.
    @discardableResult
    public func loadCustomSkin(from url: URL) throws -> SkinConfig {
        let data = try Data(contentsOf: url)

        // Try decoding directly as JSON
        if let decoded = try? JSONDecoder().decode(SkinConfig.self, from: data) {
            registerSkin(decoded)
            return decoded
        }

        // If not plain JSON, parse as ZIP container
        let extractedSkin = try extractSkinFromZip(url: url)
        registerSkin(extractedSkin)
        return extractedSkin
    }

    /// Registers a new skin config into available skins list and applies it.
    public func registerSkin(_ skin: SkinConfig) {
        if let idx = availableSkins.firstIndex(where: { $0.id.lowercased() == skin.id.lowercased() }) {
            availableSkins[idx] = skin
        } else {
            availableSkins.append(skin)
        }
        applySkin(id: skin.id)
    }

    /// Resets skin and scene back to default WLM 2009 Sky theme.
    public func resetToDefaults() {
        applySkin(id: SkinConfig.wlm2009.id)
        setScene(.sky)
        setDarkMode(false)
    }

    // MARK: - Private Helpers

    private func extractSkinFromZip(url: URL) throws -> SkinConfig {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let tempExtractDir = appSupport.appendingPathComponent("skins_temp_\(UUID().uuidString)")
        try fileManager.createDirectory(at: tempExtractDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempExtractDir) }

        let archiveData = try Data(contentsOf: url)

        // If the URL points directly to a raw JSON manifest, decode and return it
        if let directSkin = try? JSONDecoder().decode(SkinConfig.self, from: archiveData) {
            let directManifestUrl = tempExtractDir.appendingPathComponent("skin.json")
            try? archiveData.write(to: directManifestUrl)
            return directSkin
        }

        // Unpack and decompress PKZip archive entries into tempExtractDir
        try ZipArchiveExtractor.extractZip(data: archiveData, to: tempExtractDir)

        // Find skin.json inside the extracted folder
        var manifestUrl = tempExtractDir.appendingPathComponent("skin.json")
        if !fileManager.fileExists(atPath: manifestUrl.path) {
            // Search subdirectories if archive packaged skin.json inside a subfolder
            if let enumerator = fileManager.enumerator(at: tempExtractDir, includingPropertiesForKeys: nil) {
                for case let fileUrl as URL in enumerator where fileUrl.lastPathComponent.lowercased() == "skin.json" {
                    manifestUrl = fileUrl
                    break
                }
            }
        }

        guard fileManager.fileExists(atPath: manifestUrl.path) else {
            throw NSError(
                domain: "SkinManager",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "The archive does not contain a valid skin.json manifest."]
            )
        }

        let jsonData = try Data(contentsOf: manifestUrl)
        let skin = try JSONDecoder().decode(SkinConfig.self, from: jsonData)
        return skin
    }
}

// MARK: - PKZip Archive Extractor & DEFLATE Engine

/// Genuine PKZip (RFC 1951) archive extractor and DEFLATE decompressor.
/// Supports both Central Directory traversal and sequential Local File Header fallback parsing.
public struct ZipArchiveExtractor {

    public struct ZipEntry {
        public let path: String
        public let compressionMethod: UInt16
        public let compressedSize: Int
        public let uncompressedSize: Int
        public let isDirectory: Bool
        public let data: Data
    }

    /// Extracts all files and directories from a ZIP archive at `sourceUrl` into `destinationDir`.
    public static func extractZip(from sourceUrl: URL, to destinationDir: URL) throws {
        let archiveData = try Data(contentsOf: sourceUrl)
        try extractZip(data: archiveData, to: destinationDir)
    }

    /// Extracts all files and directories from ZIP archive bytes into `destinationDir`.
    public static func extractZip(data: Data, to destinationDir: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        let entries = try parseZipEntries(from: data)
        guard !entries.isEmpty else {
            throw NSError(
                domain: "ZipArchiveExtractor",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Archive contains no readable entries or is corrupt."]
            )
        }

        for entry in entries {
            let relativePath = entry.path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
            guard !relativePath.isEmpty else { continue }
            // Prevent zip slip directory traversal vulnerabilities
            guard !relativePath.contains("..") else { continue }

            let targetUrl = destinationDir.appendingPathComponent(relativePath)
            if entry.isDirectory {
                try fileManager.createDirectory(at: targetUrl, withIntermediateDirectories: true)
            } else {
                try fileManager.createDirectory(at: targetUrl.deletingLastPathComponent(), withIntermediateDirectories: true)
                try entry.data.write(to: targetUrl, options: .atomic)
            }
        }
    }

    /// Parses all entries from ZIP archive bytes, decompressing files as needed.
    public static func parseZipEntries(from data: Data) throws -> [ZipEntry] {
        // First try central directory parsing (standard for PKZip archives)
        if let cdEntries = try? parseFromCentralDirectory(data: data), !cdEntries.isEmpty {
            return cdEntries
        }

        // Fallback: parse sequentially via local file headers
        return try parseFromLocalHeaders(data: data)
    }

    // MARK: - Central Directory Parsing

    private static func parseFromCentralDirectory(data: Data) throws -> [ZipEntry]? {
        let count = data.count
        guard count >= 22 else { return nil }

        // Find End of Central Directory (EOCD) signature 0x06054B50
        var eocdOffset: Int?
        let minOffset = max(0, count - 65557)
        for i in stride(from: count - 22, through: minOffset, by: -1) {
            if readUInt32(data: data, offset: i) == 0x06054B50 {
                eocdOffset = i
                break
            }
        }

        guard let eocd = eocdOffset else { return nil }
        guard let totalEntries = readUInt16(data: data, offset: eocd + 10),
              let cdOffset = readUInt32(data: data, offset: eocd + 16),
              Int(cdOffset) < count else {
            return nil
        }

        var results: [ZipEntry] = []
        var offset = Int(cdOffset)

        for _ in 0..<totalEntries {
            guard offset + 46 <= count else { break }
            guard readUInt32(data: data, offset: offset) == 0x02014B50 else { break }

            guard let method = readUInt16(data: data, offset: offset + 10),
                  let compSize = readUInt32(data: data, offset: offset + 20),
                  let uncompSize = readUInt32(data: data, offset: offset + 24),
                  let fnLen = readUInt16(data: data, offset: offset + 28),
                  let exLen = readUInt16(data: data, offset: offset + 30),
                  let commLen = readUInt16(data: data, offset: offset + 32),
                  let localHeaderOffset = readUInt32(data: data, offset: offset + 42) else {
                break
            }

            let fnStart = offset + 46
            guard fnStart + Int(fnLen) <= count else { break }
            let fnBytes = data.subdata(in: fnStart..<(fnStart + Int(fnLen)))
            let filename = (String(data: fnBytes, encoding: .utf8) ?? String(data: fnBytes, encoding: .ascii) ?? "")
                .replacingOccurrences(of: "\\", with: "/")

            let nextCdOffset = offset + 46 + Int(fnLen) + Int(exLen) + Int(commLen)
            offset = nextCdOffset

            let isDir = filename.hasSuffix("/")
            if isDir {
                results.append(ZipEntry(
                    path: filename,
                    compressionMethod: method,
                    compressedSize: 0,
                    uncompressedSize: 0,
                    isDirectory: true,
                    data: Data()
                ))
                continue
            }

            // Read payload from local header
            let lhOffset = Int(localHeaderOffset)
            guard lhOffset + 30 <= count,
                  readUInt32(data: data, offset: lhOffset) == 0x04034B50,
                  let lhFnLen = readUInt16(data: data, offset: lhOffset + 26),
                  let lhExLen = readUInt16(data: data, offset: lhOffset + 28) else {
                continue
            }

            let dataStart = lhOffset + 30 + Int(lhFnLen) + Int(lhExLen)
            let cSize = Int(compSize)
            guard dataStart + cSize <= count else { continue }
            let compressedSlice = data.subdata(in: dataStart..<(dataStart + cSize))

            let decompressedData: Data
            if method == 0 { // Stored
                decompressedData = compressedSlice
            } else if method == 8 { // Deflated
                guard let decoded = decompressDeflate(compressedData: compressedSlice, uncompressedSize: Int(uncompSize)) else {
                    throw NSError(
                        domain: "ZipArchiveExtractor",
                        code: 422,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decompress entry: \(filename)"]
                    )
                }
                decompressedData = decoded
            } else {
                continue
            }

            results.append(ZipEntry(
                path: filename,
                compressionMethod: method,
                compressedSize: cSize,
                uncompressedSize: Int(uncompSize),
                isDirectory: false,
                data: decompressedData
            ))
        }

        return results
    }

    // MARK: - Local Headers Sequential Parsing

    private static func parseFromLocalHeaders(data: Data) throws -> [ZipEntry] {
        var results: [ZipEntry] = []
        var offset = 0
        let count = data.count

        while offset + 30 <= count {
            guard readUInt32(data: data, offset: offset) == 0x04034B50 else { break }

            guard let method = readUInt16(data: data, offset: offset + 8),
                  let compSize = readUInt32(data: data, offset: offset + 18),
                  let uncompSize = readUInt32(data: data, offset: offset + 22),
                  let fnLen = readUInt16(data: data, offset: offset + 26),
                  let exLen = readUInt16(data: data, offset: offset + 28) else {
                break
            }

            let fnStart = offset + 30
            guard fnStart + Int(fnLen) <= count else { break }
            let fnBytes = data.subdata(in: fnStart..<(fnStart + Int(fnLen)))
            let filename = (String(data: fnBytes, encoding: .utf8) ?? String(data: fnBytes, encoding: .ascii) ?? "")
                .replacingOccurrences(of: "\\", with: "/")

            let dataStart = fnStart + Int(fnLen) + Int(exLen)
            let cSize = Int(compSize)
            guard dataStart + cSize <= count else { break }
            let compressedSlice = data.subdata(in: dataStart..<(dataStart + cSize))
            offset = dataStart + cSize

            let isDir = filename.hasSuffix("/")
            if isDir {
                results.append(ZipEntry(
                    path: filename,
                    compressionMethod: method,
                    compressedSize: 0,
                    uncompressedSize: 0,
                    isDirectory: true,
                    data: Data()
                ))
                continue
            }

            let decompressedData: Data
            if method == 0 { // Stored
                decompressedData = compressedSlice
            } else if method == 8 { // Deflated
                guard let decoded = decompressDeflate(compressedData: compressedSlice, uncompressedSize: Int(uncompSize)) else {
                    throw NSError(
                        domain: "ZipArchiveExtractor",
                        code: 422,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decompress entry: \(filename)"]
                    )
                }
                decompressedData = decoded
            } else {
                continue
            }

            results.append(ZipEntry(
                path: filename,
                compressionMethod: method,
                compressedSize: cSize,
                uncompressedSize: Int(uncompSize),
                isDirectory: false,
                data: decompressedData
            ))
        }

        return results
    }

    // MARK: - DEFLATE Decompression Engine

    /// Decompresses raw DEFLATE bytes using Apple's Compression framework with zlib fallback.
    public static func decompressDeflate(compressedData: Data, uncompressedSize: Int) -> Data? {
        if uncompressedSize == 0 {
            return Data()
        }

        // 1. Apple Compression framework (COMPRESSION_ZLIB is raw DEFLATE per Apple specification)
        var destinationData = Data(count: uncompressedSize)
        let decodedSize = destinationData.withUnsafeMutableBytes { (dstBytes: UnsafeMutableRawBufferPointer) -> size_t in
            compressedData.withUnsafeBytes { (srcBytes: UnsafeRawBufferPointer) -> size_t in
                guard let dstPtr = dstBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let srcPtr = srcBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(
                    dstPtr,
                    uncompressedSize,
                    srcPtr,
                    compressedData.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        if decodedSize > 0 {
            if decodedSize < uncompressedSize {
                destinationData.count = decodedSize
            }
            return destinationData
        }

        // 2. Fallback: zlib raw deflate (windowBits = -15)
        #if canImport(zlib)
        var stream = z_stream()
        let initStatus = inflateInit2_(&stream, -15, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        if initStatus == Z_OK {
            defer { inflateEnd(&stream) }

            var outputData = Data(count: uncompressedSize)
            let success: Bool = compressedData.withUnsafeBytes { srcBuffer in
                outputData.withUnsafeMutableBytes { dstBuffer in
                    guard let srcPtr = srcBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self),
                          let dstPtr = dstBuffer.baseAddress?.assumingMemoryBound(to: Bytef.self) else {
                        return false
                    }
                    stream.next_in = UnsafeMutablePointer(mutating: srcPtr)
                    stream.avail_in = uInt(compressedData.count)
                    stream.next_out = dstPtr
                    stream.avail_out = uInt(uncompressedSize)

                    let status = inflate(&stream, Z_FINISH)
                    return status == Z_STREAM_END || status == Z_OK
                }
            }
            if success && stream.total_out > 0 {
                outputData.count = Int(stream.total_out)
                return outputData
            }
        }
        #endif

        return nil
    }

    // MARK: - Safe Alignment-Independent Little-Endian Binary Decoders

    private static func readUInt16(data: Data, offset: Int) -> UInt16? {
        guard offset + 2 <= data.count else { return nil }
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1])
        return b0 | (b1 << 8)
    }

    private static func readUInt32(data: Data, offset: Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}

// MARK: - SwiftUI Environment Integration

private struct SkinEnvironmentKey: EnvironmentKey {
    static let defaultValue: SkinConfig = .wlm2009
}

private struct SkinColorsEnvironmentKey: EnvironmentKey {
    static let defaultValue: SkinColors = SkinConfig.wlm2009.resolvedColors(isDarkMode: false)
}

private struct SkinManagerEnvironmentKey: EnvironmentKey {
    static let defaultValue: SkinManager? = nil
}

public extension EnvironmentValues {
    var currentSkin: SkinConfig {
        get { self[SkinEnvironmentKey.self] }
        set { self[SkinEnvironmentKey.self] = newValue }
    }

    var skinColors: SkinColors {
        get { self[SkinColorsEnvironmentKey.self] }
        set { self[SkinColorsEnvironmentKey.self] = newValue }
    }

    var skinManager: SkinManager? {
        get { self[SkinManagerEnvironmentKey.self] }
        set { self[SkinManagerEnvironmentKey.self] = newValue }
    }
}

@MainActor
public extension View {
    /// Injects `SkinManager` into the SwiftUI environment as an ObservableObject and environment values.
    func skinEnvironment(_ manager: SkinManager) -> some View {
        self
            .environmentObject(manager)
            .environment(\.skinManager, manager)
            .environment(\.currentSkin, manager.currentSkin)
            .environment(\.skinColors, manager.colorPalette)
    }

    /// Theme modifier alias providing skinManager and styling.
    func skinTheme(_ manager: SkinManager = .shared) -> some View {
        skinEnvironment(manager)
    }
}
