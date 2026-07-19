import CoreImage
import Foundation
import Vision

/// Turns raw camera frames into display-ready CIImages: optional person
/// segmentation (cutout or blur) plus optional mirroring. Runs on the
/// capture queue; late frames are already discarded upstream.
final class FrameProcessor {
    var mode: RenderMode = .normal
    var mirror = true

    /// Called on the capture queue with the finished frame.
    var output: ((CIImage) -> Void)?

    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    // Temporal smoothing state: the previous frame's mask, materialized so the
    // Core Image filter graph doesn't grow frame over frame.
    private var previousMask: CIImage?
    private let maskContext = CIContext(options: [.cacheIntermediates: false])
    /// Fraction of the new mask blended in each frame. Lower = steadier but
    /// more ghosting when you move quickly.
    private let maskBlendAmount = 0.4

    func process(_ buffer: CVPixelBuffer) {
        var image = CIImage(cvPixelBuffer: buffer)

        if mode != .normal, let mask = personMask(for: buffer, matching: image.extent) {
            let background: CIImage
            switch mode {
            case .cutout:
                background = CIImage(color: .clear).cropped(to: image.extent)
            case .blur:
                background = image
                    .clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 18.0])
                    .cropped(to: image.extent)
            case .normal:
                background = image
            }
            image = image.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: background,
                kCIInputMaskImageKey: mask,
            ])
        }

        if mirror {
            image = image.transformed(
                by: CGAffineTransform(scaleX: -1, y: 1)
                    .translatedBy(x: -image.extent.width, y: 0))
        }

        output?(image)
    }

    private func personMask(for buffer: CVPixelBuffer, matching extent: CGRect) -> CIImage? {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        guard (try? handler.perform([segmentation])) != nil,
              let maskBuffer = segmentation.results?.first?.pixelBuffer else {
            // Segmentation dropped this frame; reuse the last good mask so the
            // whole background doesn't flash back to sharp for one frame.
            return previousMask.map { scaled($0, to: extent) }
        }

        var mask = CIImage(cvPixelBuffer: maskBuffer)

        // Soften the mask edge a touch so per-frame boundary jitter is less visible.
        mask = mask.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 2.0])
            .cropped(to: mask.extent)

        // Exponential moving average against the previous mask to damp flicker.
        if let previous = previousMask, previous.extent == mask.extent {
            mask = mask.applyingFilter("CIMix", parameters: [
                kCIInputBackgroundImageKey: previous,
                "inputAmount": maskBlendAmount,
            ])
        }

        // Materialize at mask resolution (small, cheap) to cap the graph depth.
        if let rendered = maskContext.createCGImage(mask, from: mask.extent) {
            mask = CIImage(cgImage: rendered)
            previousMask = mask
        } else {
            previousMask = nil
        }

        return scaled(mask, to: extent)
    }

    private func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        return mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }
}
