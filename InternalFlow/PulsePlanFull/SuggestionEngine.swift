
import Foundation
final class SuggestionEngine: ObservableObject {
    func suggest(level:ReadinessLevel,tasks:[Task])->String{
        switch level{
        case .high:return "🚀 Dive into deep work"
        case .medium:return "✉️ Reply to quick email"
        case .low:return "🧘‍♂️ Take a stretch break"
        }
    }
}
