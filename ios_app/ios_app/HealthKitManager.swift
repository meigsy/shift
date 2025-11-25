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
    @Published var backgroundDeliveryEnabled = false
    
    // MARK: - Data Types for State Estimation
    
    /// All quantity types we want to read
    private var quantityTypes: [HKQuantityTypeIdentifier] {
        [
            // Heart & Recovery
            .heartRate,
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .walkingHeartRateAverage,
            
            // Respiratory & Oxygen
            .respiratoryRate,
            .oxygenSaturation,
            
            // Fitness
            .vo2Max,
            .appleWalkingSteadiness,
            
            // Activity
            .stepCount,
            .activeEnergyBurned,
            .appleExerciseTime,
            .appleStandTime,
            
            // Environment
            .timeInDaylight,
            
            // Body Composition (Withings)
            .bodyMass,
            .bodyFatPercentage,
            .leanBodyMass,
        ]
    }
    
    /// Category types we want to read
    private var categoryTypes: [HKCategoryTypeIdentifier] {
        [
            .sleepAnalysis,
        ]
    }
    
    /// All types combined for authorization
    private var typesToRead: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        
        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        
        for identifier in categoryTypes {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
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
            print("✅ HealthKit authorization granted for \(typesToRead.count) types")
            
            // Enable background delivery after authorization
            await enableBackgroundDelivery()
        } catch {
            authorizationError = error.localizedDescription
            print("❌ HealthKit authorization failed: \(error)")
        }
    }
    
    // MARK: - Background Delivery
    
    /// Enable background delivery for key types so we get notified when new data arrives
    func enableBackgroundDelivery() async {
        let criticalTypes: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .heartRateVariabilitySDNN,
            .stepCount,
            .activeEnergyBurned,
        ]
        
        for identifier in criticalTypes {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            
            do {
                try await healthStore.enableBackgroundDelivery(for: type, frequency: .immediate)
                print("✅ Background delivery enabled for \(identifier.rawValue)")
            } catch {
                print("⚠️ Background delivery failed for \(identifier.rawValue): \(error)")
            }
        }
        
        // Sleep analysis
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            do {
                try await healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate)
                print("✅ Background delivery enabled for sleep")
            } catch {
                print("⚠️ Background delivery failed for sleep: \(error)")
            }
        }
        
        backgroundDeliveryEnabled = true
    }
    
    // MARK: - Fetch All Data for Sync
    
    /// Fetch all health data since a given date (for sync)
    func fetchAllDataSince(_ since: Date) async -> HealthDataBatch {
        async let heartRates = fetchQuantitySamples(.heartRate, since: since, unit: .beatsPerMinute)
        async let hrv = fetchQuantitySamples(.heartRateVariabilitySDNN, since: since, unit: .ms)
        async let restingHR = fetchQuantitySamples(.restingHeartRate, since: since, unit: .beatsPerMinute)
        async let walkingHR = fetchQuantitySamples(.walkingHeartRateAverage, since: since, unit: .beatsPerMinute)
        async let respiratoryRate = fetchQuantitySamples(.respiratoryRate, since: since, unit: .breathsPerMinute)
        async let oxygenSaturation = fetchQuantitySamples(.oxygenSaturation, since: since, unit: .percent)
        async let vo2Max = fetchQuantitySamples(.vo2Max, since: since, unit: .vo2Max)
        async let steps = fetchQuantitySamples(.stepCount, since: since, unit: .count)
        async let activeEnergy = fetchQuantitySamples(.activeEnergyBurned, since: since, unit: .kilocalorie)
        async let exerciseTime = fetchQuantitySamples(.appleExerciseTime, since: since, unit: .minute)
        async let standTime = fetchQuantitySamples(.appleStandTime, since: since, unit: .minute)
        async let daylight = fetchQuantitySamples(.timeInDaylight, since: since, unit: .minute)
        async let bodyMass = fetchQuantitySamples(.bodyMass, since: since, unit: .kilogram)
        async let bodyFat = fetchQuantitySamples(.bodyFatPercentage, since: since, unit: .percent)
        async let leanMass = fetchQuantitySamples(.leanBodyMass, since: since, unit: .kilogram)
        async let sleep = fetchSleepSamples(since: since)
        async let workouts = fetchWorkouts(since: since)
        
        return await HealthDataBatch(
            heartRate: heartRates,
            hrv: hrv,
            restingHeartRate: restingHR,
            walkingHeartRateAverage: walkingHR,
            respiratoryRate: respiratoryRate,
            oxygenSaturation: oxygenSaturation,
            vo2Max: vo2Max,
            steps: steps,
            activeEnergy: activeEnergy,
            exerciseTime: exerciseTime,
            standTime: standTime,
            timeInDaylight: daylight,
            bodyMass: bodyMass,
            bodyFatPercentage: bodyFat,
            leanBodyMass: leanMass,
            sleep: sleep,
            workouts: workouts,
            fetchedAt: Date()
        )
    }
    
    // MARK: - Generic Quantity Query
    
    private func fetchQuantitySamples(
        _ identifier: HKQuantityTypeIdentifier,
        since: Date,
        unit: HealthUnit,
        limit: Int = HKObjectQueryNoLimit
    ) async -> [QuantitySample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: limit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results = samples.map { sample in
                    QuantitySample(
                        type: identifier.rawValue,
                        value: sample.quantity.doubleValue(for: unit.hkUnit),
                        unit: unit.rawValue,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sourceName: sample.sourceRevision.source.name,
                        sourceBundle: sample.sourceRevision.source.bundleIdentifier
                    )
                }
                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Sleep Query
    
    private func fetchSleepSamples(since: Date) async -> [SleepSample] {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return []
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKCategorySample], error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results = samples.map { sample in
                    SleepSample(
                        stage: SleepStage(rawValue: sample.value) ?? .unknown,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        sourceName: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Workout Query
    
    private func fetchWorkouts(since: Date) async -> [WorkoutSample] {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                guard let samples = samples as? [HKWorkout], error == nil else {
                    continuation.resume(returning: [])
                    return
                }
                
                let results = samples.map { workout in
                    WorkoutSample(
                        activityType: workout.workoutActivityType.name,
                        duration: workout.duration,
                        totalEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: .kilocalorie()),
                        totalDistance: workout.totalDistance?.doubleValue(for: .meter()),
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        sourceName: workout.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: results)
            }
            healthStore.execute(query)
        }
    }
    
    // MARK: - Convenience Methods (for UI)
    
    func fetchRecentHeartRates() async -> [HeartRateSample] {
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let samples = await fetchQuantitySamples(.heartRate, since: oneDayAgo, unit: .beatsPerMinute, limit: 100)
        return samples.map { HeartRateSample(bpm: $0.value, timestamp: $0.startDate) }
    }
    
    func fetchRecentHRV() async -> [HRVSample] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let samples = await fetchQuantitySamples(.heartRateVariabilitySDNN, since: sevenDaysAgo, unit: .ms, limit: 100)
        return samples.map { HRVSample(sdnn: $0.value, timestamp: $0.startDate) }
    }
    
    func fetchTodaySteps() async -> Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let samples = await fetchQuantitySamples(.stepCount, since: startOfDay, unit: .count)
        return Int(samples.reduce(0) { $0 + $1.value })
    }
}

