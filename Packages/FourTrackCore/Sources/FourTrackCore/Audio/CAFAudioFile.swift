import Foundation

/// Minimal Core Audio Format (CAF) reader and writer for mono linear PCM.
///
/// Track audio is stored as 48 kHz mono Float32 CAF, which AVAudioFile reads
/// natively. Owning the file I/O in the core package keeps the splice path
/// (the part that must never corrupt a take) testable on any platform.
public enum CAFFormat {
    public static let defaultSampleRate = 48_000.0
    /// Bytes before the first sample in files written by `CAFWriter`.
    static let headerSize: UInt64 = 8 + (12 + 32) + (12 + 4)
}

public enum CAFError: Error, Equatable, CustomStringConvertible {
    case notCAF
    case missingChunk(String)
    case unsupportedFormat(String)
    case io(String)

    public var description: String {
        switch self {
        case .notCAF: return "Not a CAF file"
        case .missingChunk(let c): return "CAF file is missing its '\(c)' chunk"
        case .unsupportedFormat(let f): return "Unsupported CAF format: \(f)"
        case .io(let m): return "File error: \(m)"
        }
    }
}

// MARK: - Writer

/// Streams Float32 mono samples into a CAF file. Call `finish()` to patch the
/// data chunk size; an unfinished file still reads correctly because the data
/// chunk is written with size -1 ("extends to end of file") until then.
public final class CAFWriter {
    public let url: URL
    public let sampleRate: Double
    public private(set) var framesWritten: Int64 = 0
    private var handle: FileHandle?

    public init(url: URL, sampleRate: Double = CAFFormat.defaultSampleRate) throws {
        self.url = url
        self.sampleRate = sampleRate
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw CAFError.io("Could not create \(url.lastPathComponent)")
        }
        handle = try FileHandle(forWritingTo: url)
        try handle?.write(contentsOf: CAFWriter.header(sampleRate: sampleRate, dataBytes: nil))
    }

    deinit {
        try? handle?.close()
    }

    static func header(sampleRate: Double, dataBytes: Int64?) -> Data {
        var d = Data()
        d.appendFourCC("caff")
        d.appendBE(UInt16(1)) // version
        d.appendBE(UInt16(0)) // flags

        d.appendFourCC("desc")
        d.appendBE(Int64(32))
        d.appendBE(sampleRate.bitPattern)
        d.appendFourCC("lpcm")
        d.appendBE(UInt32(1 | 2)) // kCAFLinearPCMFormatFlagIsFloat | IsLittleEndian
        d.appendBE(UInt32(4)) // bytes per packet
        d.appendBE(UInt32(1)) // frames per packet
        d.appendBE(UInt32(1)) // channels
        d.appendBE(UInt32(32)) // bits per channel

        d.appendFourCC("data")
        if let dataBytes {
            d.appendBE(dataBytes + 4) // includes edit count
        } else {
            d.appendBE(Int64(-1))
        }
        d.appendBE(UInt32(0)) // edit count
        return d
    }

    public func write(_ samples: UnsafeBufferPointer<Float>) throws {
        guard let handle else { throw CAFError.io("Writer is closed") }
        guard samples.count > 0, let base = samples.baseAddress else { return }
        var data = Data(count: samples.count * 4)
        data.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt32.self)
            for i in 0..<samples.count {
                out[i] = base[i].bitPattern.littleEndian
            }
        }
        try handle.write(contentsOf: data)
        framesWritten += Int64(samples.count)
    }

    public func write(_ samples: [Float]) throws {
        try samples.withUnsafeBufferPointer { try write($0) }
    }

    /// Patches the header with the final size, flushes to disk and closes.
    public func finish() throws {
        guard let handle else { return }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: CAFWriter.header(sampleRate: sampleRate, dataBytes: framesWritten * 4))
        try handle.synchronize()
        try handle.close()
        self.handle = nil
    }
}

// MARK: - Reader

/// Random-access reader for mono linear PCM CAF files (Float32/64, Int16/24/32).
public final class CAFReader {
    public let url: URL
    public let sampleRate: Double
    public let frameCount: Int64
    public let channelCount: Int

    private let handle: FileHandle
    private let dataOffset: UInt64
    private let bytesPerFrame: Int
    private let bitsPerChannel: Int
    private let isFloat: Bool
    private let isLittleEndian: Bool

    public var durationSeconds: Double { Double(frameCount) / sampleRate }

    public init(url: URL) throws {
        self.url = url
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw CAFError.io("Could not open \(url.lastPathComponent)")
        }
        let fileSize = try handle.seekToEnd()
        try handle.seek(toOffset: 0)

        guard let head = try handle.read(upToCount: 8), head.count == 8, head.fourCC(at: 0) == "caff" else {
            throw CAFError.notCAF
        }

        var offset: UInt64 = 8
        var desc: Data?
        var dataStart: UInt64?
        var dataSize: Int64 = -1
        while offset + 12 <= fileSize {
            try handle.seek(toOffset: offset)
            guard let chunkHead = try handle.read(upToCount: 12), chunkHead.count == 12 else { break }
            let type = chunkHead.fourCC(at: 0)
            let size = Int64(bitPattern: chunkHead.readBE(UInt64.self, at: 4))
            let bodyStart = offset + 12
            if type == "desc" {
                desc = try handle.read(upToCount: 32)
            } else if type == "data" {
                dataStart = bodyStart + 4 // skip edit count
                dataSize = size
                if size < 0 { break }
            }
            if size < 0 { break }
            offset = bodyStart + UInt64(size)
        }

        guard let desc, desc.count == 32 else { throw CAFError.missingChunk("desc") }
        guard let dataStart else { throw CAFError.missingChunk("data") }

