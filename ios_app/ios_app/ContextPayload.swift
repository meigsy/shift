//
//  ContextPayload.swift
//  ios_app
//
//  Created for SHIFT MVP UX context endpoint.
//

import Foundation

struct StateEstimate: Decodable {
    let userId: String
    let timestamp: Date
    let traceId: String?
    let recovery: Double?
    let readiness: Double?
    let stress: Double?
    let fatigue: Double?
    
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case timestamp
        case traceId = "trace_id"
        case recovery
        case readiness
        case stress
        case fatigue
    }
}

struct ContextPayload: Decodable {
    let stateEstimate: StateEstimate?
    let interventions: [Intervention]
    
    enum CodingKeys: String, CodingKey {
        case stateEstimate = "state_estimate"
        case interventions
    }
}




