//
//  InterventionPoller.swift
//  ios_app
//
//  Created by SHIFT on 12/02/25.
//

import Foundation
import Combine

@MainActor
class InterventionPoller: ObservableObject {
    private let interventionService: InterventionService
    private let router: InterventionRouter
    private let userId: String
    
    private var timer: Timer?
    private var seenInterventionIds: Set<String> = []
    private var isPolling = false
    
    @Published var activeInterventions: [Intervention] = []
    
    init(interventionService: InterventionService, router: InterventionRouter, userId: String) {
        self.interventionService = interventionService
        self.router = router
        self.userId = userId
    }
    
    func startPolling() {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        
        guard !isPolling else {
            print("⏸️ [\(timestamp)] Polling already started")
            return
        }
        
        isPolling = true
        print("🔄 [\(timestamp)] Starting intervention polling for user: \(userId)")
        
        // Poll immediately
        Task {
            await poll()
        }
        
        // Then poll every 60 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.poll()
            }
        }
    }
    
    func stopPolling() {
        guard isPolling else {
            return
        }
        
        isPolling = false
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("⏸️ [\(timestamp)] Stopping intervention polling")
        
        timer?.invalidate()
        timer = nil
    }
    
    private func poll() async {
        guard isPolling else {
            return
        }
        
        do {
            let interventions = try await interventionService.fetchPendingInterventions(userId: userId)
            
            // Filter out already-seen interventions
            let newInterventions = interventions.filter { intervention in
                !seenInterventionIds.contains(intervention.interventionInstanceId)
            }
            
            // Display new interventions
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            for intervention in newInterventions {
                print("📬 [\(timestamp)] New intervention: \(intervention.title) (ID: \(intervention.interventionInstanceId))")
                seenInterventionIds.insert(intervention.interventionInstanceId)
                
                // Route to appropriate surface
                router.displayIntervention(intervention)
            }
            
            if newInterventions.isEmpty {
                print("ℹ️ [\(timestamp)] No new interventions (checked \(interventions.count) total)")
            }
            
            // Update active interventions list
            activeInterventions = interventions
            
        } catch {
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            print("❌ [\(timestamp)] Error polling interventions: \(error.localizedDescription)")
            // Don't stop polling on error - continue trying
        }
    }
    
    func markInterventionAsSeen(_ interventionId: String) {
        seenInterventionIds.insert(interventionId)
    }
    
    deinit {
        // Invalidate timer directly - deinit is nonisolated, so we can't call main actor methods
        timer?.invalidate()
    }
}

