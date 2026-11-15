import Foundation

/// Linear color gradient interpolation engine matching Messenger Plus! 5.02.712 arithmetic.
public enum ColorGradientEngine {
    /// Linearly interpolate between start and end ARGB colors across UTF-16 code unit positions.
    public static func interpolate(start: UInt32, end: UInt32, index: Int, count: Int) -> UInt32 {
        if count <= 1 { return start }
        let clampedIndex = min(max(0, index), count - 1)
        let ratio = Float(clampedIndex) / Float(count - 1)

        func channel(shift: Int) -> UInt32 {
            let startVal = Float((start >> shift) & 0xFF)
            let endVal = Float((end >> shift) & 0xFF)
            // Truncation toward zero matches native Windows Plus! (.toInt())
            let interpolated = startVal + (endVal - startVal) * ratio
            return (UInt32(interpolated) & 0xFF) << shift
        }

        return channel(24) | channel(16) | channel(8) | channel(0)
    }

    /// Generate gradient wire token string: `[tag=startColor]text[/tag=endColor]`.
    public static func formatGradient(
        text: String,
        startColor: MessengerPlusColorValue,
        endColor: MessengerPlusColorValue,
        isBackground: Bool = false
    ) -> String {
        let tag = isBackground ? "a" : "c"
        return "[\(tag)=\(startColor.wireToken)]\(text)[/\(tag)=\(endColor.wireToken)]"
    }
}
