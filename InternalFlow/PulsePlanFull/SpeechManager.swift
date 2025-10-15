
import Foundation
import Combine
final class SpeechManager: ObservableObject {
    @Published var recording=false
    func start(onResult:@escaping(String)->Void){ onResult("Simulated task") }
    func stop(){}
}
