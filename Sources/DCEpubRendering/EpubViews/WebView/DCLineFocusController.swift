//
//  DCLineFocusController.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import SwiftUI
import WebKit
import CoreImage

/// How the lines around the focused one are de-emphasized.
enum DCLineFocusStyle: String, CaseIterable {
    /// Dims the other lines and outlines the focused one, like the Apple Books line guide.
    case guide
    /// Blurs the other lines (a Gaussian blur of the page, in the theme's own colors).
    case blur

    var name: String {
        switch self {
        case .guide: L("Guide")
        case .blur: L("Blur")
        }
    }
}

/// Line focus: keeps one line of text prominent and de-emphasizes the rest of the page.
///
/// The effect is native: `DCLineFocusOverlayView` covers the web view and masks out a band over the
/// focused line. Only the line geometry comes from the page (`getVisibleLineRects` in EpubUtil.js).
/// Tapping a line focuses it; tapping the focused line moves to the next one.
@MainActor
final class DCLineFocusController: NSObject {

    /// Which line to focus after the page's lines are measured.
    enum Anchor: Equatable {
        case first
        case last
        /// Keep the current line index (clamped), e.g. after re-measuring the same page.
        case keep
        /// The line containing the search mark, falling back to the first line.
        case searchMatch
    }

    fileprivate enum Constants {
        /// Clear space above/below a line with no neighbour on that side, as a fraction of its height.
        static let edgePaddingRatio: CGFloat = 0.2
        /// Never pad more than this fraction of the line height, even across a wide gap.
        static let maximumPaddingRatio: CGFloat = 0.4
        static let animationDuration: TimeInterval = 0.25
        static let fadeDuration: TimeInterval = 0.2
    }

    private weak var webView: WKWebView?
    private let overlay: DCLineFocusOverlayView
    private lazy var tapRecognizer: UITapGestureRecognizer = {
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        return recognizer
    }()

    /// Measured lines in web view coordinates, top to bottom.
    private(set) var lines: [CGRect] = []
    private(set) var focusedIndex: Int?
    let style: DCLineFocusStyle

    init(webView: WKWebView,
         appearance: DCReaderAppearance,
         style: DCLineFocusStyle,
         textTrailingInset: CGFloat = 0) {
        self.webView = webView
        self.style = style
        self.overlay = DCLineFocusOverlayView(style: style, appearance: appearance, textTrailingInset: textTrailingInset)
        super.init()

        overlay.frame = DCLineFocusOverlayView.frame(covering: webView.bounds)
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.alpha = 0
        // Above the scroll view, so the effect covers the page and doesn't scroll with it.
        webView.addSubview(overlay)
        webView.addGestureRecognizer(tapRecognizer)
    }

    func detach() {
        overlay.removeFromSuperview()
        webView?.removeGestureRecognizer(tapRecognizer)
    }

    // MARK: - Updating

    /// Measures the lines currently on screen and focuses one of them.
    func refresh(anchor: Anchor) async {
        guard let webView else { return }
        // Pages call this right after positioning; let WebKit draw that position first, or the lines
        // (and the blur snapshot) come from the previous frame.
        await webView.waitForLayout()
        let json = try? await webView.evaluateJavaScriptAsync("getVisibleLineRects()")
        let measurement = Self.decode(json)
        lines = measurement.lines
        // The blur is a picture of the page, so refresh it whenever the page is re-measured.
        await overlay.updateBlurSnapshot(from: webView)

        let index: Int?
        switch anchor {
        case .first:
            index = lines.isEmpty ? nil : 0
        case .last:
            index = lines.isEmpty ? nil : lines.count - 1
        case .keep:
            if let focusedIndex, !lines.isEmpty {
                index = min(focusedIndex, lines.count - 1)
            } else {
                index = lines.isEmpty ? nil : 0
            }
        case .searchMatch:
            index = measurement.searchLine ?? (lines.isEmpty ? nil : 0)
        }
        focus(index: index, animated: false)
    }

    /// Hides the effect while the page moves under it (vertical scrolling); `refresh` shows it again.
    func suspend() {
        UIView.animate(withDuration: Constants.fadeDuration) { [overlay] in
            overlay.alpha = 0
        }
    }

