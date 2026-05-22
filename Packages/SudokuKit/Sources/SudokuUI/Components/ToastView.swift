// ToastView — transient pill notification surface (v2.4 prep).
//
// Used by `MonetizationStateController` to surface purchase / restore results
// without churning the Settings Form. The inline `Label` row in SettingsView
// stays as the a11y / VoiceOver source of truth (`latestMessage`); the toast
// is the visual surface, mounted as an overlay above `RootView`.
//
// Layout: small pill, bottom-center, 24pt from the screen bottom, 16pt
// internal horizontal padding / 10pt vertical. Tint follows the theme's
// `status.success` / `status.error` tokens. Auto-dismiss via a `Task`
// timer keyed off `Toast.duration`.

public import Foundation
public import SwiftUI

// MARK: - Toast

public struct Toast: Equatable, Sendable {
    public enum Style: Sendable, Equatable {
        case success
        case failure
    }

    public let style: Style
    public let message: String
    public let duration: Duration

    public init(
        style: Style,
        message: String,
        duration: Duration = .seconds(3)
    ) {
        self.style = style
        self.message = message
        self.duration = duration
    }
}

// MARK: - ToastController

@MainActor
@Observable
public final class ToastController {

    public private(set) var current: Toast?

    @ObservationIgnored
    private var dismissTask: Task<Void, Never>?

    public init() {}

    /// Show `toast` and schedule auto-dismiss after `toast.duration`.
    /// Replaces any in-flight toast (and cancels its pending dismissal).
    public func show(_ toast: Toast) {
        dismissTask?.cancel()
        current = toast
        let duration = toast.duration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.current = nil
        }
    }

    /// Clear the current toast immediately (used by tests + manual dismiss).
    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }
}

// MARK: - ToastView

public struct ToastView: View {
    private let toast: Toast
    @Environment(\.theme) private var theme

    public init(toast: Toast) {
        self.toast = toast
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.white)
            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(background, in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(toast.message)
    }

    private var iconName: String {
        switch toast.style {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private var background: Color {
        switch toast.style {
        case .success: theme.status.success.resolved
        case .failure: theme.status.error.resolved
        }
    }
}

// MARK: - View overlay helper

public extension View {
    /// Mounts a bottom-center toast overlay driven by `controller.current`.
    /// Use once at the root of a scene (e.g. `RootView`).
    @MainActor
    func toastOverlay(_ controller: ToastController?) -> some View {
        overlay(alignment: .bottom) {
            if let controller, let toast = controller.current {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.message + String(describing: toast.style))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: controller?.current)
    }
}
