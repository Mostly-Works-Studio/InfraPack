// InfraPack menu bar app (macOS).
//
// A status-bar item listing the installed techs with on/off toggles and
// "Open" entries for their web UIs. It talks to the console's API on
// localhost, so it shows exactly what the console shows.
//
// Built locally by `infrapack menubar install` with the system swiftc, so no
// unsigned binary is ever downloaded.
import Cocoa
import Foundation

/// A pill toggle drawn by hand: NSSwitch inside a menu looks inactive (menus are
/// never the key window), so it would never show its filled "on" colour.
final class PillToggle: NSView {
    var isOn = false { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.4 } }
    var onTap: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 1, dy: 1)
        let radius = track.height / 2
        let fill = isOn ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor
        fill.setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()
        let knobD = track.height - 4
        let knobX = isOn ? track.maxX - knobD - 2 : track.minX + 2
        let knob = NSRect(x: knobX, y: track.minY + 2, width: knobD, height: knobD)
        NSColor.white.setFill()
        let path = NSBezierPath(ovalIn: knob)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowBlurRadius = 1.5; shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.set()
        path.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
    }
    override func mouseDown(with event: NSEvent) { if isEnabled { onTap?() } }
}

/// One tech: name, a small status line, and a toggle. Lives inside a menu item as
/// a custom view, which is what lets the menu stay open when the toggle is used.
final class StackRow: NSView {
    let name: String
    private let title = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let toggle = PillToggle()
    var onToggle: ((String) -> Void)?

    init(name: String, label: String) {
        self.name = name
        super.init(frame: NSRect(x: 0, y: 0, width: 300, height: 34))
        title.stringValue = label
        title.font = NSFont.menuFont(ofSize: 13)
        title.frame = NSRect(x: 14, y: 15, width: 220, height: 17)
        status.font = NSFont.systemFont(ofSize: 10.5)
        status.textColor = .secondaryLabelColor
        status.frame = NSRect(x: 14, y: 2, width: 220, height: 13)
        toggle.frame = NSRect(x: 300 - 14 - 34, y: 7, width: 34, height: 20)
        toggle.onTap = { [weak self] in
            guard let self = self else { return }
            self.toggle.isOn.toggle()             // flip right away; the console confirms within a refresh
            self.onToggle?(self.name)
        }
        addSubview(title); addSubview(status); addSubview(toggle)
    }
    required init?(coder: NSCoder) { fatalError() }

    func apply(on: Bool, mixed: Bool, statusText: String, busy: Bool) {
        if !busy && toggle.isOn != on { toggle.isOn = on }
        toggle.isEnabled = !busy
        status.stringValue = statusText
        status.textColor = busy ? .tertiaryLabelColor : (mixed ? .systemOrange : .secondaryLabelColor)
    }
}

