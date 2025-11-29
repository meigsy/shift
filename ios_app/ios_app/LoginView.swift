//
//  LoginView.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import SwiftUI
import AuthenticationServices

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "heart.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.red)
                
                Text("SHIFT")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Your personal health operating system")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Button {
                    authViewModel.signInWithApple()
                } label: {
                    HStack {
                        Image(systemName: "applelogo")
                            .font(.system(size: 18, weight: .medium))
                        Text("Continue with Apple")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.black)
                    .cornerRadius(8)
                }
                
                // Test bypass button for simulator (Sign in with Apple doesn't work reliably in simulator)
                Button {
                    authViewModel.signInWithMock()
                } label: {
                    HStack {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 18, weight: .medium))
                        Text("Test Sign In (Bypass)")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                
                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding()
    }
}

#Preview {
    LoginView(authViewModel: AuthViewModel())
}

