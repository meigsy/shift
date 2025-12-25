//
//  SidePanelOverlay.swift
//  ios_app
//
//  Created by SHIFT on 12/25/25.
//

import SwiftUI

struct SidePanelOverlay: View {
    @Binding var isOpen: Bool
    let chatViewModel: ChatViewModel
    let authViewModel: AuthViewModel
    @State private var showSettings: Bool = false
    
    private let panelWidth: CGFloat = 280
    
    var body: some View {
        ZStack(alignment: .leading) {
            if isOpen {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            isOpen = false
                        }
                    }
                
                sidePanel
                    .transition(.move(edge: .leading))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isOpen)
    }
    
    private var sidePanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider()
            newChatSection
            Divider()
            pastChatsSection
            Divider()
            Spacer()
            Divider()
            userMenuSection
        }
        .frame(width: panelWidth, alignment: .leading)
        .background(Color(.systemBackground))
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.width < -50 {
                        withAnimation {
                            isOpen = false
                        }
                    }
                }
        )
    }
    
    private var headerSection: some View {
        HStack {
            Text("SHIFT")
                .font(.title2)
                .fontWeight(.bold)
            Spacer()
            Button {
                withAnimation {
                    isOpen = false
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    private var newChatSection: some View {
        Button {
            chatViewModel.startNewChat()
            withAnimation {
                isOpen = false
            }
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("New Chat")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .buttonStyle(.plain)
    }
    
    private var pastChatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Past Chats")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)
            
            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal)
                .padding(.bottom)
        }
    }
    
    private var userMenuSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("User Menu")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.top)
            
            Button {
                withAnimation {
                    isOpen = false
                }
                showSettings = true
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showSettings) {
                SettingsView(authViewModel: authViewModel)
            }
            
            Button {
                authViewModel.signOut()
                withAnimation {
                    isOpen = false
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.right.square")
                    Text("Logout")
                }
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom)
    }
}

