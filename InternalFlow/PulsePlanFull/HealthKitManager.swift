
import Combine
import Foundation
final class HealthKitManager: ObservableObject {
    @Published var readiness: Double = 72
    @Published var fatigue: Double = 30
    @Published var level: ReadinessLevel = .medium
    func requestAuthorization() {}
}
