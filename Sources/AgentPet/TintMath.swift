import Foundation

/// Recolours the green band of a premultiplied RGBA8 buffer; other pixels are left as they are.
enum TintMath {
    static let bandLowDegrees = 60.0
    static let bandHighDegrees = 200.0
    static let bandFeatherDegrees = 15.0
    static let saturationFloor = 0.07
    static let saturationFeather = 0.04
    static let saturationGain = 2.3
    static let valueGain = 1.2
    static let channelMax = 255.0
    static let hueWrap = 360.0
    static let degreesPerSector = 60.0
    static let sectorPairModulus = 2.0
    static let redSectorWrap = 6.0
    static let greenSectorOffset = 2.0
    static let blueSectorOffset = 4.0
    static let smoothStepMidpoint = 0.5
    static let hashModulus: UInt64 = 360
    static let fnvOffset: UInt64 = 14_695_981_039_346_656_037
    static let fnvPrime: UInt64 = 1_099_511_628_211

    /// Stable across launches, unlike `hashValue`.
    static func hue(forName name: String) -> Double {
        var hash = fnvOffset
        for byte in name.utf8 {
            hash = (hash ^ UInt64(byte)) &* fnvPrime
        }
        return Double(hash % hashModulus)
    }

    static func tint(premultipliedRGBA pixels: inout [UInt8], targetHue: Double) {
        var index = 0
        while index + 3 < pixels.count {
            let alpha = Double(pixels[index + 3])
            if alpha > 0 {
                tintPixel(&pixels, at: index, alpha: alpha, targetHue: targetHue)
            }
            index += 4
        }
    }

    private static func tintPixel(_ pixels: inout [UInt8], at index: Int, alpha: Double, targetHue: Double) {
        let scale = channelMax / alpha
        let red = min(1, Double(pixels[index]) * scale / channelMax)
        let green = min(1, Double(pixels[index + 1]) * scale / channelMax)
        let blue = min(1, Double(pixels[index + 2]) * scale / channelMax)
        let (hue, saturation, value) = rgbToHSV(red, green, blue)
        let weight = bandWeight(hue) * smoothStep((saturation - saturationFloor) / saturationFeather + smoothStepMidpoint)
        guard weight > 0 else { return }
        let target = hsvToRGB(
            targetHue,
            min(1, saturation * saturationGain),
            min(1, value * valueGain)
        )
        let blended = [
            red + (target.0 - red) * weight,
            green + (target.1 - green) * weight,
            blue + (target.2 - blue) * weight,
        ]
        let premultiply = alpha / channelMax
        for channel in 0..<3 {
            pixels[index + channel] = UInt8(max(0, min(channelMax, (blended[channel] * premultiply * channelMax).rounded())))
        }
    }

    private static func bandWeight(_ hue: Double) -> Double {
        let distance: Double
        if hue < bandLowDegrees {
            distance = bandLowDegrees - hue
        } else if hue > bandHighDegrees {
            distance = hue - bandHighDegrees
        } else {
            distance = 0
        }
        return smoothStep(1 - distance / bandFeatherDegrees)
    }

    private static func smoothStep(_ x: Double) -> Double {
        let t = max(0, min(1, x))
        return t * t * (3 - 2 * t)
    }

    private static func rgbToHSV(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == r {
                hue = ((g - b) / delta).truncatingRemainder(dividingBy: redSectorWrap)
            } else if maxC == g {
                hue = (b - r) / delta + greenSectorOffset
            } else {
                hue = (r - g) / delta + blueSectorOffset
            }
            hue *= degreesPerSector
            if hue < 0 { hue += hueWrap }
        }
        return (hue, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    private static func hsvToRGB(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let sector = (h.truncatingRemainder(dividingBy: hueWrap) / degreesPerSector)
        let chroma = v * s
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: sectorPairModulus) - 1))
        let m = v - chroma
        let (r, g, b): (Double, Double, Double)
        switch Int(sector) {
        case 0: (r, g, b) = (chroma, x, 0)
        case 1: (r, g, b) = (x, chroma, 0)
        case 2: (r, g, b) = (0, chroma, x)
        case 3: (r, g, b) = (0, x, chroma)
        case 4: (r, g, b) = (x, 0, chroma)
        default: (r, g, b) = (chroma, 0, x)
        }
        return (r + m, g + m, b + m)
    }
}
