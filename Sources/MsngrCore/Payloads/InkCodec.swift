import Foundation

public struct InkPoint: Hashable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

public struct InkStroke: Hashable, Sendable {
    public static let himetricPerPixel: Float = 2540.0 / 96.0 // 26.458334
    public static let pixelsPerHimetric: Float = 96.0 / 2540.0 // 0.037795275

    public static let finePenHimetric = 10
    public static let normalPenHimetric = 100
    public static let boldPenHimetric = 200
    public static let smallEraserHimetric = 212
    public static let bigEraserHimetric = 500

    public var points: [InkPoint]
    public var colorRgb: UInt32 // 24-bit RGB
    public var widthHimetric: Int

    public var widthPx: Float {
        max(1.5, Float(widthHimetric) * Self.pixelsPerHimetric)
    }

    public init(points: [InkPoint], colorRgb: UInt32 = 0x000000, widthHimetric: Int = normalPenHimetric) {
        self.points = points
        self.colorRgb = colorRgb & 0xFFFFFF
        self.widthHimetric = max(1, widthHimetric)
    }
}

public struct InkDrawing: Hashable, Sendable {
    public static let defaultCanvasWidth: Float = 360.0
    public static let defaultCanvasHeight: Float = 132.0

    public var strokes: [InkStroke]
    public var canvasWidth: Float
    public var canvasHeight: Float
    public var fallbackGifData: Data?

    public init(
        strokes: [InkStroke],
        canvasWidth: Float = defaultCanvasWidth,
        canvasHeight: Float = defaultCanvasHeight,
        fallbackGifData: Data? = nil
    ) {
        self.strokes = strokes
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.fallbackGifData = fallbackGifData
    }
}

public enum InkCodec {
    public static let base64Prefix = "base64:"

    public static func rgbToColorRef(_ rgb: UInt32) -> UInt32 {
        let r = (rgb >> 16) & 0xFF
        let g = (rgb >> 8) & 0xFF
        let b = rgb & 0xFF
        return r | (g << 8) | (b << 16)
    }

    public static func colorRefToRgb(_ colorRef: UInt32) -> UInt32 {
        let r = colorRef & 0xFF
        let g = (colorRef >> 8) & 0xFF
        let b = (colorRef >> 16) & 0xFF
        return (r << 16) | (g << 8) | b
    }

    /// Encodes an unsigned integer into Multi-Byte Encoding (MBE).
    public static func writeMbe(_ value: UInt32, into data: inout Data) {
        var v = value
        while v > 0x7F {
            data.append(UInt8(0x80 | (v & 0x7F)))
            v >>= 7
        }
        data.append(UInt8(v & 0x7F))
    }

    /// Decodes an unsigned MBE integer from a data stream.
    public static func readMbe(from data: Data, at offset: inout Int) -> UInt32? {
        var result: UInt32 = 0
        var shift = 0
        while offset < data.count && shift < 35 {
            let b = UInt32(data[offset])
            offset += 1
            result |= (b & 0x7F) << shift
            if (b & 0x80) == 0 { return result }
            shift += 7
        }
        return nil
    }
}
