//
//  ContentView.swift
//  ios_app
//
//  Created by Sylvester Meighan on 11/25/25.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var authViewModel: AuthViewModel
    
    var body: some View {
        if authViewModel.isAuthenticated {
            MainView(authViewModel: authViewModel)
        } else {
            LoginView(authViewModel: authViewModel)
        }
    }
}

#Preview {
    ContentView(authViewModel: AuthViewModel())
}
