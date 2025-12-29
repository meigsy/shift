//
//  HomeView.swift
//  ios_app
//
//  SHIFT Today screen: optional state summary + 0–3 intervention tiles.
//

import SwiftUI

struct HomeView: View {
    let authViewModel: AuthViewModel
    let contextService: ContextService
    let interactionService: InteractionService?
    
    @State private var stateEstimate: StateEstimate?
    @State private var interventions: [Intervention] = []
    @State private var savedInterventions: [String] = []
    @State private var isLoading = false
    @State private var loadError: String?
    // Track which (intervention_instance_id, surface) combinations have logged "shown" events
    @State private var shownInterventions: Set<String> = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let estimate = stateEstimate {
                    todayStateView(estimate)
                }
                
                actionTilesSection
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .navigationTitle("Today")
            .task {
                await loadContext()
            }
            .refreshable {
                await loadContext()
            }
            .onReceive(NotificationCenter.default.publisher(for: .contextRefreshNeeded)) { _ in
                Task {
                    await loadContext()
                }
            }
        }
    }
    
    // MARK: - Views
    
    private func todayStateView(_ estimate: StateEstimate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(todayHeadline(from: estimate))
                .font(.title2.weight(.semibold))
            
            if let subtitle = todaySubtitle(from: estimate) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var actionTilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Order by created_at DESC (already sorted by backend) before taking first 3
            let tiles = Array(interventions.prefix(3))
            
            if tiles.isEmpty {
                // No tiles; keep Home calm and uncluttered
                EmptyView()
            } else {
                ForEach(tiles) { intervention in
                    NavigationLink {
                        InterventionDetailView(
                            intervention: intervention,
                            stateEstimate: stateEstimate,
                            interactionService: interactionService,
                            userId: authViewModel.user?.userId ?? "",
                            savedInterventions: savedInterventions
                        )
                    } label: {
                        actionTile(for: intervention)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        recordShownIfNeeded(intervention, surface: "home_tile")
                    }
                }
            }
        }
    }
    
    private func actionTile(for intervention: Intervention) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(intervention.title)
                .font(.headline)
                .foregroundStyle(.primary)
            
            Text(intervention.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    // MARK: - Helpers
    
    private func loadContext() async {
        isLoading = true
        loadError = nil
        do {
            // Backend derives user from auth token; no user_id param needed
            let payload = try await contextService.fetchContext()
            
            await MainActor.run {
                self.stateEstimate = payload.stateEstimate
                // Interventions are already ordered by created_at DESC from backend
                self.interventions = payload.interventions
                self.savedInterventions = payload.savedInterventions ?? []
            }
        } catch {
            await MainActor.run {
                self.loadError = error.localizedDescription
            }
        }
        isLoading = false
    }
    
    private func todayHeadline(from estimate: StateEstimate) -> String {
        // MVP: focus on stress; bucket client-side based on value.
        if let stress = estimate.stress {
            switch stress {
            case let x where x >= 0.7:
                return "Today: Elevated Stress"
            case let x where x >= 0.4:
                return "Today: Moderate Stress"
            default:
                return "Today: Stable"
            }
        }
        return "Today"
    }
    
    private func todaySubtitle(from estimate: StateEstimate) -> String? {
        guard let stress = estimate.stress else { return nil }
        
        if stress >= 0.7 {
            return "You're carrying a lot right now. Small resets can help you rebalance."
        } else if stress >= 0.4 {
            return "You're in the middle zone. A brief pause can keep things steady."
        } else {
            return "Your system looks steady. Keep honoring the small things that help."
        }
    }
    
    private func recordShownIfNeeded(_ intervention: Intervention, surface: String) {
        guard let interactionService,
              let userId = authViewModel.user?.userId else { return }
        
        // Deduplicate: only log "shown" once per (intervention_instance_id, surface) combination
        let dedupKey = "\(intervention.interventionInstanceId):\(surface)"
        guard !shownInterventions.contains(dedupKey) else { return }
        
        shownInterventions.insert(dedupKey)
        
        Task {
            try? await interactionService.recordInteraction(
                intervention: intervention,
                eventType: "shown",
                userId: userId
            )
        }
    }
}
