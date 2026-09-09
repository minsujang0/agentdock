// SessionDock — the local AI chat sessions you have running, gathered in the
// bottom-right corner, each one a click away from the app it lives in.
//
// Sessions are discovered two ways: hooks that Claude Code and Codex call as
// they work, and a scan of their transcript directories for anything the hooks
// missed. Both write into ~/.local/state/chat-sessions.

import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let dock = Dock()
    private var scanTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem.button?.image = NSImage(systemSymbolName: "bubble.left.and.bubble.right",
                                           accessibilityDescription: "SessionDock")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        // The header's settings button shows this same menu, built fresh so
        // its checkmarks and session list are current either way.
        Menus.build = { [weak self] in
            let popped = NSMenu()
            self?.menuNeedsUpdate(popped)
            return popped
        }

        log("시작 — 접근성 권한: \(Route.canUseAccessibility ? "있음" : "없음")")
        if !Route.canUseAccessibility {
            // Ask once; the prompt is what puts the app in the list.
            _ = AXIsProcessTrustedWithOptions(
                [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                    as CFDictionary)
        }
        Route.describeWindows()
        scan()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.scan()
        }
        dock.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dock.stop()
    }

    /// The home scan: catches sessions the hooks never saw.
    private func scan() {
        // Only ever from inside the bundle. The fallback used to name one
        // machine's checkout, which is no use to anyone else and no use here
        // either once the app is installed somewhere else.
        guard let script = Bundle.main.resourceURL?.appending(path: "scan.py"),
              FileManager.default.fileExists(atPath: script.path) else {
            log("scan.py 를 번들에서 찾지 못했습니다")
            return
        }
        let task = Process()
        task.executableURL = URL(filePath: "/usr/bin/python3")
        task.arguments = [script.path]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.dock.reload() }
        }
        try? task.run()
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if Screens.all.count > 1 {
            let header = NSMenuItem(title: "표시할 화면", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            for (index, screen) in Screens.all.enumerated() {
                let number = Screens.number(screen)
                let size = screen.frame.size
                let name = "  화면 \(index + 1) — \(Int(size.width))×\(Int(size.height))"
                let item = NSMenuItem(title: name, action: #selector(pickScreen(_:)),
                                      keyEquivalent: "")
                item.target = self
                item.tag = number
                item.state = Screens.number(Screens.target ?? screen) == number ? .on : .off
                menu.addItem(item)
            }
        }

        // What the day has cost in waiting, which is the one thing only this
        // app can see: it watches both ends of every handover.
        if let day = Ledger.load() {
            let mine = NSMenuItem(
                title: "오늘 나를 기다린 시간  \(Ledger.spell(day.waited_on_me))",
                action: nil, keyEquivalent: "")
            mine.isEnabled = false
            menu.addItem(mine)
            let theirs = NSMenuItem(
                title: "오늘 내가 기다린 시간  \(Ledger.spell(day.waited_on_them))",
                action: nil, keyEquivalent: "")
            theirs.isEnabled = false
            menu.addItem(theirs)
            if !day.longest_chat.isEmpty {
                let name = day.longest_chat.count > 28
                    ? String(day.longest_chat.prefix(27)) + "…" : day.longest_chat
                let worst = NSMenuItem(
                    title: "가장 오래 방치  \(name) · \(Ledger.spell(day.longest_seconds))",
                    action: nil, keyEquivalent: "")
                worst.isEnabled = false
                menu.addItem(worst)
            }
        }

        menu.addItem(.separator())
        add(menu, "지금 다시 찾기", #selector(rescan), "r")
        let idle = NSMenuItem(title: "유휴 세션도 보기",
                              action: #selector(toggleIdle), keyEquivalent: "")
        idle.target = self
        idle.state = Settings.shared.showIdle ? .on : .off
        menu.addItem(idle)
        let folded = NSMenuItem(title: "접어두기",
                                action: #selector(toggleFold), keyEquivalent: "")
        folded.target = self
        folded.state = Settings.shared.collapsed ? .on : .off
        menu.addItem(folded)

        let delegated = NSMenuItem(title: "위임된 작업도 보기",
                                   action: #selector(toggleDelegated), keyEquivalent: "")
        delegated.target = self
        delegated.state = Settings.shared.showDelegated ? .on : .off
        menu.addItem(delegated)

        // One entry per place the sessions on screen came from, so a source
        // can be put away without hiding a whole tool: two copies of Codex are
        // two sources, and a run started inside an editor is a third. A source
        // already put away stays listed even while it is quiet, or there would
        // be no way to bring it back.
        let sources = NSMenu()
        var listed: [String: String] = [:]
        for session in SessionStore.load() {
            listed[session.sourceKey] = session.sourceLabel
        }
        for key in Settings.shared.hiddenSources where listed[key] == nil {
            listed[key] = key
        }
        for (key, label) in listed.sorted(by: { $0.value < $1.value }) {
            let item = NSMenuItem(title: label, action: #selector(toggleSource),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = Settings.shared.isHidden(source: key) ? .off : .on
            sources.addItem(item)
        }
        let shades = NSMenu()
        for (label, value) in Settings.tintLevels {
            let item = NSMenuItem(title: label, action: #selector(pickOpacity),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.state = abs(Settings.shared.cardTint - value) < 0.01 ? .on : .off
            shades.addItem(item)
        }
        // Only worth offering where the cards fall back to NSVisualEffectView.
        // On a system with its own glass the material is never consulted, and
        // the submenu was a row of settings that changed nothing.
        if !CardView.usesSystemGlass {
        let blurs = NSMenu()
        for (label, key) in Settings.materials {
            let item = NSMenuItem(title: label, action: #selector(pickMaterial),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = Settings.shared.cardMaterial == key ? .on : .off
            blurs.addItem(item)
        }
        let blurHolder = NSMenuItem(title: "블러 재질", action: nil, keyEquivalent: "")
        menu.addItem(blurHolder)
        menu.setSubmenu(blurs, for: blurHolder)
        }

        let shadeHolder = NSMenuItem(title: "밝기", action: nil, keyEquivalent: "")
        menu.addItem(shadeHolder)
        menu.setSubmenu(shades, for: shadeHolder)

        // The left edge of the header resizes the column by hand; these are
        // here so the feature can be found without knowing that.
        let widths = NSMenu()
        for (label, points) in Settings.widthSteps {
            let item = NSMenuItem(title: "\(label) (\(Int(points)))",
                                  action: #selector(pickWidth), keyEquivalent: "")
            item.target = self
            item.representedObject = points
            item.state = abs(Settings.shared.dockWidth - points) < 1 ? .on : .off
            widths.addItem(item)
        }
        widths.addItem(.separator())
        let hint = NSMenuItem(title: "현재 \(Int(Settings.shared.dockWidth))pt — 왼쪽 모서리를 끌어도 됩니다",
                              action: nil, keyEquivalent: "")
        hint.isEnabled = false
        widths.addItem(hint)
        let widthHolder = NSMenuItem(title: "너비", action: nil, keyEquivalent: "")
        menu.addItem(widthHolder)
        menu.setSubmenu(widths, for: widthHolder)

        let heights = NSMenu()
        for (label, points) in Settings.rowSteps {
            let item = NSMenuItem(title: "\(label) (\(Int(points)))",
                                  action: #selector(pickRowHeight), keyEquivalent: "")
            item.target = self
            item.representedObject = points
            item.state = abs(Settings.shared.rowHeight - points) < 1 ? .on : .off
            heights.addItem(item)
        }
        let heightHolder = NSMenuItem(title: "행 높이", action: nil, keyEquivalent: "")
        menu.addItem(heightHolder)
        menu.setSubmenu(heights, for: heightHolder)

        if !listed.isEmpty {
            let holder = NSMenuItem(title: "소스", action: nil, keyEquivalent: "")
            menu.addItem(holder)
            menu.setSubmenu(sources, for: holder)
        }

        if !Route.canUseAccessibility {
            menu.addItem(.separator())
            let warn = NSMenuItem(title: "접근성 권한 없음 — 앱만 열립니다",
                                  action: #selector(openAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        add(menu, "업데이트 확인…  (\(Update.current))", #selector(checkUpdate), "")
        add(menu, "종료", #selector(quit), "q")
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func pickScreen(_ sender: NSMenuItem) {
        Settings.shared.pinnedScreen = sender.tag
        dock.layout(animated: false)
    }

    @objc private func rescan() {
        Route.describeWindows()
        scan()
    }

    @objc private func toggleIdle() {
        Settings.shared.showIdle.toggle()
        dock.reload()
    }

    @objc private func toggleFold() {
        dock.toggleCollapsed()
    }

    @objc private func toggleDelegated() {
        Settings.shared.showDelegated.toggle()
        dock.reload()
    }

    @objc private func pickMaterial(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Settings.shared.cardMaterial = key
        dock.repaint()
    }

    @objc private func pickOpacity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        Settings.shared.cardTint = value
        dock.repaint()
    }

    @objc private func pickWidth(_ sender: NSMenuItem) {
        guard let points = sender.representedObject as? Double else { return }
        dock.setWidth(points)
    }

    @objc private func pickRowHeight(_ sender: NSMenuItem) {
        guard let points = sender.representedObject as? Double else { return }
        dock.setRowHeight(points)
    }

    @objc private func toggleSource(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Settings.shared.toggle(source: key)
        dock.reload()
    }

    @objc private func openAccessibility() {
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func checkUpdate() {
        Task { @MainActor in
            do {
                let release = try await Update.latest()
                guard release.isNewer else {
                    Self.tell("최신입니다", "설치된 버전은 \(Update.current) 입니다.")
                    return
                }
                let notes = release.notes.isEmpty
                    ? "" : "\n\n" + String(release.notes.prefix(500))
                let answer = Self.ask(
                    "새 버전 \(release.version)",
                    "지금은 \(Update.current) 입니다." + notes
                        + "\n\n받으면 다시 빌드하고 앱을 새로 띄웁니다.",
                    accept: "받기", other: release.page == nil ? nil : "릴리스 보기")
                switch answer {
                case .accept: self.install(release)
                case .other: if let page = release.page { NSWorkspace.shared.open(page) }
                case .cancel: break
                }
            } catch {
                Self.tell("업데이트를 확인하지 못했습니다",
                          error.localizedDescription)
            }
        }
    }

    /// Hand the work to a script and get out of its way: a running bundle
    /// cannot be replaced underneath itself without breaking the process.
    private func install(_ release: Update.Release) {
        guard let script = Bundle.main.resourceURL?.appending(path: "update.sh"),
              FileManager.default.fileExists(atPath: script.path) else {
            Self.tell("업데이트 스크립트를 찾지 못했습니다",
                      "체크아웃에서 빌드한 앱에서만 자동 업데이트가 됩니다.")
            return
        }
        let task = Process()
        task.executableURL = URL(filePath: "/bin/bash")
        task.arguments = [script.path, Bundle.main.bundlePath, release.tag]
        do {
            try task.run()
        } catch {
            Self.tell("업데이트를 시작하지 못했습니다", error.localizedDescription)
            return
        }
        log("업데이트 시작: \(release.tag)")
        NSApp.terminate(nil)
    }

    private enum Answer { case accept, other, cancel }

    private static func ask(_ title: String, _ body: String,
                            accept: String, other: String?) -> Answer {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: accept)
        if let other { alert.addButton(withTitle: other) }
        alert.addButton(withTitle: "취소")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .accept
        case .alertSecondButtonReturn: return other == nil ? .cancel : .other
        default: return .cancel
        }
    }

    private static func tell(_ title: String, _ body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
