//
//  InterventionRouter.swift
//  ios_app
//
//  Created by SHIFT on 12/02/25.
//

import SwiftUI
import Combine

enum InterventionSurface {
    case notification
    case inApp  // Future
    case unknown(String)
    
    init(_ surfaceString: String) {
        switch surfaceString {
        case "notification":
            self = .notification
        case "in_app":
            self = .inApp
        default:
            self = .unknown(surfaceString)
        }
    }
}

@MainActor
class InterventionRouter: ObservableObject {
    @Published var newIntervention: Intervention?
    var onShowInAppCard: ((Intervention) -> Void)?  // Future
    
    func displayIntervention(_ intervention: Intervention) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let surface = InterventionSurface(intervention.surface)
        
        switch surface {
        case .notification:
            print("➡️ [\(timestamp)] Routing intervention '\(intervention.title)' to notification banner (ID: \(intervention.interventionInstanceId))")
            newIntervention = intervention
            
        case .inApp:
            // Future: Show in-app card
            print("➡️ [\(timestamp)] Routing intervention '\(intervention.title)' to in-app card (not yet implemented)")
            onShowInAppCard?(intervention)
            
        case .unknown(let surfaceString):
            // Fallback to notification for unknown surfaces
            print("⚠️ [\(timestamp)] Unknown intervention surface: \(surfaceString), defaulting to notification")
            newIntervention = intervention
        }
    }
}