final class InfraPackMenu: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var rows: [String: StackRow] = [:]
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var state: [String: Any] = [:]
    private var reachable = false
    private var busy = Set<String>()
    private var menuOpen = false
    private var structure = ""            // what the menu was built for; rebuild only when it changes

    // ---------------------------------------------------------- console --
    private var home: String {
        ProcessInfo.processInfo.environment["INFRAPACK_HOME"] ?? (NSHomeDirectory() + "/.infrapack")
    }
    private var consoleURL: URL {
        var port = "1717"
        if let env = try? String(contentsOfFile: home + "/.env", encoding: .utf8) {
            for line in env.split(separator: "\n") where line.hasPrefix("CONSOLE_PORT=") {
                port = String(line.dropFirst("CONSOLE_PORT=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            }
        }
        return URL(string: port == "80" ? "http://localhost" : "http://localhost:\(port)")!
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let path = Bundle.main.path(forResource: "InfraPack", ofType: "icns"), let icon = NSImage(contentsOfFile: path) {
            icon.size = NSSize(width: 18, height: 18)
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "IP"
        }
        statusItem.button?.toolTip = "InfraPack"
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refresh()
        // .common mode so the timer keeps firing while the menu is open (menu tracking runs its own loop)
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
    }

    func menuNeedsUpdate(_ menu: NSMenu) { rebuildIfNeeded() }
    func menuWillOpen(_ menu: NSMenu) { menuOpen = true; refresh() }
    func menuDidClose(_ menu: NSMenu) { menuOpen = false }

    // ------------------------------------------------------------- data --
    private func refresh() {
        var req = URLRequest(url: consoleURL.appendingPathComponent("api/state"))
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self = self else { return }
            let parsed = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async {
                self.reachable = parsed != nil
                if let p = parsed { self.state = p }
                self.updateBadge()
                self.rebuildIfNeeded()          // in place while the menu is open, so it updates live
            }
        }.resume()
    }

    private func post(_ path: String, _ body: [String: Any], then: @escaping () -> Void = {}) {
        var req = URLRequest(url: consoleURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 600
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { then(); self.refresh() }
        }.resume()
    }

    private var stacks: [[String: Any]] { state["stacks"] as? [[String: Any]] ?? [] }
    private var services: [[String: Any]] { state["services"] as? [[String: Any]] ?? [] }
    private func services(of stack: String) -> [[String: Any]] { services.filter { ($0["stack"] as? String) == stack } }

    private func updateBadge() {
        let up = services.filter { ($0["up"] as? Bool) == true }.count
        statusItem.button?.toolTip = reachable ? "InfraPack — \(up) service\(up == 1 ? "" : "s") running" : "InfraPack — console not running"
        statusItem.button?.alphaValue = reachable ? 1.0 : 0.45
    }

    // ------------------------------------------------------------- menu --
    private var currentStructure: String {
        var parts = [reachable ? "up" : "down"]
        for stack in stacks {
            let name = stack["name"] as? String ?? ""
            let links = services(of: name).compactMap { ($0["link"] as? String) != nil ? ($0["name"] as? String) : nil }
            parts.append(name + ":" + links.joined(separator: ","))
        }
        return parts.joined(separator: "|")
    }

    private func rebuildIfNeeded() {
        let s = currentStructure
        if s != structure || menu.items.isEmpty {
            // a full rebuild while the menu is open makes it flicker; keep the old one until it closes
            if menuOpen && !menu.items.isEmpty { applyState(); return }
            structure = s
            rebuild()
        } else {
            applyState()
        }
    }

    private func applyRow(_ row: StackRow, stack: [String: Any], svcs: [[String: Any]]) {
        let name = stack["name"] as? String ?? ""
        let up = svcs.filter { ($0["up"] as? Bool) == true }.count
        let starting = svcs.contains { ($0["health"] as? String) == "starting" }
        let unhealthy = svcs.contains { ($0["health"] as? String) == "unhealthy" }
        var text: String
        if busy.contains(name) { text = "working…" }
        else if up == 0 { text = "stopped" }
        else if starting { text = "starting…" }
        else if unhealthy { text = "unhealthy" }
        else if up < svcs.count { text = "\(up) of \(svcs.count) running" }
        else { text = svcs.count == 1 ? "running" : "running · \(svcs.count) services" }
        let mb = (stack["memoryMB"] as? Int).map { " · ~\(String(format: "%.1f", Double($0) / 1024)) GiB" } ?? ""
        row.apply(on: up > 0, mixed: up > 0 && up < svcs.count, statusText: text + (up > 0 ? "" : mb), busy: busy.contains(name))
    }

    // update titles / checkmarks / enabled flags of the existing items (safe while the menu is open)
    private func applyState() {
        if let head = menu.items.first(where: { $0.tag == 1 }), reachable, head.title != summaryText { head.title = summaryText }
        for it in menu.items {
            if let name = it.representedObject as? String, let row = rows[name],
               let stack = stacks.first(where: { ($0["name"] as? String) == name }) {
                applyRow(row, stack: stack, svcs: services(of: name))
            } else if let ref = it.representedObject as? [String: String], let svcName = ref["service"] {
                let up = services.first(where: { ($0["name"] as? String) == svcName }).flatMap { $0["up"] as? Bool } ?? false
                if it.isEnabled != up { it.isEnabled = up }
            }
        }
        updateBadge()
    }

    private var summaryText: String {
        let up = services.filter { ($0["up"] as? Bool) == true }.count
        var parts = ["\(up) running"]
        if let usage = state["usage"] as? [String: Any], let used = usage["memMB"] as? Double, up > 0,
           let docker = state["docker"] as? [String: Any], let cap = docker["memMB"] as? Double {
            parts.append(String(format: "%.1f of %.1f GB memory", used / 1024, cap / 1024))
        }
        return parts.joined(separator: " · ")
    }

    private func rebuild() {
        rows.removeAll()
        menu.removeAllItems()
        let head = NSMenuItem(title: reachable ? summaryText : "Console not running", action: nil, keyEquivalent: "")
        head.isEnabled = false
        head.tag = 1                                  // refreshed in place by applyState
        menu.addItem(head)
        if !reachable {
            menu.addItem(item("Start InfraPack", #selector(startInfraPack)))
            menu.addItem(.separator())
            menu.addItem(item("Quit InfraPack Menu", #selector(quit), key: "q"))
            return
        }
        if let mem = state["memory"] as? [String: Any], (mem["tooSmall"] as? Bool) == true, let rec = mem["recommendedMB"] as? Int {
            let warn = NSMenuItem(title: String(format: "Docker VM too small — resize to %.1f GiB…", Double(rec) / 1024), action: #selector(openDockerPage), keyEquivalent: "")
            warn.target = self
            if let img = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil) { warn.image = img }
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        if stacks.isEmpty {
            let none = NSMenuItem(title: "Nothing installed yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for stack in stacks {
            guard let name = stack["name"] as? String else { continue }
            let label = stack["label"] as? String ?? name
            let svcs = services(of: name)
            let row = StackRow(name: name, label: label)
            row.onToggle = { [weak self] n in self?.toggleStack(named: n) }
            rows[name] = row
            let holder = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            holder.representedObject = name
            holder.view = row
            menu.addItem(holder)
            applyRow(row, stack: stack, svcs: svcs)
            // "Open …" for every service with a UI; enabled only while it runs (so it can update in place)
            for svc in svcs {
                if let link = svc["link"] as? String, let svcName = svc["name"] as? String {
                    let open = NSMenuItem(title: "Open \(svcName)", action: #selector(openLink(_:)), keyEquivalent: "")
                    open.target = self
                    open.representedObject = ["service": svcName, "url": link]
                    open.indentationLevel = 1
                    open.isEnabled = (svc["up"] as? Bool) == true
                    menu.addItem(open)
                }
            }
        }
        menu.addItem(.separator())
        menu.addItem(item("Install more…", #selector(openCatalog), key: "i"))
        menu.addItem(item("Open console", #selector(openConsole), key: "o"))
        if stacks.count > 1 {
            menu.addItem(.separator())
            menu.addItem(item("Start all", #selector(startAll)))
            menu.addItem(item("Stop all", #selector(stopAll)))
        }
        menu.addItem(.separator())
        menu.addItem(item("Quit InfraPack Menu", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.target = self
        return it
    }

    // ---------------------------------------------------------- actions --
    @objc private func openConsole() { openConsolePage("services") }
    @objc private func openCatalog() { openConsolePage("catalog") }
    @objc private func openDockerPage() { openConsolePage("docker") }
    private var desktopAppInstalled: Bool {
        let app = NSHomeDirectory() + "/Applications/InfraPack.app"
        guard FileManager.default.fileExists(atPath: app + "/Contents/MacOS/InfraPack"),
              let plist = NSDictionary(contentsOfFile: app + "/Contents/Info.plist") else { return false }
        return (plist["CFBundleIdentifier"] as? String)?.hasPrefix("studio.mostlyworks.infrapack") == true
    }
    private func openConsolePage(_ page: String) {
        if desktopAppInstalled, let url = URL(string: "infrapack://\(page)") {
            NSWorkspace.shared.open(url)          // launches or activates the InfraPack app on that page
        } else {
            NSWorkspace.shared.open(consoleURL.appending(fragment: page))
        }
    }
    @objc private func openLink(_ sender: NSMenuItem) {
        if let ref = sender.representedObject as? [String: String], let s = ref["url"], let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func toggleStack(named name: String) {
        let up = services(of: name).contains { ($0["up"] as? Bool) == true }
        busy.insert(name); applyState()
        post("api/action", ["action": up ? "down" : "up", "stacks": [name]]) { self.busy.remove(name); self.applyState() }
    }
    @objc private func startAll() { act("up") }
    @objc private func stopAll() { act("down") }
    private func act(_ action: String) {
        let names = stacks.compactMap { $0["name"] as? String }
        names.forEach { busy.insert($0) }; applyState()
        post("api/action", ["action": action, "stacks": names]) { names.forEach { self.busy.remove($0) }; self.applyState() }
    }

    @objc private func startInfraPack() {
        // the console is down: run `infrapack up` through a login shell so PATH is the user's
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-lc", "infrapack up >/dev/null 2>&1 || ~/.local/bin/infrapack up >/dev/null 2>&1 || /opt/homebrew/bin/infrapack up >/dev/null 2>&1"]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { self.refresh() }
    }
}

extension URL {
    func appending(fragment: String) -> URL {
        var c = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        c.fragment = fragment
        return c.url ?? self
    }
}

let app = NSApplication.shared
let delegate = InfraPackMenu()
app.delegate = delegate
app.run()
