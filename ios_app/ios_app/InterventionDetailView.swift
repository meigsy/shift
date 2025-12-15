//
//  InterventionDetailView.swift
//  ios_app
//
//  Detail surface for a single intervention.
//

import SwiftUI

struct InterventionDetailView: View {
    let intervention: Intervention
    let stateEstimate: StateEstimate?
    let interactionService: InteractionService?
    let userId: String
    
    @Environment(\.dismiss) private var dismiss
    @State private var isWhyExpanded = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(intervention.title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(intervention.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if let whyCopy = whyThisCopy(from: stateEstimate) {
                    DisclosureGroup(isExpanded: $isWhyExpanded) {
                        Text(whyCopy)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    } label: {
                        Text("Why this?")
                            .font(.subheadline.weight(.medium))
                    }
                }
                
                Spacer(minLength: 24)
                
                actionButtons
            }
            .padding(20)
        }
        .navigationTitle("Intervention")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                recordInteraction(eventType: "tapped")
                dismiss()
            } label: {
                Text("Try it")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            
            Button {
                recordInteraction(eventType: "dismissed")
                dismiss()
            } label: {
                Text("Not now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            
            Button(role: .cancel) {
                recordInteraction(eventType: "dismissed")
                dismiss()
            } label: {
                Text("Skip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
        }
    }
    
    // MARK: - Helpers
    
    private func recordInteraction(eventType: String) {
        guard let interactionService = interactionService else { return }
        
        Task {
            try? await interactionService.recordInteraction(
                intervention: intervention,
                eventType: eventType,
                userId: userId
            )
        }
    }
    
    private func whyThisCopy(from estimate: StateEstimate?) -> String? {
        guard let estimate,
              let stress = estimate.stress else { return nil }
        
        if stress >= 0.7 {
            return "Based on signals such as your heart rate variability and activity patterns, your body may be responding to elevated stress. This nudge is designed to help you downshift and create a small pocket of recovery."
        } else if stress >= 0.4 {
            return "Your body may be showing signs of moderate stress. A short reset now can help prevent it from climbing and keep your system steadier."
        } else {
            return "Your system appears relatively steady. This is about reinforcing what's already working for you."
        }
    }
}


