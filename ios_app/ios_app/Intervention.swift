//
//  Intervention.swift
//  ios_app
//
//  Created by SHIFT on 12/02/25.
//

import Foundation

struct Intervention: Decodable, Identifiable, Equatable {
    let interventionInstanceId: String
    let userId: String
    let metric: String
    let level: String
    let surface: String
    let interventionKey: String
    let title: String
    let body: String
    let createdAt: Date?
    let scheduledAt: Date?
    let sentAt: Date?
    let status: String
    
    var id: String { interventionInstanceId }
    
    enum CodingKeys: String, CodingKey {
        case interventionInstanceId = "intervention_instance_id"
        case userId = "user_id"
        case metric
        case level
        case surface
        case interventionKey = "intervention_key"
        case title
        case body
        case createdAt = "created_at"
        case scheduledAt = "scheduled_at"
        case sentAt = "sent_at"
        case status
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interventionInstanceId = try container.decode(String.self, forKey: .interventionInstanceId)
        userId = try container.decode(String.self, forKey: .userId)
        metric = try container.decode(String.self, forKey: .metric)
        level = try container.decode(String.self, forKey: .level)
        surface = try container.decode(String.self, forKey: .surface)
        interventionKey = try container.decode(String.self, forKey: .interventionKey)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        status = try container.decode(String.self, forKey: .status)
        
        // Decode optional ISO8601 dates - try multiple formats
        func parseDate(from string: String?) -> Date? {
            guard let string = string, !string.isEmpty else { return nil }
            
            // Try with fractional seconds first
            let formatterWithFractional = ISO8601DateFormatter()
            formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatterWithFractional.date(from: string) {
                return date
            }
            
            // Try without fractional seconds
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.date(from: string)
        }
        
        let createdAtString = try? container.decodeIfPresent(String.self, forKey: .createdAt)
        createdAt = parseDate(from: createdAtString)
        
        let scheduledAtString = try? container.decodeIfPresent(String.self, forKey: .scheduledAt)
        scheduledAt = parseDate(from: scheduledAtString)
        
        let sentAtString = try? container.decodeIfPresent(String.self, forKey: .sentAt)
        sentAt = parseDate(from: sentAtString)
    }
}

struct InterventionsResponse: Decodable {
    let interventions: [Intervention]
}