// MARK: - Health Units

enum HealthUnit: String {
    case beatsPerMinute = "bpm"
    case ms = "ms"
    case breathsPerMinute = "breaths/min"
    case percent = "%"
    case vo2Max = "mL/kg/min"
    case count = "count"
    case kilocalorie = "kcal"
    case minute = "min"
    case kilogram = "kg"
    
    var hkUnit: HKUnit {
        switch self {
        case .beatsPerMinute:
            return HKUnit.count().unitDivided(by: .minute())
        case .ms:
            return .secondUnit(with: .milli)
        case .breathsPerMinute:
            return HKUnit.count().unitDivided(by: .minute())
        case .percent:
            return .percent()
        case .vo2Max:
            return HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())
        case .count:
            return .count()
        case .kilocalorie:
            return .kilocalorie()
        case .minute:
            return .minute()
        case .kilogram:
            return .gramUnit(with: .kilo)
        }
    }
}

// MARK: - Sleep Stages

enum SleepStage: Int {
    case inBed = 0
    case asleepUnspecified = 1
    case awake = 2
    case asleepCore = 3
    case asleepDeep = 4
    case asleepREM = 5
    case unknown = -1
    
    var name: String {
        switch self {
        case .inBed: return "in_bed"
        case .asleepUnspecified: return "asleep"
        case .awake: return "awake"
        case .asleepCore: return "core"
        case .asleepDeep: return "deep"
        case .asleepREM: return "rem"
        case .unknown: return "unknown"
        }
    }
}

