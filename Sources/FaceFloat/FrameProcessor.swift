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
              let maskBuffer = segmentation.results?.first?.pixelBuffer else { return nil }
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        return mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }
}
