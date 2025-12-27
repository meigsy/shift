//
//  OnboardingExperienceView.swift
//  ios_app
//
//  Fullscreen onboarding experience
//

import SwiftUI

struct OnboardingExperienceView: View {
    let onClose: () -> Void
    let onComplete: () -> Void
    
    @State private var currentPage = 0
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            TabView(selection: $currentPage) {
                page1
                    .tag(0)
                page2
                    .tag(1)
                page3
                    .tag(2)
                page4
                    .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
            .padding(.top, 8)
            .padding(.leading, 8)
        }
    }
    
    private var page1: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Welcome to SHIFT")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Your personal health operating system")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
    }
    
    private var page2: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Mind · Body · Bell")
                .font(.largeTitle.weight(.bold))
            VStack(spacing: 24) {
                featureRow(icon: "brain.head.profile", title: "Mind", description: "Mental wellness and clarity")
                featureRow(icon: "figure.walk", title: "Body", description: "Physical health and energy")
                featureRow(icon: "bell", title: "Bell", description: "Gentle nudges when you need them")
            }
            Spacer()
        }
        .padding()
    }
    
    private var page3: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("How it works")
                .font(.largeTitle.weight(.bold))
            VStack(alignment: .leading, spacing: 20) {
                Text("1. We learn from your health data")
                    .font(.title3)
                Text("2. We offer gentle interventions when helpful")
                    .font(.title3)
                Text("3. You stay in control")
                    .font(.title3)
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding()
    }
    
    private var page4: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Ready to begin?")
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
            Button {
                onComplete()
            } label: {
                Text("Start")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .padding()
    }
    
    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.blue)
                .frame(width: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal)
    }
}

