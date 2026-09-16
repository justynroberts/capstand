import AppKit
import AVFoundation

/// The phone's screen, drawn by a preview layer, with an optional frame around
/// it. Everything is laid out from a FrameLayout. The whole view drags the window.
final class ScreenView: NSView {

    let previewLayer = AVCaptureVideoPreviewLayer()

    var frameLayout = FrameLayout(canvas: CGSize(width: 1, height: 2), screen: CGRect(x: 0, y: 0, width: 1, height: 2)) {
        didSet { needsLayout = true }
    }

    var finish: Finish = .natural {
        didSet { applyFinish() }
    }

    private let buttonsLayer = CAShapeLayer()
    private let railLayer = CAGradientLayer()
    private let railMask = CAShapeLayer()
    private let bezelLayer = CAShapeLayer()
    private let islandLayer = CAShapeLayer()
    private let imageLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = NSColor.black.cgColor
        previewLayer.masksToBounds = true
        previewLayer.cornerCurve = .continuous

        railLayer.mask = railMask
        railLayer.startPoint = CGPoint(x: 0, y: 1)
        railLayer.endPoint = CGPoint(x: 1, y: 0)
        bezelLayer.fillColor = NSColor.black.cgColor
        islandLayer.fillColor = NSColor.black.cgColor
        imageLayer.contentsGravity = .resize

        for sublayer in [buttonsLayer, railLayer, bezelLayer, previewLayer, islandLayer, imageLayer] {
            layer?.addSublayer(sublayer)
        }
        applyFinish()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var mouseDownCanMoveWindow: Bool { true }

    private func applyFinish() {
        buttonsLayer.fillColor = finish.base.cgColor
        railLayer.colors = [finish.highlight, finish.base, finish.highlight, finish.base].map(\.cgColor)
    }

    override func layout() {
        super.layout()
        let spec = frameLayout
        let k = bounds.width / spec.canvas.width
        func scaled(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k)
        }
        func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
            let radius = max(0, min(radius, r.width / 2, r.height / 2))
            return CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        previewLayer.frame = scaled(spec.screen)
        previewLayer.cornerRadius = spec.screenRadius * k

        let drawn = spec.body != nil
        for part in [buttonsLayer, railLayer, bezelLayer] as [CALayer] { part.isHidden = !drawn }
        if let body = spec.body.map(scaled) {
            let rail = spec.rail * k
            railLayer.frame = bounds
            railMask.path = rounded(body, spec.bodyRadius * k)
            bezelLayer.path = rounded(body.insetBy(dx: rail, dy: rail), (spec.bodyRadius - spec.rail) * k)
            let buttons = CGMutablePath()
            for rect in spec.buttons.map(scaled) { buttons.addPath(rounded(rect, min(rect.width, rect.height) / 2)) }
            buttonsLayer.path = buttons
        }

        islandLayer.isHidden = spec.island == nil
        if let island = spec.island.map(scaled) {
            islandLayer.path = rounded(island, min(island.width, island.height) / 2)
        }

        imageLayer.isHidden = spec.image == nil
        imageLayer.contents = spec.image
        imageLayer.frame = bounds

        CATransaction.commit()
        // The shadow follows the frame's outline only if it is recomputed.
        window?.invalidateShadow()
    }
}
