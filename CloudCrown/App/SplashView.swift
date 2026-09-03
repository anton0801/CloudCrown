import SwiftUI

struct SplashView: View {
    @State private var glow = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SkyBackground()
                Color.black.ignoresSafeArea()
                    .opacity(0.5)
                Image("crown-load")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .blur(radius: 5)
                VStack(spacing: SkySpacing.xl) {
                    ZStack {
                        Circle()
                            .fill(SkyPalette.glow(SkyPalette.lightBlue, opacity: 0.5))
                            .frame(width: 200, height: 200)
                            .scaleEffect(glow ? 1.08 : 0.92)
                        Circle()
                            .fill(SkyPalette.surface)
                            .frame(width: 104, height: 104)
                            .shadow(color: SkyPalette.azure.opacity(0.25), radius: 24, y: 10)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(SkyPalette.crownGradient)
                    }
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: glow)

                    VStack(spacing: SkySpacing.s) {
                        Text("CloudCrown")
                            .font(SkyFont.display(30))
                            .foregroundColor(.white)
                        Text("Preparing your data")
                            .font(SkyFont.body(14))
                            .foregroundColor(.white.opacity(0.9))
                    }

                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: SkyPalette.azure))
                }
            }
            .onAppear { glow = true }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    SplashView()
}

struct NoNetworkView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                SkyPalette.canvas.ignoresSafeArea()
                SkyBackground()
                Color.black.ignoresSafeArea()
                    .opacity(0.5)
                Image("crown-load")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .ignoresSafeArea()
                    .blur(radius: 5)
                VStack(spacing: SkySpacing.l) {
                    ZStack {
                        Circle()
                            .fill(SkyPalette.danger.opacity(0.10))
                            .frame(width: 130, height: 130)
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 42, weight: .light))
                            .foregroundColor(SkyPalette.danger)
                    }
                    Image("crown-e")
                        .resizable()
                        .frame(width: 310, height: 300)
                    LightningLine()
                        .stroke(SkyPalette.danger.opacity(0.6),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        .frame(height: 10)
                        .padding(.horizontal, SkySpacing.xxl)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { }
        }.ignoresSafeArea()
    }
}
