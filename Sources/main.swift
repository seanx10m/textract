import Cocoa
import Vision
import Carbon
import ServiceManagement

// MARK: - Global State
var statusItem: NSStatusItem!
var processing = false

// MARK: - Settings (persisted in UserDefaults)
enum Settings {
    private static let d = UserDefaults.standard

    static var ocrLanguage: String {
        get { d.string(forKey: "ocrLanguage") ?? "auto" }
        set { d.set(newValue, forKey: "ocrLanguage") }
    }

    static var keepLineBreaks: Bool {
        get { d.object(forKey: "keepLineBreaks") == nil ? true : d.bool(forKey: "keepLineBreaks") }
        set { d.set(newValue, forKey: "keepLineBreaks") }
    }

    static var captureHotKey: String {
        get { d.string(forKey: "captureHotKey") ?? "cmdshift2" }
        set { d.set(newValue, forKey: "captureHotKey") }
    }
}

// Languages offered in the menu. Codes are BCP-47 tags Vision accepts on modern macOS.
let ocrLanguages: [(code: String, label: String)] = [
    ("auto",    "Automatic"),
    ("en-US",   "English"),
    ("es-ES",   "Spanish"),
    ("fr-FR",   "French"),
    ("de-DE",   "German"),
    ("it-IT",   "Italian"),
    ("pt-BR",   "Portuguese"),
    ("zh-Hans", "Chinese (Simplified)"),
    ("ja-JP",   "Japanese"),
    ("ko-KR",   "Korean"),
]

// MARK: - Hotkey presets
struct HKPreset {
    let id: String
    let glyph: String
    let keyCode: UInt32
    let mods: UInt32
}

// Virtual key codes: 1=0x12(18) 2=0x13(19) T=0x11(17) Space=0x31(49)
// Carbon modifier masks: cmdKey=256 shiftKey=512 optionKey=2048 controlKey=4096
let capturePresets: [HKPreset] = [
    HKPreset(id: "cmdshift2",        glyph: "⌘⇧2",      keyCode: 19, mods: UInt32(cmdKey | shiftKey)),
    HKPreset(id: "optcmdt",          glyph: "⌥⌘T",      keyCode: 17, mods: UInt32(optionKey | cmdKey)),
    HKPreset(id: "ctrloptcmdspace",  glyph: "⌃⌥⌘Space", keyCode: 49, mods: UInt32(controlKey | optionKey | cmdKey)),
]

func currentCapturePreset() -> HKPreset {
    capturePresets.first { $0.id == Settings.captureHotKey } ?? capturePresets[0]
}

// MARK: - Global Hotkey Manager (Carbon RegisterEventHotKey)
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var installed = false

    private func installHandler() {
        guard !installed else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            guard let event = event else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            HotKeyManager.shared.fire(hkID.id)
            return noErr
        }, 1, &spec, nil, nil)
        installed = true
    }

    @discardableResult
    func register(keyCode: UInt32, mods: UInt32, action: @escaping () -> Void) -> UInt32 {
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x54585254), id: id) // 'TXRT'
        let status = RegisterEventHotKey(keyCode, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref = ref {
            refs[id] = ref
            actions[id] = action
        }
        return id
    }

    func unregister(_ id: UInt32) {
        if let ref = refs[id] { UnregisterEventHotKey(ref) }
        refs[id] = nil
        actions[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }
}

// MARK: - OCR
func recognize(cg: CGImage) -> String? {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.usesLanguageCorrection = true
    if Settings.ocrLanguage != "auto" {
        req.recognitionLanguages = [Settings.ocrLanguage]
    }

    do {
        try VNImageRequestHandler(cgImage: cg, options: [:]).perform([req])
    } catch {
        return nil
    }

    guard let obs = req.results, !obs.isEmpty else { return nil }
    let sep = Settings.keepLineBreaks ? "\n" : " "
    let text = obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: sep)
    return text.isEmpty ? nil : text
}

