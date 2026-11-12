//
//  DCReaderOrientationLock.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import UIKit

/// Rotation lock for the reader, like Books' setting.
///
/// iOS asks the app delegate which orientations are allowed, so the host app forwards that:
///
/// ```swift
/// func application(_ application: UIApplication,
///                  supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
///     DCReaderOrientationLock.supportedOrientations
/// }
/// ```
///
/// While a reader with the lock on is open, this is the orientation it was locked in; otherwise
/// every orientation.
@MainActor
public enum DCReaderOrientationLock {

    public private(set) static var supportedOrientations: UIInterfaceOrientationMask = .all

    /// Locks to the orientation the screen is in now, or unlocks.
    static func setLocked(_ locked: Bool) {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ??
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        supportedOrientations = locked ? mask(for: scene?.interfaceOrientation ?? .portrait) : .all
        for window in scene?.windows ?? [] {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    static func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
        switch orientation {
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        case .portraitUpsideDown: .portraitUpsideDown
        default: .portrait
        }
    }
}