    func focus(index: Int?, animated: Bool) {
        guard let index, lines.indices.contains(index) else {
            // Nothing to focus on (e.g. an image-only page): show the page as is.
            focusedIndex = nil
            suspend()
            return
        }
        focusedIndex = index
        let bounds = webView?.bounds ?? .zero
        // The overlay may not have been laid out yet when the page was just created.
        let frame = DCLineFocusOverlayView.frame(covering: bounds)
        if overlay.frame != frame {
            overlay.frame = frame
        }
        let shouldAnimate = animated && !UIAccessibility.isReduceMotionEnabled && overlay.alpha > 0
        overlay.setFocus(band: Self.band(for: index, in: lines, bounds: bounds), animated: shouldAnimate)

        if overlay.alpha < 1 {
            UIView.animate(withDuration: Constants.fadeDuration) { [overlay] in
                overlay.alpha = 1
            }
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard let tapped = Self.lineIndex(at: recognizer.location(in: webView).y, in: lines) else { return }
        // Tapping the focused line steps forward, so reading can continue with repeated taps.
        let next = tapped == focusedIndex ? min(tapped + 1, lines.count - 1) : tapped
        focus(index: next, animated: true)
    }

    // MARK: - Geometry

    /// The clear band for a line, in web view coordinates. It reaches halfway into the space between
    /// the line and each neighbour, so it never overlaps the lines around it whatever the line height.
    nonisolated static func band(for index: Int, in lines: [CGRect], bounds: CGRect) -> ClosedRange<CGFloat> {
        let line = lines[index]
        let maximum = line.height * Constants.maximumPaddingRatio
        let edge = line.height * Constants.edgePaddingRatio
        let gapAbove = index > 0 ? max(0, line.minY - lines[index - 1].maxY) / 2 : nil
        let gapBelow = index + 1 < lines.count ? max(0, lines[index + 1].minY - line.maxY) / 2 : nil
        // A line without a neighbour on one side mirrors the other side, else uses a small default.
        let above = min(gapAbove ?? gapBelow ?? edge, maximum)
        let below = min(gapBelow ?? gapAbove ?? edge, maximum)
        let top = max(bounds.minY, line.minY - above)
        let bottom = min(bounds.maxY, line.maxY + below)
        return top...max(top, bottom)
    }

    /// Gradient stops (0...1, top to bottom) for a mask that is opaque (de-emphasized) outside
    /// `band` and clear inside it, fading over `feather` points centred on each edge. Band edges sit
    /// halfway between lines, so a small feather stays in the gap and never touches a neighbour.
    nonisolated static func maskLocations(band: ClosedRange<CGFloat>, height: CGFloat, feather: CGFloat) -> [NSNumber] {
        let half = min(feather / 2, (band.upperBound - band.lowerBound) / 2)
        let clearTop = (band.lowerBound + half) / height
        let clearBottom = (band.upperBound - half) / height
        let fadeTop = max(0, (band.lowerBound - half) / height)
        let fadeBottom = min(1, (band.upperBound + half) / height)
        return [0, fadeTop, clearTop, clearBottom, fadeBottom, 1].map { NSNumber(value: Double(min(max($0, 0), 1))) }
    }

    /// The line under a tap: the line containing `y`, else the nearest one.
    nonisolated static func lineIndex(at y: CGFloat, in lines: [CGRect]) -> Int? {
        if let hit = lines.firstIndex(where: { $0.minY <= y && y <= $0.maxY }) {
            return hit
        }
        return lines.indices.min { abs(lines[$0].midY - y) < abs(lines[$1].midY - y) }
    }

    private struct Measurement {
        var lines: [CGRect] = []
        var searchLine: Int?
    }

    private static func decode(_ json: String?) -> Measurement {
        guard let data = json?.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Measurement()
        }
        let lines = (object["lines"] as? [[Double]] ?? []).compactMap { values -> CGRect? in
            guard values.count == 4 else { return nil }
            return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        let searchLine = (object["searchLine"] as? Int).flatMap { $0 >= 0 ? $0 : nil }
        return Measurement(lines: lines, searchLine: searchLine)
    }
}

// MARK: - UIGestureRecognizerDelegate

extension DCLineFocusController: UIGestureRecognizerDelegate {
    // Let taps still reach the page (highlight taps, links) and the page view controller.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Overlay

/// Draws the effect: a dimming or blur layer masked to leave the focused line clear, plus (for
/// the guide style) a rounded outline around it. Lays itself out, so the mask always matches the
/// page size, including pages created before their web view had a size.
final class DCLineFocusOverlayView: UIView {

