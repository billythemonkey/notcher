//
//  AppDelegate.swift
//  notchprompt
//
//  Created by Saif on 2026-02-08.
//

import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private enum Shortcut: String, CaseIterable {
        case startPause = "p"
        case reset = "r"
        case jumpBack = "j"
        case togglePrivacy = "h"
        case toggleOverlay = "o"
        case speedUp = "="
        case speedDown = "-"
        case toggleTranslation = "t"
    }

    private let shortcutModifiers: NSEvent.ModifierFlags = [.command, .option]

    private let model = PrompterModel.shared

    private var statusItem: NSStatusItem?
    private var overlayController: OverlayWindowController?
    private var settingsWindowController: SettingsWindowController?
    private var scriptEditorWindowController: ScriptEditorWindowController?
    private var cancellables: Set<AnyCancellable> = []

    private var startPauseItem: NSMenuItem?
    private var showOverlayItem: NSMenuItem?
    private var privacyModeItem: NSMenuItem?
    private var speedUpItem: NSMenuItem?
    private var speedDownItem: NSMenuItem?
    private var translationItem: NSMenuItem?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.loadFromDefaults()
        overlayController = OverlayWindowController(model: model)
        overlayController?.setVisible(model.isOverlayVisible)

#if DEBUG
        ScreenSelectionSelfTests.run()
        runShortcutSelfChecks()
#endif

        wireModel()
        setupStatusBar()
        setupKeyboardShortcuts()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveToDefaults()
        removeKeyboardShortcuts()
        cancellables.removeAll()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if localKeyMonitor == nil || globalKeyMonitor == nil {
            setupKeyboardShortcuts()
        }
    }

    private func wireModel() {
        model.$privacyModeEnabled
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.overlayController?.setPrivacyMode(enabled)
            }
            .store(in: &cancellables)
        
        model.$isOverlayVisible
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                self?.overlayController?.setVisible(isVisible)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$overlayWidth, model.$overlayHeight)
            .removeDuplicates { lhs, rhs in
                Int(lhs.0) == Int(rhs.0) && Int(lhs.1) == Int(rhs.1)
            }
            .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)

        model.$selectedScreenID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
#if DEBUG
                print("[Notchprompt] didChangeScreenParametersNotification")
