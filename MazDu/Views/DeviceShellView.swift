import SwiftUI

/// Wraps `screenContent` inside the Game Boy shell art, positioned exactly in the
/// shell image's transparent screen cutout (coordinates from D-013/D-014).
struct DeviceShellView<ScreenContent: View, TopLeftContent: View, TopRightContent: View, MiniScreenContent: View, Controls: View>: View {
    @ViewBuilder var screenContent: () -> ScreenContent
    @ViewBuilder var topLeftContent: () -> TopLeftContent
    @ViewBuilder var topRightContent: () -> TopRightContent
    @ViewBuilder var miniScreenContent: () -> MiniScreenContent
    @ViewBuilder var controls: (_ scale: CGFloat) -> Controls

    init(
        @ViewBuilder screenContent: @escaping () -> ScreenContent,
        @ViewBuilder topLeftContent: @escaping () -> TopLeftContent = { EmptyView() },
        @ViewBuilder topRightContent: @escaping () -> TopRightContent = { EmptyView() },
        @ViewBuilder miniScreenContent: @escaping () -> MiniScreenContent = { EmptyView() },
        @ViewBuilder controls: @escaping (_ scale: CGFloat) -> Controls = { _ in EmptyView() }
    ) {
        self.screenContent = screenContent
        self.topLeftContent = topLeftContent
        self.topRightContent = topRightContent
        self.miniScreenContent = miniScreenContent
        self.controls = controls
    }

    private let canvasSize = ShellLayout.canvasSize
    private let screenHole = ShellLayout.mainScreenHole

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / canvasSize.width

            ZStack(alignment: .topLeading) {
                Image("shell_body")
                    .resizable()
                    .interpolation(.none)
                    .frame(width: canvasSize.width * scale, height: canvasSize.height * scale)

                screenContent()
                    .frame(width: screenHole.width * scale, height: screenHole.height * scale)
                    .clipped()
                    .position(x: screenHole.midX * scale, y: screenHole.midY * scale)

                hole(ShellLayout.topLeftHole, scale: scale, content: topLeftContent)
                hole(ShellLayout.topRightHole, scale: scale, content: topRightContent)
                hole(ShellLayout.miniScreenHole, scale: scale, content: miniScreenContent)

                controls(scale)
            }
            .frame(width: canvasSize.width * scale, height: canvasSize.height * scale)
        }
        .aspectRatio(canvasSize.width / canvasSize.height, contentMode: .fit)
    }

    private func hole<Content: View>(_ rect: CGRect, scale: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: rect.width * scale, height: rect.height * scale)
            .clipped()
            .position(x: rect.midX * scale, y: rect.midY * scale)
    }
}

#Preview {
    DeviceShellView {
        Color(red: 0.878, green: 0.973, blue: 0.812)
    }
    .padding()
}
