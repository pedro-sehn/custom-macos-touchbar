import AppKit

/// Shared colour and animation helpers.
///
/// Note on scope: NSTouchBar exposes no background colour — the strip itself
/// belongs to the system. Everything visual here happens inside individual
/// widget views, which is why wide widgets (graphs, pomodoro) carry the look.
enum Appearance {
    /// Green → amber → red ramp for load-style values in 0...1.
    static func heat(_ value: Double) -> NSColor {
        let v = min(max(value, 0), 1)
        // Hue 0.33 (green) down to 0.0 (red), easing so mid-range reads amber
        // rather than sitting green until the last moment.
        let hue = 0.33 * (1 - pow(v, 0.75))
        return NSColor(hue: CGFloat(hue), saturation: 0.85, brightness: 0.95, alpha: 1)
    }

    static func lerp(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
        let t = CGFloat(min(max(t, 0), 1))
        guard let x = a.usingColorSpace(.sRGB), let y = b.usingColorSpace(.sRGB) else { return a }
        return NSColor(srgbRed: x.redComponent + (y.redComponent - x.redComponent) * t,
                       green: x.greenComponent + (y.greenComponent - x.greenComponent) * t,
                       blue: x.blueComponent + (y.blueComponent - x.blueComponent) * t,
                       alpha: 1)
    }

    /// Runs layer changes with an explicit duration instead of Core Animation's
    /// 0.25s default, so fills can be paced to the ticker.
    static func animate(duration: CFTimeInterval,
                        timing: CAMediaTimingFunctionName = .linear,
                        _ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: timing))
        body()
        CATransaction.commit()
    }

    /// One-shot brightness pulse. Used to acknowledge state changes — the
    /// Touch Bar has no press feedback of its own beyond haptics.
    static func pulse(_ layer: CALayer, to color: NSColor, duration: CFTimeInterval = 0.35) {
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = color.highlight(withLevel: 0.55)?.cgColor ?? color.cgColor
        animation.toValue = layer.backgroundColor
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "pulse")
    }

    /// Quick inward press. Works on any layer regardless of how the view draws
    /// itself, which matters for NSButton — its bezel is not the layer's
    /// background, so animating colour there shows nothing.
    ///
    /// Scales *down*, never up: growing a button shoves its neighbours around
    /// and can push items past the end of the bar, where NSTouchBar drops them.
    static func bump(_ layer: CALayer, scale: CGFloat = 0.88) {
        let animation = CAKeyframeAnimation(keyPath: "transform")
        animation.values = [
            CATransform3DIdentity,
            scaleAboutCenter(layer, scale),
            CATransform3DIdentity
        ]
        animation.keyTimes = [0, 0.35, 1]
        animation.duration = 0.22
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(animation, forKey: "bump")
    }

    /// A scale that pivots on the layer's visual centre.
    ///
    /// `transform.scale` pivots on `anchorPoint`, and AppKit gives layer-backed
    /// NSViews an anchor of (0, 0) — so a plain scale animation squeezes toward
    /// the bottom-left corner. Moving the anchor instead would fight AppKit,
    /// which rewrites `position` on every layout pass, so the offset is baked
    /// into the transform: translate to centre, scale, translate back.
    private static func scaleAboutCenter(_ layer: CALayer, _ scale: CGFloat) -> CATransform3D {
        let bounds = layer.bounds
        let anchor = CGPoint(x: layer.anchorPoint.x * bounds.width,
                             y: layer.anchorPoint.y * bounds.height)
        let offset = CGPoint(x: bounds.midX - anchor.x, y: bounds.midY - anchor.y)

        var transform = CATransform3DIdentity
        transform = CATransform3DTranslate(transform, offset.x, offset.y, 0)
        transform = CATransform3DScale(transform, scale, scale, 1)
        return CATransform3DTranslate(transform, -offset.x, -offset.y, 0)
    }

    /// Vertical gradient, dark at the bottom so text stays readable over it.
    static func gradientLayer(_ color: NSColor) -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.colors = [
            color.withAlphaComponent(0.85).cgColor,
            color.withAlphaComponent(0.35).cgColor
        ]
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 0, y: 0)
        return gradient
    }
}
