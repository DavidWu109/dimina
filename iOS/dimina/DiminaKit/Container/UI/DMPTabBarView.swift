//
//  DMPTabBarView.swift
//  dimina
//
//  Mini-app 底部 tabBar 组件。根据 app-config.json 的 tabBar 段渲染。
//

import Foundation
import UIKit

public protocol DMPTabBarViewDelegate: AnyObject {
    /// 用户点击了 tabBar 上的某一项。index 是 tabBar.list 的下标。
    func tabBarView(_ tabBarView: DMPTabBarView, didSelectIndex index: Int, item: DMPTabBarItem)
}

/// 高度约定：内容 49pt + 安全区底部。
public class DMPTabBarView: UIView {

    public weak var delegate: DMPTabBarViewDelegate?

    private let config: DMPTabBarConfig
    private let appId: String
    private let versionCode: Int?
    private let stack = UIStackView()
    private let topBorder = UIView()
    private var buttons: [DMPTabBarItemButton] = []
    private(set) var selectedIndex: Int = 0

    public static let contentHeight: CGFloat = 49

    public init(config: DMPTabBarConfig, appId: String, versionCode: Int?) {
        self.config = config
        self.appId = appId
        self.versionCode = versionCode
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    private func setup() {
        backgroundColor = DMPUtil.colorFromHexString(config.backgroundColor) ?? .systemBackground

        topBorder.backgroundColor = config.borderStyle == "white" ? .white.withAlphaComponent(0.2) : .black.withAlphaComponent(0.2)
        topBorder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topBorder)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        for (index, item) in config.list.enumerated() {
            let button = DMPTabBarItemButton(
                item: item,
                normalColor: DMPUtil.colorFromHexString(config.color) ?? .gray,
                selectedColor: DMPUtil.colorFromHexString(config.selectedColor) ?? .systemBlue
            )
            button.tag = index
            button.addTarget(self, action: #selector(onTap(_:)), for: .touchUpInside)
            loadIcons(into: button, item: item)
            stack.addArrangedSubview(button)
            buttons.append(button)
        }

        NSLayoutConstraint.activate([
            topBorder.topAnchor.constraint(equalTo: topAnchor),
            topBorder.leadingAnchor.constraint(equalTo: leadingAnchor),
            topBorder.trailingAnchor.constraint(equalTo: trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 0.5),

            stack.topAnchor.constraint(equalTo: topBorder.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: DMPTabBarView.contentHeight),
        ])
    }

    /// 由 `pagePath` 切换选中态。pagePath 不在 list 里时不变。
    public func setSelected(pagePath: String) {
        guard let index = config.index(of: pagePath) else { return }
        select(index: index, notify: false)
    }

    /// 由 setTabBarItem 等 API 调用，更新某个 tab 的文字/icon。
    public func updateItem(index: Int, text: String?, iconPath: String?, selectedIconPath: String?) {
        guard index >= 0, index < buttons.count else { return }
        let button = buttons[index]
        if let text = text { button.setLabelText(text) }
        if let iconPath = iconPath {
            loadIcon(path: iconPath) { img in button.setNormalIcon(img) }
        }
        if let selectedIconPath = selectedIconPath {
            loadIcon(path: selectedIconPath) { img in button.setSelectedIcon(img) }
        }
    }

    /// setTabBarStyle 应用：colors 更新。
    public func applyStyle(color: String?, selectedColor: String?, backgroundColor: String?, borderStyle: String?) {
        if let backgroundColor = backgroundColor, let c = DMPUtil.colorFromHexString(backgroundColor) {
            self.backgroundColor = c
        }
        if let borderStyle = borderStyle {
            topBorder.backgroundColor = borderStyle == "white" ? .white.withAlphaComponent(0.2) : .black.withAlphaComponent(0.2)
        }
        let normal = color.flatMap(DMPUtil.colorFromHexString) ?? DMPUtil.colorFromHexString(config.color) ?? .gray
        let selected = selectedColor.flatMap(DMPUtil.colorFromHexString) ?? DMPUtil.colorFromHexString(config.selectedColor) ?? .systemBlue
        for button in buttons {
            button.updateColors(normal: normal, selected: selected)
        }
    }

    public func setBadge(index: Int, text: String) {
        guard index >= 0, index < buttons.count else { return }
        buttons[index].setBadge(text)
    }

    public func removeBadge(index: Int) {
        guard index >= 0, index < buttons.count else { return }
        buttons[index].removeBadge()
    }

    public func showRedDot(index: Int) {
        guard index >= 0, index < buttons.count else { return }
        buttons[index].showRedDot()
    }

    public func hideRedDot(index: Int) {
        guard index >= 0, index < buttons.count else { return }
        buttons[index].hideRedDot()
    }

    @objc private func onTap(_ sender: UIControl) {
        let index = sender.tag
        guard index >= 0, index < config.list.count else { return }
        if index == selectedIndex { return }
        select(index: index, notify: true)
    }

    private func select(index: Int, notify: Bool) {
        for (i, button) in buttons.enumerated() {
            button.setSelected(i == index)
        }
        selectedIndex = index
        if notify {
            delegate?.tabBarView(self, didSelectIndex: index, item: config.list[index])
        }
    }

    // MARK: - Icon loading

    private func loadIcons(into button: DMPTabBarItemButton, item: DMPTabBarItem) {
        if let p = item.iconPath {
            loadIcon(path: p) { img in button.setNormalIcon(img) }
        }
        if let p = item.selectedIconPath {
            loadIcon(path: p) { img in button.setSelectedIcon(img) }
        }
    }

    /// icon path 形如 "/wxfca8a42caa0f8c5a/main/static/explore.png"，第一段是 Taro 打包出来的
    /// pkgId，不是真实 appId。实际文件在 appBundlePath/<path-without-first-segment>。
    private func loadIcon(path: String, completion: @escaping (UIImage?) -> Void) {
        let resolved = resolveIconPath(path)
        if FileManager.default.fileExists(atPath: resolved) {
            completion(UIImage(contentsOfFile: resolved))
            return
        }
        // Fallback: path 不带 pkgId 前缀，直接拼。
        let fallback = DMPSandboxManager.appBundlePath(appId, versionCode: versionCode) + path
        if FileManager.default.fileExists(atPath: fallback) {
            completion(UIImage(contentsOfFile: fallback))
            return
        }
        DMPLog.bundle.warn("tabBar icon not found: tried \(resolved) and \(fallback)")
        completion(nil)
    }

    private func resolveIconPath(_ path: String) -> String {
        // path 形如 "/<pkgId>/main/static/foo.png"，剥离首段（pkgId）
        var components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if components.count > 1 {
            components.removeFirst()
        }
        let suffix = "/" + components.joined(separator: "/")
        return DMPSandboxManager.appBundlePath(appId, versionCode: versionCode) + suffix
    }
}

// MARK: - Item Button

private final class DMPTabBarItemButton: UIControl {
    private let iconView = UIImageView()
    private let label = UILabel()
    private var normalIcon: UIImage?
    private var selectedIcon: UIImage?
    private var normalColor: UIColor
    private var selectedColor: UIColor

