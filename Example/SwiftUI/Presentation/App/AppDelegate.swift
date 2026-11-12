//
//  AppDelegate.swift
//  DCEpubReaderKit
//
//  Created by Liam Smith-Gales on 11/11/26.
//

import UIKit
import DCEpubReaderKit

/// Lets the reader's rotation lock decide which orientations are allowed.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        DCReaderOrientationLock.supportedOrientations
    }
}
