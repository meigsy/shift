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
    
    @StateObject private var chatViewModel: ChatViewModel
    @State private var isSidePanelOpen: Bool = false
    
    init(authViewModel: AuthViewModel, conversationalAgentBaseURL: String) {
        self.authViewModel = authViewModel
        self.conversationalAgentBaseURL = conversationalAgentBaseURL
        
        let chatService = ChatService(
            baseURL: conversationalAgentBaseURL,
            authViewModel: authViewModel
        )
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(
            chatService: chatService,
            authViewModel: authViewModel
        ))
    }
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                ChatView(chatViewModel: chatViewModel)
                
                SidePanelOverlay(
                    isOpen: $isSidePanelOpen,
                    chatViewModel: chatViewModel,
                    authViewModel: authViewModel
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


