//
//  DMPScreenShotProtectionController.swift
//  Dimina
//

import UIKit

/// Applies capture protection to the mini-program navigation container.
///
/// iOS has no public window-level screenshot-disable API. Secure text fields,
/// however, are omitted from system captures. This controller hosts the target
/// layer inside that secure rendering subtree while protection is enabled and
/// restores the original layer hierarchy when the page changes or exits.
final class DMPScreenShotProtectionController {
    private weak var protectedView: UIView?
    private weak var originalSuperlayer: CALayer?
    private var originalLayerIndex: UInt32 = 0
    private var secureTextField: UITextField?

    @discardableResult
    @MainActor
    func setProtected(_ protected: Bool, view: UIView) -> Bool {
        if protected {
            return enable(on: view)
        }
        reset()
        return true
    }

    @MainActor
    func reset() {
        guard let secureTextField else { return }

        if let protectedView,
           let destinationLayer = originalSuperlayer ?? protectedView.superview?.layer {
            protectedView.layer.removeFromSuperlayer()
            let insertionIndex = min(
                originalLayerIndex,
                UInt32(destinationLayer.sublayers?.count ?? 0)
            )
            destinationLayer.insertSublayer(protectedView.layer, at: insertionIndex)
            protectedView.superview?.setNeedsLayout()
            protectedView.setNeedsLayout()
        }

        secureTextField.removeFromSuperview()
        self.secureTextField = nil
        protectedView = nil
        originalSuperlayer = nil
        originalLayerIndex = 0
    }

    @MainActor
    private func enable(on view: UIView) -> Bool {
        if protectedView === view, secureTextField != nil {
            return true
        }
        reset()

        guard let superview = view.superview,
              let superlayer = view.layer.superlayer else {
            return false
        }

        let textField = UITextField(frame: view.frame)
        textField.isUserInteractionEnabled = false
        textField.backgroundColor = .black
        textField.autoresizingMask = view.autoresizingMask
        superview.insertSubview(textField, belowSubview: view)
        textField.isSecureTextEntry = true
        textField.layoutIfNeeded()

        guard let secureContainerLayer = textField.subviews.first?.layer else {
            textField.removeFromSuperview()
            return false
        }

        let layerIndex = superlayer.sublayers?.firstIndex(where: { $0 === view.layer }) ?? 0
        originalLayerIndex = UInt32(layerIndex)
        originalSuperlayer = superlayer
        protectedView = view
        secureTextField = textField

        view.layer.removeFromSuperlayer()
        secureContainerLayer.addSublayer(view.layer)
        return true
    }
}
