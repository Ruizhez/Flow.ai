
import Foundation
enum TaskCategory: String, Codable, CaseIterable { case work, personal, wellness, learning }
struct Task: Identifiable, Codable {
    var id = UUID()
    var title: String
    var due: Date? = nil
    var category: TaskCategory
    var effort: Int
}
enum ReadinessLevel: String, Codable { case high, medium, low }
