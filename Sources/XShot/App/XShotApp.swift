import AppKit
import Combine
import SwiftUI

@main
public struct XShotLauncher {
    @MainActor
    public static func main() {
        let app = NSApplication.shared
        let delegate = XShotAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
public final class XShotAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var popoverHost: NSHostingController<MenuBarView>!
    private var appState: AppState!
    private var cancellables: Set<AnyCancellable> = []

    public func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeLocaleStore.shared.applyAppearanceToApp()
        SystemWallpaperManager.shared.prewarmAsync(desktopLabel: L10n.t(.wallpaperDesktopName))
        installStandardMenus()
        appState = AppState()
        appState.startBackgroundServices()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon(isRecording: false)

        if let button = statusItem.button {
            button.action = #selector(togglePopover(_:))
            button.target = self
        }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance

        let host = NSHostingController(
            rootView: MenuBarView(
                appState: appState,
                permissions: appState.permissions,
                dismissPopover: { [weak pop] in
                    pop?.performClose(nil)
                }
            )
        )
        host.sizingOptions = [.preferredContentSize]
        pop.contentViewController = host
        self.popover = pop
        self.popoverHost = host
        syncPopoverSize()

        appState.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] recording in
                self?.updateStatusItemIcon(isRecording: recording)
                self?.syncPopoverSize()
            }
            .store(in: &cancellables)

        appState.$recentItems
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncPopoverSize()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            appState.$enableKeystrokesByDefault,
            appState.$enableTypingFocusZoom,
            appState.permissions.$hasAccessibility
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.syncPopoverSize()
            }
        }
        .store(in: &cancellables)

        ThemeLocaleStore.shared.$language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { [weak self] in
                    self?.syncPopoverSize()
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest3(
            appState.authManager.$session,
            appState.updater.$status,
            appState.store.$entitlement
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.syncPopoverSize()
            }
        }
        .store(in: &cancellables)

        ThemeLocaleStore.shared.$appearanceMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in
                self?.popover?.appearance = mode.nsAppearance
                // Ensure the menu bar status icon ALWAYS follows macOS's actual menu bar appearance!
                self?.statusItem?.button?.appearance = nil
                self?.statusItem?.button?.window?.appearance = nil
            }
            .store(in: &cancellables)
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if appState?.authManager.handleCallbackURL(url) == true {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private func syncPopoverSize() {
        guard let host = popoverHost, let pop = popover else { return }
        host.view.layoutSubtreeIfNeeded()
        let fitted = host.sizeThatFits(in: CGSize(width: 340, height: 800))
        let target = NSSize(width: 340, height: max(320, ceil(fitted.height) + 6))
        host.preferredContentSize = target
        pop.contentSize = target
    }

    private func installStandardMenus() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.t(.quitXShotMenu), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func updateStatusItemIcon(isRecording: Bool) {
        guard let button = statusItem.button else { return }
        button.appearance = nil
        button.window?.appearance = nil
        let symbolName = isRecording ? "record.circle.fill" : "camera.aperture"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "XShot")?
            .withSymbolConfiguration(config)
        image?.isTemplate = !isRecording
        button.image = image
        if isRecording {
            button.contentTintColor = .systemRed
        } else {
            button.contentTintColor = nil
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.appearance = ThemeLocaleStore.shared.appearanceMode.nsAppearance
            appState.permissions.refresh()
            appState.refreshClipboardStatus()
            syncPopoverSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            DispatchQueue.main.async { [weak self] in
                self?.syncPopoverSize()
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
