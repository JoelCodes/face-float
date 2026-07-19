import AppKit
import CoreImage
import Metal
import MetalKit

/// Renders CIImages into a transparent Metal layer, aspect-filled and
/// center-cropped. The window shape is a cornerRadius mask on this layer.
final class VideoView: MTKView {
    private var ciContext: CIContext!
    private var commandQueue: MTLCommandQueue!
    private var image: CIImage?
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    override var mouseDownCanMoveWindow: Bool { true }

    init() {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: .zero, device: device)
        guard let device else { return }
        commandQueue = device.makeCommandQueue()
        ciContext = CIContext(mtlDevice: device)

        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        enableSetNeedsDisplay = true
        isPaused = true
        layer?.isOpaque = false
        layer?.masksToBounds = true
    }

    required init(coder: NSCoder) { fatalError("not used") }

    /// Thread-safe entry point; may be called from the capture queue.
    func show(_ newImage: CIImage) {
        DispatchQueue.main.async { [weak self] in
            self?.image = newImage
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image,
              let drawable = currentDrawable,
              let descriptor = currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // Clear to transparent first: CIContext.render does not erase pixels
        // outside the image, and cutout mode needs true transparency.
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)?.endEncoding()

        let target = drawableSize
        let scale = max(target.width / image.extent.width, target.height / image.extent.height)
        var scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        scaled = scaled.transformed(by: CGAffineTransform(
            translationX: (target.width - scaled.extent.width) / 2 - scaled.extent.origin.x,
            y: (target.height - scaled.extent.height) / 2 - scaled.extent.origin.y))

        ciContext.render(
            scaled, to: drawable.texture, commandBuffer: commandBuffer,
            bounds: CGRect(origin: .zero, size: target), colorSpace: colorSpace)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
