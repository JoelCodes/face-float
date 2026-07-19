import Foundation

enum WindowShape: String, CaseIterable {
    case circle
    case rectangle

    var title: String {
        switch self {
        case .circle: return "Circle"
        case .rectangle: return "Rectangle"
        }
    }
}

enum RenderMode: String, CaseIterable {
    case normal
    case cutout
    case blur

    var title: String {
        switch self {
        case .normal: return "Normal"
        case .cutout: return "Cutout Background"
        case .blur: return "Blur Background"
        }
    }
}

enum SegmentationQuality: String, CaseIterable {
    case accurate
    case fast

    var title: String {
        switch self {
        case .accurate: return "Best Edges"
        case .fast: return "Fast Tracking"
        }
    }
}

enum Settings {
    private static let defaults = UserDefaults.standard

    static var shape: WindowShape {
        get { WindowShape(rawValue: defaults.string(forKey: "shape") ?? "") ?? .circle }
        set { defaults.set(newValue.rawValue, forKey: "shape") }
    }

    static var mode: RenderMode {
        get { RenderMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "mode") }
    }

    static var mirror: Bool {
        get { defaults.object(forKey: "mirror") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "mirror") }
    }

    static var quality: SegmentationQuality {
        get { SegmentationQuality(rawValue: defaults.string(forKey: "quality") ?? "") ?? .accurate }
        set { defaults.set(newValue.rawValue, forKey: "quality") }
    }

    static var cameraID: String? {
        get { defaults.string(forKey: "cameraID") }
        set { defaults.set(newValue, forKey: "cameraID") }
    }
}
