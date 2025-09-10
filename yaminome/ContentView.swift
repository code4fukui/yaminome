import SwiftUI

class OrientationObserver: ObservableObject {
    @Published var orientation: UIDeviceOrientation = UIDevice.current.orientation

    init() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.orientation = UIDevice.current.orientation
        }
    }
}

struct ContentView: View {
    @StateObject private var model = DepthViewModel()
    @StateObject private var oo = OrientationObserver()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = model.depthUIImage {
                    let a = angle(for: oo.orientation)

                    // 元画像サイズ
                    let iw = img.size.width
                    let ih = img.size.height

                    // 回転後のアスペクト比（90°時は h/w に入れ替わる）
                    let isRotated90 = abs(a.degrees).truncatingRemainder(dividingBy: 180) != 0
                    let aspect = isRotated90 ? (ih / iw) : (iw / ih)

                    // 画面の幅に合わせて高さを決定（幅いっぱい）
                    let targetW = geo.size.width
                    let targetH = targetW / aspect

                    Image(uiImage: img)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: targetW, height: targetH)
                        .rotationEffect(a) // 画面向きに追従
                        // 中央に配置（回転で外れないように）
                        .position(x: geo.size.width/2, y: geo.size.height/2)
                        .animation(.easeInOut(duration: 0.15), value: oo.orientation)
                } else {
                    ProgressView("LiDARを初期化中…").foregroundColor(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .ignoresSafeArea()
            .onAppear { model.start() }
            .onDisappear { model.stop() }
        }
    }

    func angle(for o: UIDeviceOrientation) -> Angle {
        switch o {
        case .portrait:           return .degrees(90)
        case .landscapeLeft:      return .degrees(0)   // ホームバー右
        case .landscapeRight:     return .degrees(180)  // ホームバー左
        case .portraitUpsideDown: return .degrees(270)
        default:                  return .degrees(0)
        }
    }
}
