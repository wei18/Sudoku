// B-6 spike (#1029, U-10): does a real AdMob BannerView (UIViewRepresentable)
// render at non-zero size inside `tabViewBottomAccessory`, and does the SDK's
// own impression callback fire? Mirrors the shape of the app's live bridge
// (AdsAdMob/LiveAdMobBridge.swift): a bare representable mounting a retained
// BannerView, no explicit SwiftUI frame. Google's public test ad unit + test
// App ID only — no production identifiers.
import SwiftUI
import GoogleMobileAds

@main
struct B6App: App {
    init() {
        MobileAds.shared.start { status in
            NSLog("B6SPIKE MobileAds started: %@",
                  status.adapterStatusesByClassName.keys.joined(separator: ","))
        }
    }

    var body: some Scene {
        WindowGroup { B6Root() }
    }
}

struct B6Root: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "calendar") {
                ScrollView {
                    LazyVStack {
                        Text("B-6 accessory × AdMob spike").font(.headline)
                        ForEach(0..<60) { idx in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.teal.opacity(0.4))
                                .frame(height: 60)
                                .overlay(Text("row \(idx)"))
                        }
                    }
                    .padding()
                }
            }
            Tab("Practice", systemImage: "square.grid.3x3") {
                Color.orange.ignoresSafeArea()
            }
            Tab("Progress", systemImage: "chart.bar") {
                Color.purple.ignoresSafeArea()
            }
        }
        .tabViewBottomAccessory {
            BannerAccessory()
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

struct BannerAccessory: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        BannerRepresentable()
            .onAppear {
                NSLog("B6SPIKE accessory placement on appear: %@",
                      String(describing: placement))
            }
            .onChange(of: placement) { _, new in
                NSLog("B6SPIKE accessory placement changed: %@",
                      String(describing: new))
            }
    }
}

struct BannerRepresentable: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> BannerView {
        let view = BannerView(adSize: AdSizeBanner)
        // Google's PUBLIC demo banner unit (developers.google.com/admob/ios/test-ads)
        view.adUnitID = "ca-app-pub-3940256099942544/2934735716"
        view.delegate = context.coordinator
        view.load(Request())
        NSLog("B6SPIKE banner load requested")
        return view
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}

    final class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            NSLog("B6SPIKE didReceiveAd bounds=%@ intrinsic=%@",
                  NSCoder.string(for: bannerView.bounds.size),
                  NSCoder.string(for: bannerView.intrinsicContentSize))
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: any Error) {
            NSLog("B6SPIKE didFailToReceiveAd: %@", error.localizedDescription)
        }

        func bannerViewDidRecordImpression(_ bannerView: BannerView) {
            NSLog("B6SPIKE IMPRESSION recorded bounds=%@ window=%@",
                  NSCoder.string(for: bannerView.bounds.size),
                  bannerView.window == nil ? "nil" : "attached")
        }

        func bannerViewDidRecordClick(_ bannerView: BannerView) {
            NSLog("B6SPIKE click recorded")
        }
    }
}