    private enum Constants {
        /// Strength of the dimming in the guide style (fraction of the page background over the text).
        static let guideDimming: CGFloat = 0.72
        /// The guide keeps a crisp edge; the blur fades over a few points (centred on the band edge).
        static let guideFeather: CGFloat = 1
        static let blurFeather: CGFloat = 4
        /// Blur radius in points: letter shapes stay visible but even headings can't be read.
        static let blurRadius: CGFloat = 6
        /// Page-colored margin around the snapshot, so the blur fades out past the text instead of
        /// being cut off at the web view's edge.
        static var blurPadding: CGFloat { blurRadius * 3 }
        /// The outline extends a little past the text column, like Books.
        static let outlineHorizontalOutset: CGFloat = 8
        /// How far the effect extends past the web view, so it covers the page margins too and has no
        /// visible edge. Anything past the screen is simply clipped.
        static let outset = UIEdgeInsets(top: 400, left: 64, bottom: 400, right: 64)
        static let outlineWidth: CGFloat = 1
        static let outlineOpacity: CGFloat = 0.55
    }

    let style: DCLineFocusStyle
    private let effectView: UIView
    private let gradientMask = DCLineFocusMaskView()
    private let outlineLayer = CAShapeLayer()
    /// Focused band in web view coordinates.
    private var focusedBand: ClosedRange<CGFloat>?
    private let textTrailingInset: CGFloat
    private let pageBackground: UIColor

    /// The overlay's frame in the web view for a web view of the given bounds.
    static func frame(covering bounds: CGRect) -> CGRect {
        bounds.inset(by: UIEdgeInsets(top: -Constants.outset.top,
                                      left: -Constants.outset.left,
                                      bottom: -Constants.outset.bottom,
                                      right: -Constants.outset.right))
    }