        sampleRate = Double(bitPattern: desc.readBE(UInt64.self, at: 0))
        let formatID = desc.fourCC(at: 8)
        let flags = desc.readBE(UInt32.self, at: 12)
        let bytesPerPacket = Int(desc.readBE(UInt32.self, at: 16))
        let framesPerPacket = Int(desc.readBE(UInt32.self, at: 20))
        channelCount = Int(desc.readBE(UInt32.self, at: 24))
        bitsPerChannel = Int(desc.readBE(UInt32.self, at: 28))

        guard formatID == "lpcm" else { throw CAFError.unsupportedFormat(formatID) }
        guard framesPerPacket == 1, channelCount >= 1, bytesPerPacket == channelCount * bitsPerChannel / 8 else {
            throw CAFError.unsupportedFormat("packet layout")
        }
        isFloat = flags & 1 != 0
        isLittleEndian = flags & 2 != 0
        switch (isFloat, bitsPerChannel) {
        case (true, 32), (true, 64), (false, 16), (false, 24), (false, 32): break
        default: throw CAFError.unsupportedFormat("\(bitsPerChannel)-bit \(isFloat ? "float" : "int")")
        }
        bytesPerFrame = bytesPerPacket
        dataOffset = dataStart

        let available = Int64(fileSize) - Int64(dataStart)
        let declared = dataSize < 0 ? available : min(available, dataSize - 4)
        frameCount = max(0, declared) / Int64(bytesPerFrame)
    }

    deinit {
        try? handle.close()
    }

    /// Reads `count` frames starting at `start`, downmixed to mono. Frames outside
    /// the file are returned as silence, so callers can treat every track as
    /// infinitely long.
    public func read(from start: Int64, count: Int) throws -> [Float] {
        var out = [Float](repeating: 0, count: max(0, count))
        guard count > 0 else { return out }
        let readStart = max(start, 0)
        let readEnd = min(start + Int64(count), frameCount)
        guard readEnd > readStart else { return out }
        let n = Int(readEnd - readStart)
        try handle.seek(toOffset: dataOffset + UInt64(readStart) * UInt64(bytesPerFrame))
        guard let bytes = try handle.read(upToCount: n * bytesPerFrame) else { return out }
        let framesRead = bytes.count / bytesPerFrame
        let dest = Int(readStart - start)
        let bytesPerSample = bitsPerChannel / 8
        let channels = channelCount
        let scale = 1 / Float(channels)
        bytes.withUnsafeBytes { raw in
            for f in 0..<framesRead {
                var acc: Float = 0
                for ch in 0..<channels {
                    let o = f * bytesPerFrame + ch * bytesPerSample
                    acc += decodeSample(raw, at: o)
                }
                out[dest + f] = channels == 1 ? acc : acc * scale
            }
        }
        return out
    }

    @inline(__always)
    private func decodeSample(_ raw: UnsafeRawBufferPointer, at o: Int) -> Float {
        func u(_ i: Int) -> UInt32 { UInt32(raw[o + i]) }
        switch (isFloat, bitsPerChannel) {
        case (true, 32):
            let bits = isLittleEndian
                ? u(0) | u(1) << 8 | u(2) << 16 | u(3) << 24
                : u(3) | u(2) << 8 | u(1) << 16 | u(0) << 24
            return Float(bitPattern: bits)
        case (true, 64):
            var bits: UInt64 = 0
            for i in 0..<8 {
                let byte = UInt64(raw[o + (isLittleEndian ? i : 7 - i)])
                bits |= byte << (8 * UInt64(i))
            }
            return Float(Double(bitPattern: bits))
        case (false, 16):
            let bits = isLittleEndian ? u(0) | u(1) << 8 : u(1) | u(0) << 8
            return Float(Int16(truncatingIfNeeded: bits)) / 32_768
        case (false, 24):
            let bits = isLittleEndian ? u(0) << 8 | u(1) << 16 | u(2) << 24 : u(2) << 8 | u(1) << 16 | u(0) << 24
            return Float(Int32(bitPattern: bits) >> 8) / 8_388_608
        default:
            let bits = isLittleEndian
                ? u(0) | u(1) << 8 | u(2) << 16 | u(3) << 24
                : u(3) | u(2) << 8 | u(1) << 16 | u(0) << 24
            return Float(Double(Int32(bitPattern: bits)) / 2_147_483_648)
        }
    }

    /// Convenience: whole file as one array. Only for tests and short files.
    public func readAll() throws -> [Float] {
        try read(from: 0, count: Int(frameCount))
    }
}

// MARK: - Atomic replace

public enum AtomicFile {
    /// Atomically moves `source` over `destination` (rename(2) semantics). Both
    /// must be on the same volume, which holds for files in one project folder.
    public static func replace(_ destination: URL, with source: URL) throws {
        if rename(source.path, destination.path) != 0 {
            throw CAFError.io("rename failed (\(errno)) for \(destination.lastPathComponent)")
        }
    }
}

// MARK: - Byte helpers

extension Data {
    mutating func appendFourCC(_ s: String) {
        append(contentsOf: Array(s.utf8.prefix(4)))
    }

    mutating func appendBE<T: FixedWidthInteger>(_ v: T) {
        var be = v.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    func fourCC(at offset: Int) -> String {
        let start = startIndex + offset
        return String(decoding: self[start..<start + 4], as: UTF8.self)
    }

    func readBE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var v: T = 0
        let start = startIndex + offset
        for i in 0..<MemoryLayout<T>.size {
            v = v << 8 | T(self[start + i])
        }
        return v
    }
}
