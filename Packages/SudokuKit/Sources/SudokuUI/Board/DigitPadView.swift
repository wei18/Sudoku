// DigitPadView — 1–9 + clear, plus undo / redo / pencil toggle.
//
// Per docs/designs/05-board.md. Buttons are ≥44 pt tall for touch comfort.

import SwiftUI

struct DigitPadView: View {
    let pencilMode: Bool
    let canUndo: Bool
    let canRedo: Bool
    let onDigit: (Int) -> Void
    let onClear: () -> Void
    let onTogglePencil: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            controlRow
            digitRow
            HStack {
                Spacer()
                Button(action: onClear) {
                    Label("Clear", systemImage: "delete.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                Spacer()
            }
        }
        .padding(.horizontal, 16)
    }

    private var controlRow: some View {
        HStack(spacing: 24) {
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .disabled(!canUndo)
            .accessibilityLabel("Undo")

            Button(action: onRedo) {
                Image(systemName: "arrow.uturn.forward")
            }
            .disabled(!canRedo)
            .accessibilityLabel("Redo")

            Button(action: onTogglePencil) {
                Image(systemName: pencilMode ? "pencil" : "pencil.slash")
                    .foregroundStyle(pencilMode
                        ? theme.accent.primary.resolved
                        : theme.text.primary.resolved)
            }
            .accessibilityLabel("Pencil")
            .accessibilityValue(pencilMode ? "On" : "Off")
        }
        .font(.title2)
    }

    private var digitRow: some View {
        HStack(spacing: 6) {
            ForEach(1...9, id: \.self) { digit in
                Button {
                    onDigit(digit)
                } label: {
                    Text("\(digit)")
                        .frame(minWidth: 30, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Digit \(digit)")
            }
        }
    }
}
