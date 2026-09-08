// Screenshot canvas lifecycle adapted from Expo SecureWindowCanvas (MIT).
// https://github.com/expo/expo/pull/49372
import UIKit

/// 采用 Expo 的安全输入框图层方案，在小程序受限页面展示期间保护所在窗口。
/// 依赖系统安全输入框的绘制行为，不是 iOS 官方的任意视图防截屏 API。
final class DMPScreenShotProtectionController {
    private var canvas: DMPSecureWindowCanvas?

    @discardableResult
    @MainActor
    func setProtected(_ protected: Bool, view: UIView) -> Bool {
        guard protected else {
            reset()
            return true
        }
        guard let window = view.window else { return false }
        if canvas?.view === window {
            return true
        }
        // 先确认新容器挂载成功，失败时保留现有保护，允许后续生命周期重试。
        guard let nextCanvas = DMPSecureWindowCanvas(protecting: window) else {
            return false
        }
        canvas?.restore()
        canvas = nextCanvas
        return true
    }

    @MainActor
    func reset() {
        canvas?.restore()
        canvas = nil
    }
}

@MainActor
private final class DMPSecureWindowCanvas {
    private let textField: UITextField
    private let originalParent: CALayer
    private let originalIndex: UInt32
    private(set) weak var view: UIView?

    init?(protecting view: UIWindow) {
        guard let parent = view.layer.superlayer else { return nil }
        let index = parent.sublayers?.firstIndex(where: { $0 === view.layer }) ?? 0
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        field.backgroundColor = .clear
        // 使用父图层坐标系，保留目标视图原有的位置和尺寸。
        field.frame = view.bounds
        // 与 Expo 一致：只挂载 layer，不插入 UIView 层级或读取 subviews。
        parent.addSublayer(field.layer)
        guard let secureLayer = field.layer.sublayers?.first else {
            field.layer.removeFromSuperlayer()
            return nil
        }
        view.layer.removeFromSuperlayer()
        secureLayer.addSublayer(view.layer)
        textField = field
        originalParent = parent
        originalIndex = UInt32(index)
        self.view = view
    }

    func restore() {
        defer { textField.layer.removeFromSuperlayer() }
        guard let view else { return }
        view.layer.removeFromSuperlayer()
        originalParent.insertSublayer(view.layer, at: min(originalIndex, UInt32(originalParent.sublayers?.count ?? 0)))
        view.superview?.setNeedsLayout()
        view.setNeedsLayout()
        self.view = nil
    }
}
