//
//  InterventionBanner.swift
//  ios_app
//
//  Created by SHIFT on 12/02/25.
//

import SwiftUI

struct InterventionBanner: View {
    let intervention: Intervention
    let interactionService: InteractionService?
    let userId: String
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var dragOffset: CGFloat = 0
    @State private var autoDismissTask: Task<Void, Never>?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Icon based on level
                Image(systemName: iconForLevel(intervention.level))
                    .font(.title2)
                    .foregroundStyle(colorForLevel(intervention.level))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(intervention.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(intervention.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button(action: {
                    // Cancel auto-dismiss timer
                    autoDismissTask?.cancel()
                    autoDismissTask = nil
                    
                    // Record manual dismiss interaction
                    if let interactionService = interactionService {
                        Task {
                            try? await interactionService.recordInteraction(
                                intervention: intervention,
                                eventType: InteractionEventType.dismissManual,
                                userId: userId
                            )
                        }
                    }
                    onDismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
            .padding(.horizontal, 16)
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height < 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height < -50 {
                            // Cancel auto-dismiss timer
                            autoDismissTask?.cancel()
                            autoDismissTask = nil
                            
                            // Dismiss if dragged up enough
                            // Record manual dismiss interaction
                            if let interactionService = interactionService {
                                Task {
                                    try? await interactionService.recordInteraction(
                                        intervention: intervention,
                                        eventType: InteractionEventType.dismissManual,
                                        userId: userId
                                    )
                                }
                            }
                            withAnimation(.spring()) {
                                isVisible = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onDismiss()
                            }
                        } else {
                            // Snap back
                            withAnimation(.spring()) {
                                dragOffset = 0
                            }
                        }
                    }
            )
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isVisible = true
            }
            
            // Record "shown" interaction
            if let interactionService = interactionService {
                Task {
                    try? await interactionService.recordInteraction(
                        intervention: intervention,
                        eventType: InteractionEventType.shown,
                        userId: userId
                    )
                }
            }
            
            // Auto-dismiss after 30 seconds (increased for easier testing)
            autoDismissTask = Task {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                
                // Check if task was cancelled (manual dismiss happened)
                guard !Task.isCancelled else { return }
                
                // Record timeout dismiss interaction
                if let interactionService = interactionService {
                    try? await interactionService.recordInteraction(
                        intervention: intervention,
                        eventType: InteractionEventType.dismissTimeout,
                        userId: userId
                    )
                }
                
                // Check again after async call
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    withAnimation(.spring()) {
                        isVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onDismiss()
                    }
                }
            }
        }
    }
    
    private func iconForLevel(_ level: String) -> String {
        switch level {
        case "high":
            return "exclamationmark.triangle.fill"
        case "medium":
            return "info.circle.fill"
        case "low":
            return "checkmark.circle.fill"
        default:
            return "bell.fill"
        }
    }
    
    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "high":
            return .orange
        case "medium":
            return .blue
        case "low":
            return .green
        default:
            return .gray
        }
    }
}

#Preview {
    ZStack {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()
        
        VStack {
            // Preview with JSON-like data (would need to decode from JSON in real preview)
            Text("Intervention Banner Preview")
                .font(.headline)
            Text("Preview requires JSON decoding - see implementation")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

