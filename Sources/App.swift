import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

private final class LauncherPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = LauncherModel(history: ClipboardHistory(board: .general))
    private var panel: LauncherPanel!
    private var statusItem: NSStatusItem!
    private var menu = NSMenu(title: "轻启")
    private var previousApp: NSRunningApplication?
    private var hotKey: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var layoutChange: AnyCancellable?
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installEditMenu()
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        panel.title = "轻启"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let host = NSHostingView(rootView: LauncherView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        panel.delegate = self

        model.didCopy = { [weak self] in self?.hide(restoreFocus: true) }
        model.dismiss = { [weak self] in self?.hide(restoreFocus: true) }
        model.openURL = { [weak self] url in self?.open(url) }
        layoutChange = model.$groups.sink { [weak self] _ in
            DispatchQueue.main.async { self?.fitVisiblePanel() }
        }
        let shortcut = registerHotKey()
        installStatusItem(shortcut: shortcut)
        NSLog("轻启启动。全局快捷键 %@", shortcut ?? "注册失败，可使用菜单栏")
        model.loadApps()
        let poll = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let changed = self.model.history.capture()
            if self.panel.isVisible { self.model.tick(clipboardChanged: changed) }
        }
        poll.tolerance = 0.05
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
        present()
    }

    private func registerHotKey() -> String? {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue().toggle()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        guard status == noErr else { return nil }
        let keyID = EventHotKeyID(signature: 0x51494E47, id: 1)
        let choices = [(optionKey, "⌥ 空格"), (controlKey | optionKey, "⌃⌥ 空格")]
        for (modifiers, label) in choices {
            let registered = RegisterEventHotKey(UInt32(kVK_Space), UInt32(modifiers), keyID,
                                                GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotKey)
            if registered == noErr { return label }
        }
        return nil
    }

    private func installStatusItem(shortcut: String?) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(contentsOf: Bundle.main.url(forResource: "MenuBarIcon", withExtension: "pdf")!)!
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        button.image = image
        button.setAccessibilityLabel("轻启")
        button.toolTip = shortcut.map { "轻启 · " + $0 } ?? "轻启 · 点击打开"
        button.target = self
        button.action = #selector(statusClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let title = shortcut.map { "打开轻启    " + $0 } ?? "打开轻启（快捷键未能注册）"
        menu.addItem(withTitle: title, action: #selector(showFromMenu), keyEquivalent: "").target = self
        menu.addItem(withTitle: "剪贴板历史", action: #selector(showClipboard), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出轻启", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
    }

    private func installEditMenu() {
        let bar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "轻启")
        appMenu.addItem(withTitle: "退出轻启", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        bar.addItem(appItem)
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"),
                                     ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: NSSelectorFromString(action), keyEquivalent: key)
        }
        let editItem = NSMenuItem()
        editItem.submenu = edit
        bar.addItem(editItem)
        NSApp.mainMenu = bar
    }

    @objc private func statusClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            toggle()
        }
    }

    @objc private func showFromMenu() { present() }
    @objc private func showClipboard() { present(.clipboard) }

    private func toggle() {
        if panel.isVisible && panel.isKeyWindow { hide(restoreFocus: true) }
        else { present() }
    }

    private var contentHeight: CGFloat {
        let groups = model.groups
        var body: CGFloat = 24
        for group in groups {
            body += 19 + (group.chips ? 33 : CGFloat(group.entries.count) * 48)
        }
        if groups.count > 1 { body += CGFloat(groups.count - 1) * 11 }
        if model.empty != nil { body += 116 }
        if model.footnote != nil { body += 30 }
        return max(220, min(500, 112 + body))
    }

    private func fitVisiblePanel() {
        guard panel.isVisible, let screen = panel.screen else { return }
        let height = min(contentHeight, screen.visibleFrame.height - 24)
        var frame = panel.frame
        if abs(frame.height - height) < 0.5 { return }
        frame.origin.y = max(screen.visibleFrame.minY, frame.maxY - height)
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private func present(_ tool: Tool? = nil) {
        if let active = NSWorkspace.shared.frontmostApplication, active.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = active
        }
        model.show(tool)
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            let width = min(680, area.width - 24)
            let height = min(contentHeight, area.height - 24)
            let top = area.maxY - min(area.height * 0.20, max(0, area.height - 500) / 2)
            panel.setFrame(NSRect(x: (area.midX - width / 2).rounded(), y: max(area.minY, top - height).rounded(),
                                  width: width, height: height), display: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, panel.isKeyWindow,
                  let field = panel.contentView?.viewWithTagForSearch() else { return }
            panel.makeFirstResponder(field)
        }
    }

    private func hide(restoreFocus: Bool) {
        panel.orderOut(nil)
        if restoreFocus, let previousApp, !previousApp.isTerminated {
            previousApp.activate(options: [.activateIgnoringOtherApps])
        }
    }

    private func open(_ url: URL) {
        if NSWorkspace.shared.open(url) { hide(restoreFocus: false) }
        else { model.report(ToolError("系统未能打开 " + (url.isFileURL ? url.path : url.absoluteString))) }
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel.isVisible { panel.orderOut(nil) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if panel != nil { present() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let hotKeyHandler { RemoveEventHandler(hotKeyHandler) }
    }
}

private extension NSView {
    func viewWithTagForSearch() -> NSTextField? {
        if identifier?.rawValue == "launcher-search" { return self as? NSTextField }
        return subviews.lazy.compactMap { $0.viewWithTagForSearch() }.first
    }
}

@main
enum Qingqi {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