    init(style: DCLineFocusStyle, appearance: DCReaderAppearance, textTrailingInset: CGFloat = 0) {
        self.style = style
        self.textTrailingInset = textTrailingInset
        self.pageBackground = appearance.uiBackgroundColor
        switch style {
        case .guide:
            let dimming = UIView()
            dimming.backgroundColor = appearance.uiBackgroundColor.withAlphaComponent(Constants.guideDimming)
            effectView = dimming
        case .blur:
            // A blurred snapshot of the page rather than a UIVisualEffectView: system blur materials
            // add their own tint, which washes out the theme's colors.
            let imageView = UIImageView()
            imageView.contentMode = .scaleToFill
            effectView = imageView
        }
        super.init(frame: .zero)

        // Touches go to the page; the effect is purely visual.
        isUserInteractionEnabled = false
        clipsToBounds = false
        addSubview(effectView)
        effectView.mask = gradientMask

        outlineLayer.fillColor = UIColor.clear.cgColor
        outlineLayer.strokeColor = appearance.uiTextColor.withAlphaComponent(Constants.outlineOpacity).cgColor
        outlineLayer.lineWidth = Constants.outlineWidth
        outlineLayer.isHidden = true
        if style == .guide {
            layer.addSublayer(outlineLayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The dimming covers the margins too; the blurred snapshot covers the web view plus its padding.
        if style == .guide {
            effectView.frame = bounds
        } else {
            let pad = Constants.blurPadding
            effectView.frame = bounds.inset(by: Constants.outset).insetBy(dx: -pad, dy: -pad)
        }
        // A mask view isn't part of the hierarchy, so it has to be sized by hand.
        gradientMask.frame = effectView.bounds
        apply(animated: false)
    }

    func setFocus(band: ClosedRange<CGFloat>?, animated: Bool) {
        focusedBand = band
        apply(animated: animated)
    }

    /// Current mask stops, for tests.
    var maskLocations: [NSNumber] { gradientMask.locations }
    /// The blurred page image (blur style), for tests.
    var blurredImage: UIImage? { (effectView as? UIImageView)?.image }

    /// Renders the blurred picture of the page used by the blur style.
    func updateBlurSnapshot(from webView: WKWebView) async {
        guard style == .blur, let imageView = effectView as? UIImageView, webView.bounds.width > 0 else { return }
        // Pages fade in after loading; a snapshot of a still-transparent page comes out blank.
        await Self.waitUntilVisible(webView)
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = true
        guard let snapshot = try? await webView.takeSnapshot(configuration: configuration) else { return }
        imageView.image = Self.blurred(snapshot, background: pageBackground, radius: Constants.blurRadius)
    }

    private static func waitUntilVisible(_ view: UIView, timeout: TimeInterval = 1) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let opacity = view.layer.presentation()?.opacity ?? Float(view.alpha)
            if view.alpha >= 1, opacity >= 0.99 { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    /// Flattens the (transparent) page snapshot onto the page color, then blurs it, so the blurred
    /// area keeps the theme's colors and fully hides the live text underneath.
    private static func blurred(_ image: UIImage, background: UIColor, radius: CGFloat) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let pad = Constants.blurPadding
        let size = CGSize(width: image.size.width + pad * 2, height: image.size.height + pad * 2)
        let flattened = UIGraphicsImageRenderer(size: size, format: format).image { context in
            background.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(at: CGPoint(x: pad, y: pad))
        }
        guard let input = CIImage(image: flattened) else { return nil }
        let output = input.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(radius * image.scale))
            .cropped(to: input.extent)
        guard let cgImage = DCBlurContext.shared.createCGImage(output, from: input.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
    /// Current outline frame (guide style) in web view coordinates, for tests.
    var outlineFrame: CGRect? {
        guard !outlineLayer.isHidden, let box = outlineLayer.path?.boundingBox else { return nil }
        return box.offsetBy(dx: -Constants.outset.left, dy: -Constants.outset.top)
    }

    private func apply(animated: Bool) {
        guard let webBand = focusedBand, bounds.height > 0 else {
            gradientMask.setLocations([0, 0, 0, 0, 0, 1], animated: false, duration: 0)
            outlineLayer.isHidden = true
            return
        }
        // Convert from web view to overlay coordinates.
        let band = (webBand.lowerBound + Constants.outset.top)...(webBand.upperBound + Constants.outset.top)
        let feather = style == .guide ? Constants.guideFeather : Constants.blurFeather
        let duration = DCLineFocusController.Constants.animationDuration
        // The mask lives in the effect view, which for the blur covers the (padded) web view.
        let pad = Constants.blurPadding
        let maskBand = style == .guide ? band : (webBand.lowerBound + pad)...(webBand.upperBound + pad)
        gradientMask.setLocations(DCLineFocusController.maskLocations(band: maskBand,
                                                                      height: effectView.bounds.height,
                                                                      feather: feather),
                                  animated: animated,
                                  duration: duration)

        guard style == .guide else { return }
        let textWidth = bounds.width - Constants.outset.left - Constants.outset.right - textTrailingInset
        let rect = CGRect(x: Constants.outset.left - Constants.outlineHorizontalOutset,
                          y: band.lowerBound,
                          width: textWidth + Constants.outlineHorizontalOutset * 2,
                          height: band.upperBound - band.lowerBound)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: rect.height / 2).cgPath
        if animated, let current = outlineLayer.path {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = outlineLayer.presentation()?.path ?? current
            animation.toValue = path
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            outlineLayer.add(animation, forKey: "path")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outlineLayer.path = path
        outlineLayer.isHidden = false
        CATransaction.commit()
    }
}

/// Core Image context shared by every page's blur, since creating one is expensive.
private enum DCBlurContext {
    nonisolated(unsafe) static let shared = CIContext(options: [.cacheIntermediates: false])
}

// MARK: - Mask

/// Vertical alpha gradient used as the effect's mask: opaque = de-emphasized, clear = in focus.
final class DCLineFocusMaskView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    private var gradientLayer: CAGradientLayer {
        // `layerClass` guarantees the backing layer type.
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        let opaque = UIColor.black.cgColor
        let clear = UIColor.clear.cgColor
        gradientLayer.colors = [opaque, opaque, clear, clear, opaque, opaque]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        // Fully de-emphasized until a line is focused.
        gradientLayer.locations = [0, 0, 0, 0, 0, 1]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var locations: [NSNumber] {
        gradientLayer.locations ?? []
    }

    func setLocations(_ locations: [NSNumber], animated: Bool, duration: TimeInterval) {
        if animated {
            let animation = CABasicAnimation(keyPath: "locations")
            animation.fromValue = gradientLayer.presentation()?.locations ?? gradientLayer.locations
            animation.toValue = locations
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            gradientLayer.add(animation, forKey: "locations")
        }
        // Backing layers don't animate implicitly, so this just sets the final value.
        gradientLayer.locations = locations
    }
}
