import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Foundation

@MainActor
public final class PermissionManager: ObservableObject {
    @Published public var hasScreenRecording: Bool = false
    @Published public var hasMicrophone: Bool = false
    @Published public var hasCamera: Bool = false
    @Published public var hasAccessibility: Bool = false
    @Published public var hasInputMonitoring: Bool = false
    private var verifiedByScreenCaptureKit: Bool = false

    public var canCaptureKeystrokes: Bool {
        hasAccessibility || hasInputMonitoring
    }

    public init() {
        refresh()
    }

    public func refresh() {
        hasScreenRecording = verifiedByScreenCaptureKit || CGPreflightScreenCaptureAccess()
        hasMicrophone = (AVCaptureDevice.authorizationStatus(for: .audio) == .authorized)
        hasCamera = (AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
        #if MAC_APP_STORE
        hasAccessibility = false
        hasInputMonitoring = false
        #else
        hasAccessibility = AXIsProcessTrusted()
        hasInputMonitoring = CGPreflightListenEventAccess()
        #endif
    }

    public func markScreenRecordingVerified() {
        verifiedByScreenCaptureKit = true
        hasScreenRecording = true
    }

    public func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refresh()
        }
    }

    public func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    public func requestCamera() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
    }

    public func requestAccessibilityAndInputMonitoring() {
        #if !MAC_APP_STORE
        // Prompt macOS standard Accessibility trust dialog (enables BOTH global keystrokes & exact input caret focus bounds!)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
        #endif
    }

    public func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func openInputMonitoringSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}
