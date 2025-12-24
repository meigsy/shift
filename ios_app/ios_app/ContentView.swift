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
    
    var body: some View {
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
}

#Preview {
    ContentView(authViewModel: AuthViewModel())
}
