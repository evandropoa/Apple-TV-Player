//
//  AppDelegate.swift
//  Apple-TV-Player
//
//  Created by Mikhail Demidov on 16.10.2020.
//

import UIKit
import os

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        #if targetEnvironment(simulator)
        print("App sandbox path \(FileManager.default.temporaryDirectory.deletingLastPathComponent())")
        #endif
        return true
    }
}

