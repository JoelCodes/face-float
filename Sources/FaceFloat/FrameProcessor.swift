import CoreImage
import Foundation
import Vision

/// Turns raw camera frames into display-ready CIImages: optional person
/// segmentation (cutout or blur) plus optional mirroring.
///
/// Segmentation runs asynchronously on its own queue so the video stays at
/// full frame rate even with `.accurate` quality; each frame composites with
/// the latest available mask.
final class FrameProcessor {
    var mode: RenderMode = .normal
    var mirror = true
    var quality: SegmentationQuality = .accurate {
        didSet {
            let level: VNGeneratePersonSegmentationRequest.QualityLevel =
                quality == .accurate ? .accurate : .balanced
            segmentationQueue.async { [segmentation] in
                segmentation.qualityLevel = level
            }
        }
    }

    /// Called on the capture queue with the finished frame.
    var output: ((CIImage) -> Void)?

    private let segmentation: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .accurate
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        return request
    }()

    private let segmentationQueue = DispatchQueue(label: "facefloat.segmentation")
    private let lock = NSLock()
    private var segmentationBusy = false
    /// Latest smoothed mask at mask resolution, materialized. Guarded by `lock`.
    private var latestMask: CIImage?
    /// Previous mask for temporal smoothing. Segmentation queue only.
    private var previousMask: CIImage?
    private let maskContext = CIContext(options: [.cacheIntermediates: false])

    func process(_ buffer: CVPixelBuffer) {
        var image = CIImage(cvPixelBuffer: buffer)

        if mode != .normal {
            scheduleSegmentation(buffer)
            lock.lock()
            let mask = latestMask
            lock.unlock()

            if let mask {
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
                    kCIInputMaskImageKey: scaled(mask, to: image.extent),
                ])
            }
        }

        if mirror {
            image = image.transformed(
                by: CGAffineTransform(scaleX: -1, y: 1)
                    .translatedBy(x: -image.extent.width, y: 0))
        }

        output?(image)
    }

    /// Kicks off a mask computation unless one is already in flight.
    private func scheduleSegmentation(_ buffer: CVPixelBuffer) {
        lock.lock()
        let busy = segmentationBusy
        if !busy { segmentationBusy = true }
        lock.unlock()
        guard !busy else { return }

        segmentationQueue.async { [weak self] in
            guard let self else { return }
            let mask = self.computeMask(for: buffer)
            self.lock.lock()
            if let mask { self.latestMask = mask }
            self.segmentationBusy = false
            self.lock.unlock()
        }
    }

    /// Runs Vision segmentation, softens the edge, and temporally smooths
    /// against the previous mask. Returns nil if this frame's request failed.
    private func computeMask(for buffer: CVPixelBuffer) -> CIImage? {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, options: [:])
        guard (try? handler.perform([segmentation])) != nil,
              let maskBuffer = segmentation.results?.first?.pixelBuffer else { return nil }

        var mask = CIImage(cvPixelBuffer: maskBuffer)

        // Soften the mask edge a touch so per-frame boundary jitter is less visible.
        mask = mask.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 2.0])
            .cropped(to: mask.extent)

        // Exponential moving average against the previous mask to damp flicker.
        // Accurate masks update less often and are already stable, so favor the
        // new mask more to reduce trailing.
        if let previous = previousMask, previous.extent == mask.extent {
            mask = mask.applyingFilter("CIMix", parameters: [
                kCIInputBackgroundImageKey: previous,
                "inputAmount": quality == .accurate ? 0.7 : 0.4,
            ])
        }

        // Materialize at mask resolution (small, cheap) to cap the graph depth.
        guard let rendered = maskContext.createCGImage(mask, from: mask.extent) else {
            previousMask = nil
            return nil
        }
        let materialized = CIImage(cgImage: rendered)
        previousMask = materialized
        return materialized
    }

    private func scaled(_ mask: CIImage, to extent: CGRect) -> CIImage {
        let sx = extent.width / mask.extent.width
        let sy = extent.height / mask.extent.height
        return mask.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
    }
}
