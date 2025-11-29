//
//  MainView.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import SwiftUI

struct MainView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var healthKit = HealthKitManager()
    
    @State private var heartRates: [HeartRateSample] = []
    @State private var hrvSamples: [HRVSample] = []
    @State private var todaySteps: Int = 0
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            List {
                // User Info Section
                if let user = authViewModel.user {
                    Section {
                        HStack {
                            Label("User ID", systemImage: "person.circle")
                            Spacer()
                            Text(user.userId)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        if let email = user.email {
                            HStack {
                                Label("Email", systemImage: "envelope")
                                Spacer()
                                Text(email)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Button {
                            authViewModel.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "arrow.right.square")
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Account")
                    }
                }
                
                // Authorization Section
                Section {
                    if !healthKit.isHealthKitAvailable {
                        Label("HealthKit not available", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    } else if healthKit.isAuthorized {
                        Label("HealthKit connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button {
                            Task {
                                await healthKit.requestAuthorization()
                            }
                        } label: {
                            Label("Connect HealthKit", systemImage: "heart.circle")
                        }
                    }
                    
                    if let error = healthKit.authorizationError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Connection")
                }
                
                // Data Section
                if healthKit.isAuthorized {
                    Section {
                        HStack {
                            Label("Steps today", systemImage: "figure.walk")
                            Spacer()
                            Text("\(todaySteps)")
                                .fontWeight(.semibold)
                        }
                    } header: {
                        Text("Activity")
                    }
                    
                    Section {
                        if heartRates.isEmpty {
                            Text("No heart rate data")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(heartRates.prefix(5)) { sample in
                                HStack {
                                    Label("\(Int(sample.bpm)) bpm", systemImage: "heart.fill")
                                        .foregroundStyle(.red)
                                    Spacer()
                                    Text(sample.timestamp, style: .time)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Heart Rate (last 24h)")
                    }
                    
                    Section {
                        if hrvSamples.isEmpty {
                            Text("No HRV data")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(hrvSamples.prefix(5)) { sample in
                                HStack {
                                    Label("\(Int(sample.sdnn)) ms", systemImage: "waveform.path.ecg")
                                        .foregroundStyle(.purple)
                                    Spacer()
                                    Text(sample.timestamp, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("HRV (last 7 days)")
                    }
                    
                    Section {
                        Button {
                            Task {
                                await fetchAllData()
                            }
                        } label: {
                            if isLoading {
                                ProgressView()
                            } else {
                                Label("Refresh Data", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(isLoading)
                    }
                }
            }
            .navigationTitle("SHIFT")
            .task {
                // Auto-fetch data if already authorized
                if healthKit.isAuthorized {
                    await fetchAllData()
                }
            }
            .onChange(of: healthKit.isAuthorized) { _, authorized in
                if authorized {
                    Task {
                        await fetchAllData()
                    }
                }
            }
        }
    }
    
    private func fetchAllData() async {
        isLoading = true
        async let hr = healthKit.fetchRecentHeartRates()
        async let hrv = healthKit.fetchRecentHRV()
        async let steps = healthKit.fetchTodaySteps()
        
        heartRates = await hr
        hrvSamples = await hrv
        todaySteps = await steps
        isLoading = false
    }
}

#Preview {
    let authViewModel = AuthViewModel()
    authViewModel.isAuthenticated = true
    authViewModel.user = User(
        id: "test-user",
        userId: "test-user",
        email: "test@example.com",
        displayName: "Test User",
        createdAt: nil
    )
    return MainView(authViewModel: authViewModel)
}


