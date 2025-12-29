//
//  ContentView.swift
//  ios_app
//
//  Created by Sylvester Meighan on 11/25/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @AppStorage("useChatShell") private var useChatShell: Bool = true
    
    // Create ChatViewModel at this level so it's available to both AppShellView and MainView
    @StateObject private var chatViewModel: ChatViewModel
    
    init(authViewModel: AuthViewModel, conversationalAgentBaseURL: String) {
        self.authViewModel = authViewModel
        
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
        Group {
            if authViewModel.isAuthenticated {
                if useChatShell {
                    AppShellView(
                        authViewModel: authViewModel,
                        conversationalAgentBaseURL: ios_appApp.CONVERSATIONAL_AGENT_BASE_URL
                    )
                } else {
                    MainView(authViewModel: authViewModel)
                }
            } else {
                LoginView(authViewModel: authViewModel)
            }
        }
        .environmentObject(chatViewModel)
    }
}

#Preview {
    ContentView(
        authViewModel: AuthViewModel(),
        conversationalAgentBaseURL: "https://conversational-agent-meqmyk4w5q-uc.a.run.app"
    )
}
