//
//  InteractionService.swift
//  ios_app
//
//  Created by SHIFT on 12/02/25.
//

import Foundation

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
        
        let interactionRequestDict: [String: Any] = [
            "trace_id": traceId,
            "user_id": userId,
            "intervention_instance_id": intervention.interventionInstanceId as Any,
            "event_type": eventType,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: interactionRequestDict, options: [])
            let _ = try await apiClient.post(path: "/app_interactions", bodyData: jsonData)
            print("✅ [\(timestamp)] Interaction recorded successfully")
        } catch {
            print("❌ [\(timestamp)] Failed to record interaction: \(error.localizedDescription)")
            // Don't throw - interaction tracking is non-blocking
        }
    }
    
    func recordFlowEvent(
        eventType: String,
        userId: String,
        payload: [String: Any]? = nil
    ) async throws {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("📊 [\(timestamp)] Recording flow event: \(eventType)")
        
        // Generate a trace_id for flow events (not tied to an intervention)
        let traceId = UUID().uuidString
        
        var interactionRequestDict: [String: Any] = [
            "trace_id": traceId,
            "user_id": userId,
            "intervention_instance_id": nil as String? as Any,
            "event_type": eventType,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        if let payload = payload {
            interactionRequestDict["payload"] = payload
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: interactionRequestDict, options: [])
            let _ = try await apiClient.post(path: "/app_interactions", bodyData: jsonData)
            print("✅ [\(timestamp)] Flow event recorded successfully")
        } catch {
            print("❌ [\(timestamp)] Failed to record flow event: \(error.localizedDescription)")
            // Don't throw - flow event tracking is non-blocking
        }
    }
    
    func resetUserData(scope: String = "all") async throws {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        print("🔄 [\(timestamp)] Resetting user data with scope: \(scope)")
        
        // #region agent log
        let logData1: [String: Any] = [
            "location": "InteractionService.swift:83",
            "message": "resetUserData entry",
            "data": ["scope": scope, "timestamp": timestamp],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "ALL"
        ]
        if let logJson = try? JSONSerialization.data(withJSONObject: logData1),
           let logStr = String(data: logJson, encoding: .utf8) {
            try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
        }
        // #endregion
        
        let resetRequest: [String: Any] = ["scope": scope]
        let jsonData = try JSONSerialization.data(withJSONObject: resetRequest, options: [])
        
        // #region agent log
        let logData2: [String: Any] = [
            "location": "InteractionService.swift:95",
            "message": "Before API call",
            "data": [
                "requestBody": String(data: jsonData, encoding: .utf8) ?? "nil",
                "path": "/user/reset"
            ],
            "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
            "sessionId": "debug-session",
            "runId": "run1",
            "hypothesisId": "B"
        ]
        if let logJson = try? JSONSerialization.data(withJSONObject: logData2),
           let logStr = String(data: logJson, encoding: .utf8) {
            try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
        }
        // #endregion
        
        do {
            let _ = try await apiClient.post(path: "/user/reset", bodyData: jsonData)
            print("✅ [\(timestamp)] Reset request sent successfully")
            
            // #region agent log
            let logData3: [String: Any] = [
                "location": "InteractionService.swift:109",
                "message": "API call succeeded",
                "data": ["success": true],
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "ALL"
            ]
            if let logJson = try? JSONSerialization.data(withJSONObject: logData3),
               let logStr = String(data: logJson, encoding: .utf8) {
                try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
            }
            // #endregion
        } catch {
            print("❌ [\(timestamp)] Failed to reset user data: \(error.localizedDescription)")
            
            // #region agent log
            let errorType = String(describing: type(of: error))
            var errorDetails: [String: Any] = [
                "error": error.localizedDescription,
                "errorType": errorType,
                "errorDescription": String(describing: error)
            ]
            if let apiError = error as? ApiError {
                if case .httpError(let status, let msg) = apiError {
                    errorDetails["statusCode"] = status
                    errorDetails["message"] = msg
                }
            }
            let logData4: [String: Any] = [
                "location": "InteractionService.swift:129",
                "message": "API call failed",
                "data": errorDetails,
                "timestamp": Int64(Date().timeIntervalSince1970 * 1000),
                "sessionId": "debug-session",
                "runId": "run1",
                "hypothesisId": "ALL"
            ]
            if let logJson = try? JSONSerialization.data(withJSONObject: logData4),
               let logStr = String(data: logJson, encoding: .utf8) {
                try? logStr.appendLineToFile(filePath: "/Users/sly/dev/shift/.cursor/debug.log")
            }
            // #endregion
            
            throw error
        }
    }
}