// MARK: - Data Models

struct QuantitySample: Codable, Identifiable {
    var id: String { "\(type)-\(startDate.timeIntervalSince1970)" }
    let type: String
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let sourceName: String
    let sourceBundle: String
}

struct SleepSample: Codable, Identifiable {
    var id: String { "\(stage.name)-\(startDate.timeIntervalSince1970)" }
    let stage: SleepStage
    let startDate: Date
    let endDate: Date
    let sourceName: String
    
    enum CodingKeys: String, CodingKey {
        case stage, startDate, endDate, sourceName
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(stage.name, forKey: .stage)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(endDate, forKey: .endDate)
        try container.encode(sourceName, forKey: .sourceName)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stageName = try container.decode(String.self, forKey: .stage)
        self.stage = SleepStage.allCases.first { $0.name == stageName } ?? .unknown
        self.startDate = try container.decode(Date.self, forKey: .startDate)
        self.endDate = try container.decode(Date.self, forKey: .endDate)
        self.sourceName = try container.decode(String.self, forKey: .sourceName)
    }
    
    init(stage: SleepStage, startDate: Date, endDate: Date, sourceName: String) {
        self.stage = stage
        self.startDate = startDate
        self.endDate = endDate
        self.sourceName = sourceName
    }
}

extension SleepStage: CaseIterable {}

struct WorkoutSample: Codable, Identifiable {
    var id: String { "\(activityType)-\(startDate.timeIntervalSince1970)" }
    let activityType: String
    let duration: TimeInterval
    let totalEnergyBurned: Double?
    let totalDistance: Double?
    let startDate: Date
    let endDate: Date
    let sourceName: String
}

struct HealthDataBatch: Codable {
    let heartRate: [QuantitySample]
    let hrv: [QuantitySample]
    let restingHeartRate: [QuantitySample]
    let walkingHeartRateAverage: [QuantitySample]
    let respiratoryRate: [QuantitySample]
    let oxygenSaturation: [QuantitySample]
    let vo2Max: [QuantitySample]
    let steps: [QuantitySample]
    let activeEnergy: [QuantitySample]
    let exerciseTime: [QuantitySample]
    let standTime: [QuantitySample]
    let timeInDaylight: [QuantitySample]
    let bodyMass: [QuantitySample]
    let bodyFatPercentage: [QuantitySample]
    let leanBodyMass: [QuantitySample]
    let sleep: [SleepSample]
    let workouts: [WorkoutSample]
    let fetchedAt: Date
    
    var totalSampleCount: Int {
        heartRate.count + hrv.count + restingHeartRate.count + walkingHeartRateAverage.count +
        respiratoryRate.count + oxygenSaturation.count + vo2Max.count + steps.count +
        activeEnergy.count + exerciseTime.count + standTime.count + timeInDaylight.count +
        bodyMass.count + bodyFatPercentage.count + leanBodyMass.count + sleep.count + workouts.count
    }
}

// Legacy models for UI compatibility
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

// MARK: - Workout Activity Type Extension

extension HKWorkoutActivityType {
    var name: String {
        switch self {
        case .running: return "running"
        case .walking: return "walking"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining: return "strength_training"
        case .traditionalStrengthTraining: return "strength_training"
        case .highIntensityIntervalTraining: return "hiit"
        case .coreTraining: return "core_training"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        case .stairClimbing: return "stair_climbing"
        case .crossTraining: return "cross_training"
        case .mixedCardio: return "mixed_cardio"
        case .pilates: return "pilates"
        case .dance: return "dance"
        case .cooldown: return "cooldown"
        case .mindAndBody: return "mind_and_body"
        default: return "other"
        }
    }
}
