import SwiftUI
import ServiceManagement
import AppKit

@main
struct ChromeHeadlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Prevent multiple instances
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!).count > 1 {
            // Show modal alert
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Already Running"
                alert.informativeText = "TahoeElectronFix is already running. Check your menu bar."
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.runModal()
                
                // Quit after user dismisses alert
                NSApplication.shared.terminate(nil)
            }
        }
    }
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private let defaults = UserDefaults.standard
    private let stateKey = "ChromeHeadlessState"
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 App launched - applicationDidFinishLaunching called")
        
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        print("✅ Set activation policy to .accessory")
        
        // Check if this is the first launch
        let isFirstLaunch = !defaults.bool(forKey: "HasLaunchedBefore")
        
        if isFirstLaunch {
            // First launch: initialize state to ON
            defaults.set(true, forKey: "HasLaunchedBefore")
            defaults.set(true, forKey: stateKey)
            print("🆕 First launch - initializing state to ON")
            
            // Force set environment variable to 1 on first launch
            setEnvironmentVariable(to: true)
        } else {
            // Subsequent launches: restore the persisted state
            let persistedState = getCurrentState()
            print("📊 Current persisted state: \(persistedState ? "ON (1)" : "OFF (0)")")
            setEnvironmentVariable(to: persistedState)
        }
        
        // Setup menu bar
        setupMenuBar()
        print("📋 Menu bar setup attempted")
        
        // Update icon based on current state
        updateIcon()
        print("🎨 Icon update called")
        
        print("✅ Setup complete!")
    }
    
    private func setupMenuBar() {
        // Create status item with fixed length
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        guard let button = statusItem.button else {
            print("❌ ERROR: Could not get status item button!")
            return
        }
        
        // Set button properties
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        // Create menu
        menu = NSMenu()
        
        // Start at Launch menu item with icon
        let startAtLoginItem = NSMenuItem(
            title: "Start at Launch",
            action: #selector(toggleStartAtLogin),
            keyEquivalent: ""
        )
        startAtLoginItem.target = self
        startAtLoginItem.state = isStartAtLoginEnabled() ? .on : .off
        
        // Add icon for Start at Launch
        if let startIcon = NSImage(systemSymbolName: "power.circle", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            startAtLoginItem.image = startIcon.withSymbolConfiguration(config)
        }
        
        menu.addItem(startAtLoginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Offer coffee menu item with icon
        let coffeeItem = NSMenuItem(
            title: "Offer a coffee to the dev...",
            action: #selector(openKofiPage),
            keyEquivalent: ""
        )
        coffeeItem.target = self
        
        // Add coffee icon
        if let coffeeIcon = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            coffeeItem.image = coffeeIcon.withSymbolConfiguration(config)
        }
        
        menu.addItem(coffeeItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit menu item with icon
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self
        
        // Add icon for Quit
        if let quitIcon = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            quitItem.image = quitIcon.withSymbolConfiguration(config)
        }
        
        menu.addItem(quitItem)
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        
        if event.type == .rightMouseUp {
            // Right click - show menu
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            // Left click - toggle state
            toggleChromeHeadless()
        }
    }
    
    @objc private func toggleChromeHeadless() {
        let currentState = getCurrentState()
        let newState = !currentState
        
        print("🔄 Toggling state from \(currentState ? "ON" : "OFF") to \(newState ? "ON" : "OFF")")
        
        defaults.set(newState, forKey: stateKey)
        setEnvironmentVariable(to: newState)
        updateIcon()
    }
    
    private func getCurrentState() -> Bool {
        return defaults.bool(forKey: stateKey)
    }
    
    private func setEnvironmentVariable(to value: Bool) {
        let envValue = value ? "1" : "0"
        
        print("🌍 Setting CHROME_HEADLESS to \(envValue)")
        
        // Run launchctl through a proper shell environment
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "launchctl setenv CHROME_HEADLESS \(envValue)"]
        
        // Capture output to see what's happening
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if task.terminationStatus == 0 {
                print("✅ Environment variable set successfully via launchctl")
            } else {
                print("⚠️ launchctl returned status \(task.terminationStatus)")
                if !output.isEmpty {
                    print("Output: \(output)")
                }
            }
        } catch {
            print("❌ Error running launchctl: \(error)")
        }
        
        // Verify it was set
        verifyEnvironmentVariable()
    }
    
    private func verifyEnvironmentVariable() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "launchctl getenv CHROME_HEADLESS"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if !output.isEmpty {
                print("✅ Verified: CHROME_HEADLESS = \(output)")
            } else {
                print("⚠️ Could not verify environment variable")
            }
        } catch {
            print("❌ Error verifying: \(error)")
        }
    }
    
    private func updateIcon() {
        guard let button = statusItem?.button else {
            print("❌ Cannot update icon - button is nil")
            return
        }
        
        let isEnabled = getCurrentState()
        
        // Use atom symbol
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let imageName = "atom"
        
        if let image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil) {
            let finalImage = image.withSymbolConfiguration(config)
            button.image = finalImage
            button.image?.isTemplate = true
            
            if isEnabled {
                // Solid color for enabled state
                button.contentTintColor = nil
            } else {
                // Grey for disabled state
                button.contentTintColor = NSColor.gray.withAlphaComponent(0.5)
            }
        }
        
        // Set tooltip (hover text)
        let stateValue = isEnabled ? "1" : "0"
        button.toolTip = "CHROME_HEADLESS \(stateValue)"
    }
    
    @objc private func toggleStartAtLogin() {
        do {
            if isStartAtLoginEnabled() {
                try SMAppService.mainApp.unregister()
                print("✅ Unregistered from start at login")
            } else {
                try SMAppService.mainApp.register()
                print("✅ Registered for start at login")
            }
            updateStartAtLoginMenuItem()
        } catch {
            print("❌ Error toggling start at login: \(error)")
        }
    }
    
    private func isStartAtLoginEnabled() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    private func updateStartAtLoginMenuItem() {
        if let menuItem = menu.item(withTitle: "Start at Launch") {
            menuItem.state = isStartAtLoginEnabled() ? .on : .off
        }
    }
    
    @objc private func openKofiPage() {
        if let url = URL(string: "https://ko-fi.com/realabitbol") {
            NSWorkspace.shared.open(url)
            print("☕ Opening Ko-fi page")
        }
    }
    
    @objc private func quitApp() {
        print("👋 Quitting app")
        NSApplication.shared.terminate(nil)
    }
}