func runOCR(on cg: CGImage) {
    if processing { return }
    processing = true
    DispatchQueue.global(qos: .userInitiated).async {
        let text = recognize(cg: cg)
        DispatchQueue.main.async {
            processing = false
            guard let text = text else {
                showToast("No text found", success: false)
                return
            }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            let n = text.components(separatedBy: "\n").count
            showToast("Textracted \(n) line\(n == 1 ? "" : "s")", success: true)
        }
    }
}

func extractFromClipboard(announce: Bool = true) {
    let pb = NSPasteboard.general
    guard let imageType = pb.availableType(from: [.tiff, .png]),
          let data = pb.data(forType: imageType),
          let image = NSImage(data: data),
          let tiff = image.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let cg = bmp.cgImage else {
        if announce { showToast("No image on clipboard", success: false) }
        return
    }
    runOCR(on: cg)
}

// MARK: - Region capture (native crosshair → clipboard → OCR)
func captureRegionAndExtract() {
    let before = NSPasteboard.general.changeCount
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-i", "-c"] // interactive selection, copy to clipboard
    task.terminationHandler = { _ in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            // Clipboard only changes if the user actually captured (not Esc-cancelled).
            if NSPasteboard.general.changeCount != before {
                extractFromClipboard(announce: true)
            }
        }
    }
    do {
        try task.run()
    } catch {
        showToast("Capture failed", success: false)
    }
}

// MARK: - Toast Notification (bottom-right, non-invasive)
var toastWindow: NSWindow?

func showToast(_ message: String, success: Bool = true) {
    DispatchQueue.main.async {
        toastWindow?.orderOut(nil)

        guard let screen = NSScreen.main else { return }

        let padding: CGFloat = 16
        let toastW: CGFloat = 200
        let toastH: CGFloat = 40
        let margin: CGFloat = 20

        let x = screen.visibleFrame.maxX - toastW - margin
        let y = screen.visibleFrame.minY + margin

        let w = NSWindow(
            contentRect: NSRect(x: x, y: y, width: toastW, height: toastH),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        w.level = .floating
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = true
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .transient]

        let container = NSView(frame: NSRect(x: 0, y: 0, width: toastW, height: toastH))
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.92).cgColor

        // Status glyph
        let glyph = NSTextField(labelWithString: success ? "\u{2713}" : "\u{26A0}")
        glyph.font = .systemFont(ofSize: 16, weight: .semibold)
        glyph.textColor = success
            ? NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1)
            : NSColor(red: 0.95, green: 0.7, blue: 0.25, alpha: 1)
        glyph.frame = NSRect(x: padding, y: (toastH - 20) / 2, width: 20, height: 20)
        container.addSubview(glyph)

        // Message
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.frame = NSRect(x: padding + 24, y: (toastH - 18) / 2, width: toastW - padding * 2 - 24, height: 18)
        container.addSubview(label)

        w.contentView = container
        w.alphaValue = 0
        w.orderFrontRegardless()
        toastWindow = w

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            w.animator().alphaValue = 1
        })

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.4
                w.animator().alphaValue = 0
            }) {
                w.orderOut(nil)
                if toastWindow === w { toastWindow = nil }
            }
        }
    }
}

// MARK: - Menu Bar Icon
func createMenuBarIcon() -> NSImage {
    let s: CGFloat = 18
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { img.unlockFocus(); return img }

    let font = NSFont.systemFont(ofSize: 12, weight: .bold)
    let str = NSAttributedString(string: "T", attributes: [
        .font: font, .foregroundColor: NSColor.black
    ])
    let sz = str.size()
    str.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2))

    let m: CGFloat = 1, cl: CGFloat = 4, lw: CGFloat = 1.2
    ctx.setStrokeColor(NSColor.black.cgColor)
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    for (a, b, c) in [
        (CGPoint(x: m, y: s-m-cl), CGPoint(x: m, y: s-m), CGPoint(x: m+cl, y: s-m)),
        (CGPoint(x: s-m-cl, y: s-m), CGPoint(x: s-m, y: s-m), CGPoint(x: s-m, y: s-m-cl)),
        (CGPoint(x: m, y: m+cl), CGPoint(x: m, y: m), CGPoint(x: m+cl, y: m)),
        (CGPoint(x: s-m-cl, y: m), CGPoint(x: s-m, y: m), CGPoint(x: s-m, y: m+cl)),
    ] as [(CGPoint, CGPoint, CGPoint)] {
        ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: c)
    }
    ctx.strokePath()
    img.unlockFocus()
    img.isTemplate = true
    return img
}

