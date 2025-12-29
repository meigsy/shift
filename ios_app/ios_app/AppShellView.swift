//
//  AppShellView.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct AppShellView: View {
    let authViewModel: AuthViewModel
    let conversationalAgentBaseURL: String
    
    @EnvironmentObject private var chatViewModel: ChatViewModel
    @State private var isSidePanelOpen: Bool = false
    @State private var activeExperience: ExperienceID? = nil
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                ChatView(
                    chatViewModel: chatViewModel,
                    authViewModel: authViewModel,
                    activeExperience: $activeExperience
                )
                
                SidePanelOverlay(
                    isOpen: $isSidePanelOpen,
                    chatViewModel: chatViewModel,
                    authViewModel: authViewModel,
                    onOpenExperience: { activeExperience = $0 }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        withAnimation {
                            isSidePanelOpen.toggle()
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                }
            }
        }
    }
}


