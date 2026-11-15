import SwiftUI

/// Authentic Windows Live Messenger 2009 Nudge window-shake engine.
///
/// Replicates the exact 13-step displacement delta table extracted from `msnmsgr.exe` (14.0.8117.0416 at `0x00430DA0`):
/// 4 cycles × 13 steps = 52 ticks at 20 ms per step (`1,040 ms` total duration).
@MainActor
public final class NudgeShakeEngine: ObservableObject {
    @Published public private(set) var offsetX: CGFloat = 0
    @Published public private(set) var offsetY: CGFloat = 0
    @Published public private(set) var isShaking: Bool = false

    /// Exact 13-step displacement deltas per cycle (summing to `(0, 0)`).
    public static let wlmNudgeDeltas: [(x: CGFloat, y: CGFloat)] = [
        (4, 3),
        (-3, -6),
        (-3, 4),
        (2, 2),
        (-3, -5),
        (5, 5),
        (-3, -6),
        (-3, 6),
        (-1, -3),
        (6, -1),
        (-3, 4),
        (6, -6),
        (-4, 3)
    ]

    /// Step interval in milliseconds (20 ms).
    public static let stepIntervalMs: Int = 20

    /// Number of full cycles per nudge (4 cycles = 52 steps = 1,040 ms).
    public static let cycleCount: Int = 4

    /// Vibration pattern timings in milliseconds matching `MsnSoundPlayer.vibrateNudge`.
    public static let vibrationTimingsMs: [Int] = [0, 120, 80, 150, 60, 200]

    public init() {}

    /// Triggers a 4-cycle WLM 2009 nudge shake animation.
    public func trigger(stepNanoseconds: UInt64 = 20_000_000) async {
        guard !isShaking else { return }
        isShaking = true
        var curX: CGFloat = 0
        var curY: CGFloat = 0

        for _ in 0..<Self.cycleCount {
            for delta in Self.wlmNudgeDeltas {
                curX += delta.x
                curY += delta.y
                self.offsetX = curX
                self.offsetY = curY
                if stepNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: stepNanoseconds)
                }
            }
        }

        self.offsetX = 0
        self.offsetY = 0
        self.isShaking = false
    }
}
