import Foundation

/// Represents a voice clip audio message and its waveform metadata.
public struct VoiceClipPayload: Hashable, Sendable {
    public static let msnObjectType = 11
    public static let targetWaveformBars = 40
    public static let maxDuration: TimeInterval = 30.0 // 30 seconds

    public let fileName: String
    public let fileSize: Int64
    public let duration: TimeInterval
    public let waveformLevels: [Float]

    public init(
        fileName: String,
        fileSize: Int64,
        duration: TimeInterval,
        waveformLevels: [Float]
    ) {
        self.fileName = fileName
        self.fileSize = fileSize
        self.duration = duration
        self.waveformLevels = waveformLevels
    }

    /// Determines if a file is an audio or voice clip based on filename pattern or audio extensions.
    public static func isAudioOrVoiceClip(fileName: String) -> Bool {
        let lower = fileName.lowercased()
        return lower.contains("voice_clip") ||
            lower.hasSuffix(".m4a") ||
            lower.hasSuffix(".mp3") ||
            lower.hasSuffix(".wav") ||
            lower.hasSuffix(".aac") ||
            lower.hasSuffix(".amr") ||
            lower.hasSuffix(".ogg")
    }

    /// Computes normalized speech level [0.0 ... 1.0] from signed 16-bit Little-Endian PCM data.
    public static func computeRmsLevel(pcm16LE: Data) -> Float {
        let samplesCount = (pcm16LE.count / 2)
        guard samplesCount > 0 else { return 0.0 }

        var energy: Double = 0.0
        pcm16LE.withUnsafeBytes { raw in
            let ptr = raw.bindMemory(to: Int16.self)
            for i in 0..<samplesCount {
                let sample = Double(Int16(littleEndian: ptr[i]))
                energy += sample * sample
            }
        }

        let rms = sqrt(energy / Double(samplesCount))
        let normalized = Float(rms / 8192.0)
        return min(max(normalized, 0.0), 1.0)
    }

    /// Resamples an arbitrary sequence of audio levels into exactly 40 discrete visual bars.
    public static func generateWaveform(levels: [Float], targetCount: Int = targetWaveformBars) -> [Float] {
        guard targetCount > 0 else { return [] }
        guard !levels.isEmpty else { return Array(repeating: 0.0, count: targetCount) }
        var result = [Float]()
        result.reserveCapacity(targetCount)
        for i in 0..<targetCount {
            let srcIndex = (i * levels.count) / targetCount
            let val = levels[min(srcIndex, levels.count - 1)]
            result.append(min(max(val, 0.0), 1.0))
        }
        return result
    }

    /// Resamples raw audio PCM or level data into discrete visual bars, guarding against non-positive targetCount.
    public static func resample(audioData: Data, targetCount: Int = targetWaveformBars) -> [Float] {
        guard targetCount > 0 else { return [] }
        let level = computeRmsLevel(pcm16LE: audioData)
        return generateWaveform(levels: [level], targetCount: targetCount)
    }

    /// Resamples audio levels with safe non-positive targetCount handling.
    public static func resample(levels: [Float], targetCount: Int = targetWaveformBars) -> [Float] {
        generateWaveform(levels: levels, targetCount: targetCount)
    }
}
