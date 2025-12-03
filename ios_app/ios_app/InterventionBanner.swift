//
//  InterventionBanner.swift
//  ios_app
//
//  Created by SHIFT on 12/02/25.
//

import SwiftUI

struct InterventionBanner: View {
    let intervention: Intervention
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    @State private var dragOffset: CGFloat = 0
    
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
                
                Button(action: onDismiss) {
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
                            // Dismiss if dragged up enough
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
            
            // Auto-dismiss after 8 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                withAnimation(.spring()) {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
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

