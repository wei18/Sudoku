// B-7 spike (#1029, U-9): does GlassEffectContainer merge child shapes when the
// children use the SYSTEM button style (.buttonStyle(.glass)), and when they use
// explicit .glassEffect()? design.md §4.6 says shapes blend as they near each
// other, controlled by the container's spacing value.
//
// Layout: two columns of rows. Left column = .buttonStyle(.glass) children,
// right column = .glassEffect() children. Rows step the HStack item spacing
// from wide (40) to near (2). Every row sits in its own
// GlassEffectContainer(spacing: 40). If §4.6 is right, the near rows merge
// into one continuous glass shape; if error #8's misreading were right,
// nothing merges.
import SwiftUI

@main
struct B7App: App {
    var body: some Scene {
        WindowGroup { B7Root() }
    }
}

struct B7Root: View {
    let itemSpacings: [CGFloat] = [40, 24, 12, 6, 2]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.orange, .pink, .purple, .blue],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Text("B-7 GlassEffectContainer spike")
                    .font(.headline).foregroundStyle(.white)

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 22) {
                        Text(".buttonStyle(.glass)")
                            .font(.caption2).foregroundStyle(.white)
                        ForEach(itemSpacings, id: \.self) { gap in
                            row(gap: gap) {
                                Button { } label: { Image(systemName: "arrow.uturn.backward") }
                                    .buttonStyle(.glass)
                                Button { } label: { Image(systemName: "arrow.uturn.forward") }
                                    .buttonStyle(.glass)
                                Button { } label: { Image(systemName: "pencil") }
                                    .buttonStyle(.glass)
                            }
                        }
                    }
                    VStack(spacing: 22) {
                        Text(".glassEffect()")
                            .font(.caption2).foregroundStyle(.white)
                        ForEach(itemSpacings, id: \.self) { gap in
                            row(gap: gap) {
                                Image(systemName: "arrow.uturn.backward")
                                    .frame(width: 36, height: 36)
                                    .glassEffect()
                                Image(systemName: "arrow.uturn.forward")
                                    .frame(width: 36, height: 36)
                                    .glassEffect()
                                Image(systemName: "pencil")
                                    .frame(width: 36, height: 36)
                                    .glassEffect()
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)

                VStack(spacing: 8) {
                    Text("control: NO container, .buttonStyle(.glass), gap 2")
                        .font(.caption2).foregroundStyle(.white)
                    HStack(spacing: 2) {
                        Button { } label: { Image(systemName: "arrow.uturn.backward") }
                            .buttonStyle(.glass)
                        Button { } label: { Image(systemName: "arrow.uturn.forward") }
                            .buttonStyle(.glass)
                        Button { } label: { Image(systemName: "pencil") }
                            .buttonStyle(.glass)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func row(gap: CGFloat, @ViewBuilder content: () -> some View) -> some View {
        VStack(spacing: 4) {
            GlassEffectContainer(spacing: 40) {
                HStack(spacing: gap) { content() }
            }
            Text("gap \(Int(gap))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.8))
        }
    }
}
