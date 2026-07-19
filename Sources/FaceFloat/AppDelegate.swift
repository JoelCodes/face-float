import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let window = OverlayWindow()
    private let videoView = VideoView()
    private let camera = CameraManager()
    private let processor = FrameProcessor()
    private var statusItem: NSStatusItem!

    private let sizePresets: [(String, CGFloat)] = [
        ("Small", 200), ("Medium", 320), ("Large", 480),
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        processor.mode = Settings.mode
        processor.mirror = Settings.mirror
        processor.quality = Settings.quality

        camera.frameHandler = { [processor] buffer in processor.process(buffer) }
        processor.output = { [videoView] image in videoView.show(image) }
        camera.deviceChanged = { Settings.cameraID = nil }

        setUpWindow()
        setUpStatusItem()
        requestCameraAccess()
    }

    private func setUpWindow() {
        window.contentView = videoView
        window.delegate = self
        window.setFrameAutosaveName("FaceFloatWindow")
        if window.frame.width < window.minSize.width {
            window.setContentSize(NSSize(width: 320, height: 320))
        }
        window.apply(shape: Settings.shape)
        updateShapeMask()
        window.center()
        window.setFrameUsingName("FaceFloatWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let contextMenu = NSMenu()
        contextMenu.delegate = self
        videoView.menu = contextMenu
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "web.camera", accessibilityDescription: "FaceFloat")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func requestCameraAccess() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            camera.start(deviceID: Settings.cameraID)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.camera.start(deviceID: Settings.cameraID)
                    } else {
                        self?.showPermissionAlert()
                    }
                }
            }
        default:
            showPermissionAlert()
        }
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Camera access is required"
        alert.informativeText = "FaceFloat needs camera access. Enable it in System Settings → Privacy & Security → Camera, then relaunch."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
        NSApp.terminate(nil)
    }

    // MARK: - Shape mask

    private func updateShapeMask() {
        let radius: CGFloat
        switch Settings.shape {
        case .circle:
            radius = min(window.frame.width, window.frame.height) / 2
        case .rectangle:
            radius = 16
        }
        videoView.layer?.cornerRadius = radius
    }

    func windowDidResize(_ notification: Notification) {
        updateShapeMask()
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let cameraMenu = NSMenu()
        let devices = CameraManager.availableDevices()
        if devices.isEmpty {
            cameraMenu.addItem(withTitle: "No cameras found", action: nil, keyEquivalent: "")
        }
        for device in devices {
            let item = NSMenuItem(
                title: device.localizedName, action: #selector(selectCamera(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.uniqueID
            item.state = device.uniqueID == camera.currentDevice?.uniqueID ? .on : .off
            cameraMenu.addItem(item)
        }
        let cameraItem = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        cameraItem.submenu = cameraMenu
        menu.addItem(cameraItem)
        menu.addItem(.separator())

        for shape in WindowShape.allCases {
            let item = NSMenuItem(
                title: shape.title, action: #selector(selectShape(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = shape.rawValue
            item.state = shape == Settings.shape ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        for mode in RenderMode.allCases {
            let item = NSMenuItem(
                title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == Settings.mode ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let qualityMenu = NSMenu()
        for quality in SegmentationQuality.allCases {
            let item = NSMenuItem(
                title: quality.title, action: #selector(selectQuality(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = quality.rawValue
            item.state = quality == Settings.quality ? .on : .off
            qualityMenu.addItem(item)
        }
        let qualityItem = NSMenuItem(title: "Edge Quality", action: nil, keyEquivalent: "")
        qualityItem.submenu = qualityMenu
        menu.addItem(qualityItem)
        menu.addItem(.separator())

        let mirrorItem = NSMenuItem(
            title: "Mirror", action: #selector(toggleMirror(_:)), keyEquivalent: "")
        mirrorItem.target = self
        mirrorItem.state = Settings.mirror ? .on : .off
        menu.addItem(mirrorItem)
        menu.addItem(.separator())

        for (name, size) in sizePresets {
            let item = NSMenuItem(
                title: name, action: #selector(selectSize(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = size
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit FaceFloat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func selectCamera(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Settings.cameraID = id
        camera.start(deviceID: id)
    }

    @objc private func selectShape(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let shape = WindowShape(rawValue: raw) else { return }
        Settings.shape = shape
        window.apply(shape: shape)
        updateShapeMask()
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = RenderMode(rawValue: raw) else { return }
        Settings.mode = mode
        processor.mode = mode
    }

    @objc private func selectQuality(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let quality = SegmentationQuality(rawValue: raw) else { return }
        Settings.quality = quality
        processor.quality = quality
    }

    @objc private func toggleMirror(_ sender: NSMenuItem) {
        Settings.mirror.toggle()
        processor.mirror = Settings.mirror
    }

    @objc private func selectSize(_ sender: NSMenuItem) {
        guard let side = sender.representedObject as? CGFloat else { return }
        var frame = window.frame
        let newHeight = Settings.shape == .circle ? side : side * frame.height / frame.width
        frame.origin.y += frame.height - newHeight
        frame.size = NSSize(width: side, height: newHeight)
        window.setFrame(frame, display: true, animate: true)
    }
}