// MARK: - App Delegate
class TextractApp: NSObject, NSApplicationDelegate {
    var captureHotKeyID: UInt32 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = createMenuBarIcon()
            btn.toolTip = "Textract — screen text capture"
        }

        // Clipboard extract has a fixed global hotkey: ⌘⇧1 (keyCode 18).
        HotKeyManager.shared.register(keyCode: 18, mods: UInt32(cmdKey | shiftKey)) {
            extractFromClipboard(announce: true)
        }
        // Region capture hotkey (configurable).
        applyCaptureHotKey()

        rebuildMenu()
    }

    func applyCaptureHotKey() {
        if captureHotKeyID != 0 {
            HotKeyManager.shared.unregister(captureHotKeyID)
        }
        let p = currentCapturePreset()
        captureHotKeyID = HotKeyManager.shared.register(keyCode: p.keyCode, mods: p.mods) {
            captureRegionAndExtract()
        }
    }

    var loginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let capture = NSMenuItem(title: "Capture Region   \(currentCapturePreset().glyph)",
                                 action: #selector(captureRegion), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)

        let clip = NSMenuItem(title: "Extract from Clipboard   ⌘⇧1",
                              action: #selector(clipboardExtract), keyEquivalent: "")
        clip.target = self
        menu.addItem(clip)

        menu.addItem(NSMenuItem.separator())

        // Capture Hotkey submenu
        let hkItem = NSMenuItem(title: "Capture Hotkey", action: nil, keyEquivalent: "")
        let hkMenu = NSMenu()
        for p in capturePresets {
            let it = NSMenuItem(title: p.glyph, action: #selector(selectCaptureHotKey(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = p.id
            it.state = (p.id == Settings.captureHotKey) ? .on : .off
            hkMenu.addItem(it)
        }
        hkItem.submenu = hkMenu
        menu.addItem(hkItem)

        // OCR Language submenu
        let langItem = NSMenuItem(title: "OCR Language", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        for lang in ocrLanguages {
            let it = NSMenuItem(title: lang.label, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = lang.code
            it.state = (lang.code == Settings.ocrLanguage) ? .on : .off
            langMenu.addItem(it)
        }
        langItem.submenu = langMenu
        menu.addItem(langItem)

        let lineBreaks = NSMenuItem(title: "Keep Line Breaks", action: #selector(toggleLineBreaks), keyEquivalent: "")
        lineBreaks.target = self
        lineBreaks.state = Settings.keepLineBreaks ? .on : .off
        menu.addItem(lineBreaks)

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = loginEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Textract", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc func captureRegion() { captureRegionAndExtract() }
    @objc func clipboardExtract() { extractFromClipboard(announce: true) }

    @objc func selectCaptureHotKey(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        Settings.captureHotKey = id
        applyCaptureHotKey()
        rebuildMenu()
    }

    @objc func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        Settings.ocrLanguage = code
        rebuildMenu()
    }

    @objc func toggleLineBreaks() {
        Settings.keepLineBreaks.toggle()
        rebuildMenu()
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled {
                try svc.unregister()
            } else {
                try svc.register()
            }
        } catch {
            showToast("Login item change failed", success: false)
        }
        rebuildMenu()
    }
}

// MARK: - Launch
let app = NSApplication.shared
let delegate = TextractApp()
app.delegate = delegate
app.run()
