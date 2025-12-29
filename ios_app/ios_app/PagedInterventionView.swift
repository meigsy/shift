//
//  PagedInterventionView.swift
//  ios_app
//
//  Paged full-screen flow for interventions
//

import SwiftUI

struct PagedInterventionView: View {
    let intervention: Intervention
    let interactionService: InteractionService?
    let userId: String
    
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var currentPage = 0
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            TabView(selection: $currentPage) {
                ForEach(Array((intervention.pages ?? []).enumerated()), id: \.offset) { index, page in
                    pageView(for: page, isLastPage: index == (intervention.pages?.count ?? 0) - 1)
                        .tag(index)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            
            // X button in top-left
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .padding(.top, 8)
            .padding(.leading, 8)
        }
        .background(Color(uiColor: .systemBackground))
    }
    
    @ViewBuilder
    private func pageView(for page: InterventionPage, isLastPage: Bool) -> some View {
        VStack(spacing: 32) {
            Spacer()
            
            switch page.template {
            case "hero":
                heroPage(page)
            case "feature_list":
                featureListPage(page)
            case "bullet_list":
                bulletListPage(page)
            case "cta":
                ctaPage(page, isLastPage: isLastPage)
            default:
                Text("Unknown template: \(page.template)")
            }
            
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 24)
    }
    
    private func heroPage(_ page: InterventionPage) -> some View {
        VStack(spacing: 16) {
            Text(page.title ?? "")
                .font(.system(size: 34, weight: .bold))
                .multilineTextAlignment(.center)
            
            Text(page.subtitle ?? "")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func featureListPage(_ page: InterventionPage) -> some View {
        VStack(spacing: 24) {
            Text(page.title ?? "")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            
            VStack(spacing: 20) {
                ForEach(Array((page.features ?? []).enumerated()), id: \.offset) { _, feature in
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 32))
                            .foregroundStyle(.blue)
                            .frame(width: 40)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                                .font(.headline)
                            
                            Text(feature.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
    }
    
    private func bulletListPage(_ page: InterventionPage) -> some View {
        VStack(spacing: 24) {
            Text(page.title ?? "")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array((page.bullets ?? []).enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 12) {
                        Text("•")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        
                        Text(bullet)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
    
    private func ctaPage(_ page: InterventionPage, isLastPage: Bool) -> some View {
        VStack(spacing: 32) {
            Text(page.title ?? "")
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
            
            if isLastPage {
                Button {
                    handleCompletion()
                } label: {
                    Text(page.buttonText ?? "Continue")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
    
    private func handleCompletion() {
        // Record flow_completed event
        if let interactionService = interactionService {
            Task {
                try? await interactionService.recordFlowEvent(
                    eventType: "flow_completed",
                    userId: userId,
                    payload: [
                        "flow_id": GettingStartedFlow.flowId,
                        "flow_version": GettingStartedFlow.version
                    ]
                )
            }
        }
        
        // Execute completion_action
        if let completionAction = intervention.action?.completionAction {
            switch completionAction.type {
            case "chat_prompt":
                if let prompt = completionAction.prompt {
                    chatViewModel.injectMessage(role: "assistant", text: prompt)
                }
            default:
                break
            }
        }
        
        // Dismiss
        dismiss()
    }
}
