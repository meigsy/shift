//
//  AppDelegate.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    
    var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        print("🚀 AppDelegate: App finished launching")
        return true
    }
    
    /// Called when app is woken in background for HealthKit background delivery
    func applicationDidBecomeActive(_ application: UIApplication) {
        print("📱 AppDelegate: App became active")
    }
    
    /// Called when app is about to enter foreground
    func applicationWillEnterForeground(_ application: UIApplication) {
        print("📱 AppDelegate: App entering foreground")
    }
    
    /// Called when app enters background
    func applicationDidEnterBackground(_ application: UIApplication) {
        print("📱 AppDelegate: App entered background")
    }
}

// MARK: - Background Task Helper

extension AppDelegate {
    
    /// Request background execution time and perform sync work
    func performBackgroundSync(application: UIApplication, syncWork: @escaping () async throws -> Void) {
        // End any existing background task
        if backgroundTaskIdentifier != .invalid {
            application.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
        
        // Request new background task
        backgroundTaskIdentifier = application.beginBackgroundTask(withName: "HealthKitSync") { [weak self] in
            // Task expired - clean up
            print("⏱️ Background task expired")
            if let self = self, self.backgroundTaskIdentifier != .invalid {
                application.endBackgroundTask(self.backgroundTaskIdentifier)
                self.backgroundTaskIdentifier = .invalid
            }
        }
        
        guard backgroundTaskIdentifier != .invalid else {
            print("⚠️ Could not start background task")
            return
        }
        
        print("🔄 Starting background sync task (ID: \(backgroundTaskIdentifier.rawValue))")
        
        // Perform sync work
        Task {
            do {
                try await syncWork()
                print("✅ Background sync completed")
            } catch {
                print("❌ Background sync failed: \(error.localizedDescription)")
            }
            
            // End background task when done
            if self.backgroundTaskIdentifier != .invalid {
                application.endBackgroundTask(self.backgroundTaskIdentifier)
                self.backgroundTaskIdentifier = .invalid
            }
        }
    }
}

