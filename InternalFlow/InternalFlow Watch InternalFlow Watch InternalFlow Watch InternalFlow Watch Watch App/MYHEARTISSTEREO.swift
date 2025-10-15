//
//  MYHEARTISSTEREO.swift
//  InternalFlow
//
//  Created by Ruizhe Zheng on 5/31/25.
//

import HealthKit
let healthStore = HKHealthStore()

func requestHeartRateAccess() async throws -> Double? {
    guard HKHealthStore.isHealthDataAvailable() else { return nil }

    let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
    let typesToRead: Set = [heartRateType]

    return try await withCheckedThrowingContinuation { continuation in
        healthStore.requestAuthorization(toShare: [], read: typesToRead) { success, error in
            if success {
                Task {
                    do {
                        let bpm = try await fetchLatestHeartRateAsync()
                        continuation.resume(returning: bpm)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } else if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}

func requestRateVariabilityAccess() async throws -> Double? {
    guard HKHealthStore.isHealthDataAvailable() else { return nil }

    // 要访问的类型：HRV（SDNN）
    guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
        return nil
    }
    let typesToRead: Set = [hrvType]

    return try await withCheckedThrowingContinuation { continuation in
        healthStore.requestAuthorization(toShare: [], read: typesToRead) { success, error in
            if success {
                Task {
                    do {
                        let hrv = try await fetchLatestHRVAsync()
                        continuation.resume(returning: hrv)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            } else if let error = error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }
}

func fetchLatestHeartRateAsync() async throws -> Double? {
    return try await withCheckedThrowingContinuation { continuation in
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            continuation.resume(returning: nil)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: heartRateType,
                                  predicate: nil,
                                  limit: 1,
                                  sortDescriptors: [sortDescriptor]) { _, results, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }

            if let result = results?.first as? HKQuantitySample {
                let bpm = result.quantity.doubleValue(for: HKUnit(from: "count/min"))
                continuation.resume(returning: bpm)
            } else {
                continuation.resume(returning: nil)
            }
        }

        healthStore.execute(query)
    }
}

func fetchLatestHRVAsync() async throws -> Double? {
    return try await withCheckedThrowingContinuation { continuation in
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            continuation.resume(returning: nil)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(sampleType: hrvType,
                                  predicate: nil,
                                  limit: 1,
                                  sortDescriptors: [sortDescriptor]) { _, results, error in
            if let error = error {
                continuation.resume(throwing: error)
                return
            }

            if let result = results?.first as? HKQuantitySample {
                let hrv = result.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                continuation.resume(returning: hrv)
            } else {
                continuation.resume(returning: nil)
            }
        }

        healthStore.execute(query)
    }
}
