import SwiftUI
import UIKit

// Linked from NativeRuffle/libruffle_ios.a by the dedicated experimental CI.
// This C ABI returns a retained native UIKit PlayerController. It does not
// create a WKWebView or call into the JavaScript/WASM Ruffle build.
@_silgen_name("shiguang_native_player_create")
private func shiguang_native_player_create(
    _ url: UnsafePointer<CChar>, _ quality: UInt32
) -> UnsafeMutableRawPointer?

struct NativeRuffleController: UIViewControllerRepresentable {
    let url: URL
    let quality: GameQualityPreset
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let level: UInt32
        switch quality {
        case .saving: level = 0
        case .balanced: level = 1
        case .ultra: level = 2
        }
        let raw = url.absoluteString.withCString { pointer in
            shiguang_native_player_create(pointer, level)
        }
        guard let raw else {
            let fallback = UIViewController()
            fallback.view.backgroundColor = .black
            DispatchQueue.main.async {
                onError("原生 Ruffle 初始化失败。请导出诊断信息，并切换回网页引擎测试。")
            }
            return fallback
        }
        LaunchDiagnostics.log("[原生 Ruffle] UIKit Metal PlayerController 已建立，SWF URL：\(url.path)，画质等级：\(level)")
        return Unmanaged<UIViewController>.fromOpaque(raw).takeRetainedValue()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
        LaunchDiagnostics.log("[原生 Ruffle] 退出播放器，交由 UIKit 释放 PlayerController")
    }
}
