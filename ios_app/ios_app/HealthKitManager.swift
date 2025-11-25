//
//  HealthKitManager.swift
//  ios_app
//
//  Created by SHIFT on 11/25/25.
//

import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitManager: ObservableObject {
    
    private let healthStore = HKHealthStore()
    
    @Published var isAuthorized = false
    @Published var authorizationError: String?
    
    // MARK: - Data Types We Want
    
    /// Types we want to READ from HealthKit
    private var typesToRead: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        
        // Heart data
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRate)
        }
        if let hrv = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrv)
        }
        if let restingHR = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHR)
        }
        
        // Activity
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(steps)
        }
        if let activeEnergy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergy)
        }
        
        // Sleep
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        
        // Workouts
        types.insert(HKWorkoutType.workoutType())
        
        return types
    }
    
    // MARK: - Authorization
    
    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }
    
    func requestAuthorization() async {
        guard isHealthKitAvailable else {
            authorizationError = "HealthKit is not available on this device"
            return
        }
        
        do {
            // Request read-only access (we don't write data)
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)
            isAuthorized = true
            print("✅ HealthKit authorization granted")
        } catch {
            authorizationError = error.localizedDescription
            print("❌ HealthKit authorization failed: \(error)")
        }
    }
    
    // MARK: - Query: Heart Rate (last 24h)
    
    func fetchRecentHeartRates() async -> [HeartRateSample] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            return []
        }
        
        let now = Date()
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: oneDayAgo, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: 100,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                
                let heartRates = samples.map { sample in
                    HeartRateSample(
                        bpm: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
                        timestamp: sample.startDate
                    )
                }
                continuation.resume(returning: heartRates)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Query: HRV (last 7 days)
    
    func fetchRecentHRV() async -> [HRVSample] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return []
        }
        
        let now = Date()
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now)!
        let predicate = HKQuery.predicateForSamples(withStart: sevenDaysAgo, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: 100,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                
                let hrvSamples = samples.map { sample in
                    HRVSample(
                        sdnn: sample.quantity.doubleValue(for: .secondUnit(with: .milli)),
                        timestamp: sample.startDate
                    )
                }
                continuation.resume(returning: hrvSamples)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Query: Steps (today)
    
    func fetchTodaySteps() async -> Int {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            return 0
        }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                guard let sum = result?.sumQuantity(), error == nil else {
                    continuation.resume(returning: 0)
                    return
                }
                continuation.resume(returning: Int(sum.doubleValue(for: .count())))
            }
            healthStore.execute(query)
        }
    }
}

// MARK: - Data Models

struct HeartRateSample: Identifiable {
    let id = UUID()
    let bpm: Double
    let timestamp: Date
}

struct HRVSample: Identifiable {
    let id = UUID()
    let sdnn: Double  // milliseconds
    let timestamp: Date
}

