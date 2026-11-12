//
//  DCReaderOrientationLock.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import UIKit

/// Rotation lock for the reader, like Books' setting.
///
/// iOS asks the app delegate which orientations each window allows, so the host app forwards that:
///
/// ```swift
/// func application(_ application: UIApplication,
///                  supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
///     DCReaderOrientationLock.supportedOrientations(for: window)
/// }
/// ```
///
/// A window showing a reader with the lock on keeps the orientation it was locked in; every other
/// window turns freely.
@MainActor
public enum DCReaderOrientationLock {

    private static var locked: [ObjectIdentifier: UIInterfaceOrientationMask] = [:]

    public static func supportedOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
        window?.windowScene.flatMap { locked[ObjectIdentifier($0)] } ?? .all
    }

    /// Locks `scene` to the orientation it's in now, or unlocks it.
    static func setLocked(_ isLocked: Bool, scene: UIWindowScene?) {
        guard let scene else { return }
        locked[ObjectIdentifier(scene)] = isLocked ? mask(for: scene.interfaceOrientation) : nil
        for window in scene.windows {
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

    /// Whether the lock can do anything in `scene`: iPad ignores it in Split View and Stage Manager
    /// (the window isn't the whole screen), and Mac windows don't rotate.
    static func isAvailable(in scene: UIWindowScene?) -> Bool {
        guard !ProcessInfo.processInfo.isMacCatalystApp else { return false }
        guard let scene, let window = scene.windows.first else { return true }
        return window.bounds.size == scene.screen.bounds.size
            || window.bounds.size == CGSize(width: scene.screen.bounds.height, height: scene.screen.bounds.width)
    }
}
