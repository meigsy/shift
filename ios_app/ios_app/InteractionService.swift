//
//  InteractionService.swift
//  ios_app
//
//  Created by SHIFT on 12/02/25.
//

import Foundation

struct InteractionEventType {
    static let shown = "shown"
    static let tapPrimary = "tap_primary"
    static let dismissManual = "dismiss_manual"
    static let dismissTimeout = "dismiss_timeout"
}

@MainActor
class InteractionService {
    private let apiClient: ApiClient
    
    init(apiClient: ApiClient) {
        self.apiClient = apiClient
    }
    
    func recordInteraction(
        intervention: Intervention,
        eventType: String,
        userId: String
    ) async throws {
        guard let traceId = intervention.traceId else {
            print("⚠️ Cannot record interaction - intervention missing trace_id")
            return
        }
        
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("📊 [\(timestamp)] Recording interaction: \(eventType) for intervention \(intervention.interventionInstanceId)")
        
        let interactionRequest = AppInteractionRequest(
            traceId: traceId,
            userId: userId,
            interventionInstanceId: intervention.interventionInstanceId,
            eventType: eventType,
            timestamp: Date()
        )
        
        do {
            let _ = try await apiClient.post(path: "/app_interactions", body: interactionRequest)
            print("✅ [\(timestamp)] Interaction recorded successfully")
        } catch {
            print("❌ [\(timestamp)] Failed to record interaction: \(error.localizedDescription)")
            // Don't throw - interaction tracking is non-blocking
        }
    }
}

struct AppInteractionRequest: Codable {
    let traceId: String
    let userId: String
    let interventionInstanceId: String?
    let eventType: String
    let timestamp: Date
    
    enum CodingKeys: String, CodingKey {
        case traceId = "trace_id"
        case userId = "user_id"
        case interventionInstanceId = "intervention_instance_id"
        case eventType = "event_type"
        case timestamp
    }
}

