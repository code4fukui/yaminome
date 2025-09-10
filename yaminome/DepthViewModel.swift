import Foundation
import UIKit
import ARKit
import Photos

final class DepthViewModel: NSObject, ObservableObject, ARSessionDelegate {
    @Published var depthUIImage: UIImage?
    @Published var useSmoothed: Bool = false

    private let session = ARSession()
    private let processingQueue = DispatchQueue(label: "depth.processing")

    // 表示レンジ（メートル）
    private let minDepth: Float = 0.0
    private let maxDepth: Float = 5.0

    func start() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            print("このデバイスはLiDARのsceneDepthに非対応")
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = useSmoothed ? [.smoothedSceneDepth] : [.sceneDepth]
        config.environmentTexturing = .none
        session.delegate = self
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
    }

    func toggleSmoothing() {
        useSmoothed.toggle()
        start()
    }

    // ARSessionDelegate
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        processingQueue.async { [weak self] in
            guard let self else { return }
            // LiDAR 深度（smoothed優先）
            let depthData = self.useSmoothed ? frame.smoothedSceneDepth : frame.sceneDepth
            guard let depth = depthData?.depthMap else { return }
            if let uiImage = Self.depthPixelBufferToUIImage(depth,
                                                            minDepth: self.minDepth,
                                                            maxDepth: self.maxDepth) {
                DispatchQueue.main.async {
                    self.depthUIImage = uiImage
                }
            }
        }
    }

    // Float32のCVPixelBuffer(メートル) → グレースケールUIImage(0=黒, 5m=白)
    static func depthPixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer,
                                          minDepth: Float,
                                          maxDepth: Float) -> UIImage? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DepthFloat32 ||
              CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_DisparityFloat32 else {
            // 想定は DepthFloat32（メートル）
            return nil
        }

        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRowOut = width // 8bitグレースケールで1pix=1byte

        // 出力バッファ（0-255）
        var outData = [UInt8](repeating: 0, count: width * height)

        // 入力ポインタ
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let src = base.assumingMemoryBound(to: Float32.self)

        let clipMin = minDepth
        let clipMax = maxDepth
        let inv = 1.0 / (clipMax - clipMin)

        // 近→黒/白の向きは好み。ここでは「近い=暗い, 遠い=明るい」
        for y in 0..<height {
            for x in 0..<width {
                let d = src[y * width + x]
                // 無効値（NaN/inf/負）を真っ黒に
                if !d.isFinite || d <= 0 {
                    outData[y * width + x] = 0
                } else {
                    let t = max(0, min(1, 1.0 - (d - clipMin) * Float(inv))) // 0..1
                    outData[y * width + x] = UInt8(t * 255)
                }
            }
        }

        // CGImage生成
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(outData) as CFData) else { return nil }
        guard let cgImage = CGImage(width: width,
                                    height: height,
                                    bitsPerComponent: 8,
                                    bitsPerPixel: 8,
                                    bytesPerRow: bytesPerRowOut,
                                    space: colorSpace,
                                    bitmapInfo: CGBitmapInfo(rawValue: 0),
                                    provider: provider,
                                    decode: nil,
                                    shouldInterpolate: false,
                                    intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // PNG保存（フォトライブラリ）
    func saveCurrentDepthPNG() {
        guard let image = depthUIImage,
              let png = image.pngData() else { return }

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                print("PhotoLibrary権限がありません")
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: png, options: nil)
            }, completionHandler: { success, error in
                if let error { print("保存エラー: \(error)") }
                else { print("保存完了") }
            })
        }
    }
}