#endif
                self?.overlayController?.reposition()
            }
            .store(in: &cancellables)

        Publishers.MergeMany(
            model.$script.map { _ in () }.eraseToAnyPublisher(),
            model.$isRunning.map { _ in () }.eraseToAnyPublisher(),
            model.$privacyModeEnabled.map { _ in () }.eraseToAnyPublisher(),
            model.$speedPointsPerSecond.map { _ in () }.eraseToAnyPublisher(),
            model.$fontSize.map { _ in () }.eraseToAnyPublisher(),
            model.$overlayWidth.map { _ in () }.eraseToAnyPublisher(),
            model.$overlayHeight.map { _ in () }.eraseToAnyPublisher(),
            model.$countdownSeconds.map { _ in () }.eraseToAnyPublisher(),
            model.$countdownBehavior.map { _ in () }.eraseToAnyPublisher(),
            model.$scrollMode.map { _ in () }.eraseToAnyPublisher(),
            model.$selectedScreenID.map { _ in () }.eraseToAnyPublisher(),
            model.$isLiveTranslationMode.map { _ in () }.eraseToAnyPublisher(),
            model.$targetLanguageCode.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.model.saveToDefaults()
        }
        .store(in: &cancellables)
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "NP"
        item.button?.toolTip = "Notchprompt"

        let menu = NSMenu()

        let startPause = NSMenuItem(
            title: "Start/Pause (Option+Command+P)",
            action: #selector(toggleRunning),
            keyEquivalent: Shortcut.startPause.rawValue
        )
        startPause.target = self
        startPause.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(startPause)
        startPauseItem = startPause

        let reset = NSMenuItem(
            title: "Reset Scroll (Option+Command+R)",
            action: #selector(resetScroll),
            keyEquivalent: Shortcut.reset.rawValue
        )
        reset.target = self
        reset.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(reset)

        let jumpBack = NSMenuItem(
            title: "Jump Back 5s (Option+Command+J)",
            action: #selector(jumpBack),
            keyEquivalent: Shortcut.jumpBack.rawValue
        )
        jumpBack.target = self
        jumpBack.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(jumpBack)

        let privacyMode = NSMenuItem(
            title: "Privacy Mode (Option+Command+H)",
            action: #selector(togglePrivacyMode),
            keyEquivalent: Shortcut.togglePrivacy.rawValue
        )
        privacyMode.target = self
        privacyMode.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(privacyMode)
        privacyModeItem = privacyMode

        let showOverlay = NSMenuItem(
            title: "Show Overlay (Option+Command+O)",
            action: #selector(toggleOverlayVisibility),
            keyEquivalent: Shortcut.toggleOverlay.rawValue
        )
        showOverlay.target = self
        showOverlay.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(showOverlay)
        showOverlayItem = showOverlay

        let speedUp = NSMenuItem(
            title: "Increase Speed (Option+Command+=)",
            action: #selector(increaseSpeed),
            keyEquivalent: Shortcut.speedUp.rawValue
        )
        speedUp.target = self
        speedUp.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(speedUp)
        speedUpItem = speedUp

        let speedDown = NSMenuItem(
            title: "Decrease Speed (Option+Command+-)",
            action: #selector(decreaseSpeed),
            keyEquivalent: Shortcut.speedDown.rawValue
        )
        speedDown.target = self
        speedDown.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(speedDown)
        speedDownItem = speedDown

        menu.addItem(.separator())

        let translation = NSMenuItem(
            title: "Live Translation (Option+Command+T)",
            action: #selector(toggleTranslation),
            keyEquivalent: Shortcut.toggleTranslation.rawValue
        )
        translation.target = self
        translation.keyEquivalentModifierMask = shortcutModifiers
        menu.addItem(translation)
        translationItem = translation

        menu.addItem(.separator())

        let openScriptEditor = NSMenuItem(title: "Script Editor…", action: #selector(openScriptEditorWindow), keyEquivalent: "")
        openScriptEditor.target = self
        menu.addItem(openScriptEditor)

        menu.addItem(.separator())

        let open = NSMenuItem(title: "Settings…", action: #selector(openMainWindow), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Notchprompt", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    // MARK: - Actions

    @objc private func toggleRunning() {
        model.toggleRunning()
    }

    @objc private func resetScroll() {
        model.resetScroll()
    }

    @objc private func jumpBack() {
        model.jumpBack(seconds: 5)
    }

    @objc private func togglePrivacyMode() {
        model.privacyModeEnabled.toggle()
    }
    
    @objc private func toggleOverlayVisibility() {
        model.isOverlayVisible.toggle()
    }

    @objc private func increaseSpeed() {
        model.adjustSpeed(delta: PrompterModel.speedStep)
    }

    @objc private func decreaseSpeed() {
        model.adjustSpeed(delta: -PrompterModel.speedStep)
    }

    @objc private func toggleTranslation() {
        model.isLiveTranslationMode.toggle()
        let manager = LiveTranslationManager.shared
        if model.isLiveTranslationMode {
            manager.targetLanguageCode = model.targetLanguageCode
            manager.startListening()
        } else {
            manager.stopListening()
        }
    }

    @objc private func openMainWindow() {
        Task { @MainActor in
            if settingsWindowController == nil {
                settingsWindowController = SettingsWindowController()
            }
            settingsWindowController?.show()
        }
    }
    
    @objc private func openScriptEditorWindow() {
        Task { @MainActor in
            if scriptEditorWindowController == nil {
                scriptEditorWindowController = ScriptEditorWindowController()
            }
            scriptEditorWindowController?.show()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func setupKeyboardShortcuts() {
        removeKeyboardShortcuts()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleShortcut(event) == true {
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.handleShortcut(event)
        }
    }

    private func removeKeyboardShortcuts() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
    }

    @discardableResult
    private func handleShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = shortcut(charactersIgnoringModifiers: event.charactersIgnoringModifiers, flags: flags) else {
            return false
        }

        switch key {
        case .startPause:
            model.toggleRunning()
            return true
        case .reset:
            model.resetScroll()
            return true
        case .jumpBack:
            model.jumpBack(seconds: 5)
            return true
        case .togglePrivacy:
            model.privacyModeEnabled.toggle()
            return true
        case .toggleOverlay:
            model.isOverlayVisible.toggle()
            return true
        case .speedUp:
            model.adjustSpeed(delta: PrompterModel.speedStep)
            return true
        case .speedDown:
            model.adjustSpeed(delta: -PrompterModel.speedStep)
            return true
        case .toggleTranslation:
            toggleTranslation()
            return true
        }
    }

    private func shortcut(
        charactersIgnoringModifiers: String?,
        flags: NSEvent.ModifierFlags
    ) -> Shortcut? {
        guard flags == shortcutModifiers else { return nil }
        guard var raw = charactersIgnoringModifiers?.lowercased(), !raw.isEmpty else {
            return nil
        }

        if raw == "+" {
            raw = Shortcut.speedUp.rawValue
        } else if raw == "_" {
            raw = Shortcut.speedDown.rawValue
        }

        return Shortcut(rawValue: raw)
    }

#if DEBUG
    private func runShortcutSelfChecks() {
        func check(_ key: String, _ expected: Shortcut?) {
            let result = shortcut(charactersIgnoringModifiers: key, flags: shortcutModifiers)
            assert(result == expected, "Unexpected shortcut map for \(key). expected=\(String(describing: expected)) got=\(String(describing: result))")
        }

        check("p", .startPause)
        check("r", .reset)
        check("j", .jumpBack)
        check("h", .togglePrivacy)
        check("o", .toggleOverlay)
        check("=", .speedUp)
        check("+", .speedUp)
        check("-", .speedDown)
        check("_", .speedDown)

        check("t", .toggleTranslation)

        let invalid = shortcut(charactersIgnoringModifiers: "p", flags: [.command])
        assert(invalid == nil, "Shortcuts should require exact Option+Command modifiers")
    }
#endif

    // MARK: - Menu Validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem === startPauseItem {
            menuItem.title = model.isRunning ? "Pause (Option+Command+P)" : "Start (Option+Command+P)"
            return true
        }

        if menuItem === privacyModeItem {
            menuItem.state = model.privacyModeEnabled ? .on : .off
            return true
        }
        
        if menuItem === showOverlayItem {
            menuItem.state = model.isOverlayVisible ? .on : .off
            return true
        }

        if menuItem === speedUpItem || menuItem === speedDownItem {
            return true
        }

        if menuItem === translationItem {
            menuItem.state = model.isLiveTranslationMode ? .on : .off
            return true
        }

        return true
    }
}
