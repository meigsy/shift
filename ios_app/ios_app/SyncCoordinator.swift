//
//  SyncCoordinator.swift
//  ios_app
//
//  Created by SHIFT on 11/30/25.
//

import Foundation

/// Thread-safe actor that coalesces multiple sync requests into sequential execution.
/// Prevents redundant syncs when multiple HealthKit observers fire in quick succession.
actor SyncCoordinator {
    
    // MARK: - State
    
    /// Whether a sync is currently in progress
    private var isSyncInProgress = false
    
    /// Whether a sync was requested while another sync was in progress
    private var pendingSync = false
    
    // MARK: - Public Interface
    
    /// Request a sync, coalescing multiple rapid requests.
    /// - Parameter startSync: Async closure that performs the actual sync work
    /// 
    /// Behavior:
    /// - If no sync is in progress, starts a sync immediately
    /// - If a sync is in progress, marks that a sync is pending and returns
    /// - When the current sync finishes, if a sync is pending, runs one more sync
    func requestSync(startSync: @escaping () async -> Void) async {
        if isSyncInProgress {
            // A sync is already running, mark that we need another one
            pendingSync = true
            print("⏸️ Sync already in progress, marking pending")
            return
        }
        
        // No sync in progress, start one
        isSyncInProgress = true
        print("🔄 Starting sync (coordinated)")
        
        // Run the sync in a Task so we can continue monitoring
        Task {
            await startSync()
            // When sync finishes, check if we need to run another one
            await syncFinished(startSync: startSync)
        }
    }
    
    // MARK: - Private Helpers
    
    /// Called when a sync finishes to handle pending syncs
    private func syncFinished(startSync: @escaping () async -> Void) async {
        if pendingSync {
            // Another sync was requested while we were running
            pendingSync = false
            print("🔄 Running pending sync")
            // Recursively call requestSync, which will start the next sync
            // (isSyncInProgress is still true, and we keep it that way)
            Task {
                await startSync()
                await syncFinished(startSync: startSync)
            }
        } else {
            // No pending syncs, we're done
            isSyncInProgress = false
            print("✅ All syncs complete")
        }
    }
}