    init(item: DMPTabBarItem, normalColor: UIColor, selectedColor: UIColor) {
        self.normalColor = normalColor
        self.selectedColor = selectedColor
        super.init(frame: .zero)
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        label.text = item.text
        label.font = .systemFont(ofSize: 10)
        label.textColor = normalColor
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(label)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 2),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not implemented") }

    func setNormalIcon(_ image: UIImage?) {
        normalIcon = image
        if !isSelected { iconView.image = image }
    }

    func setSelectedIcon(_ image: UIImage?) {
        selectedIcon = image
        if isSelected { iconView.image = image }
    }

    func setLabelText(_ text: String) {
        label.text = text
    }

    func setSelected(_ selected: Bool) {
        isSelected = selected
        iconView.image = selected ? (selectedIcon ?? normalIcon) : (normalIcon ?? selectedIcon)
        label.textColor = selected ? selectedColor : normalColor
    }

    func updateColors(normal: UIColor, selected: UIColor) {
        normalColor = normal
        selectedColor = selected
        label.textColor = isSelected ? selected : normal
    }

    // MARK: - Badge / Red Dot

    private lazy var badgeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 9, weight: .medium)
        l.textColor = .white
        l.backgroundColor = .systemRed
        l.textAlignment = .center
        l.layer.cornerRadius = 8
        l.layer.masksToBounds = true
        l.translatesAutoresizingMaskIntoConstraints = false
        l.isHidden = true
        addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: iconView.trailingAnchor),
            l.centerYAnchor.constraint(equalTo: iconView.topAnchor, constant: 2),
            l.heightAnchor.constraint(equalToConstant: 16),
            l.widthAnchor.constraint(greaterThanOrEqualToConstant: 16),
        ])
        return l
    }()

    private lazy var redDotView: UIView = {
        let v = UIView()
        v.backgroundColor = .systemRed
        v.layer.cornerRadius = 4
        v.translatesAutoresizingMaskIntoConstraints = false
        v.isHidden = true
        addSubview(v)
        NSLayoutConstraint.activate([
            v.centerXAnchor.constraint(equalTo: iconView.trailingAnchor),
            v.centerYAnchor.constraint(equalTo: iconView.topAnchor, constant: 2),
            v.widthAnchor.constraint(equalToConstant: 8),
            v.heightAnchor.constraint(equalToConstant: 8),
        ])
        return v
    }()

    func setBadge(_ text: String) {
        badgeLabel.text = " \(text) "
        badgeLabel.isHidden = false
        redDotView.isHidden = true
    }

    func removeBadge() {
        badgeLabel.isHidden = true
    }

    func showRedDot() {
        redDotView.isHidden = false
        badgeLabel.isHidden = true
    }

    func hideRedDot() {
        redDotView.isHidden = true
    }
}
