//
//  BreathingExperienceView.swift
//  ios_app
//
//  Fullscreen breathing exercise experience
//

import SwiftUI

struct BreathingExperienceView: View {
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
            Text("Sit tall")
                .font(.largeTitle.weight(.bold))
            Text("10 seconds")
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
    
    private var page2: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Breathe in 4, out 6")
                .font(.largeTitle.weight(.bold))
            Text("40 seconds")
                .font(.title2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }
    
    private var page3: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("Notice how you feel")
                .font(.largeTitle.weight(.bold))
            Text("10 seconds")
                .font(.title2)
                .foregroundStyle(.secondary)
            Button {
                onComplete()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
            Spacer()
        }
        .padding()
    }
}



