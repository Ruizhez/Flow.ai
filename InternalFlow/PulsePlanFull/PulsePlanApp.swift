
import SwiftUI

@main
struct PulsePlanApp: App {
    @StateObject private var hk      = HealthKitManager()
    @StateObject private var tasks   = TaskStore()
    @StateObject private var speech  = SpeechManager()
    @StateObject private var sugg    = SuggestionEngine()
    @StateObject private var advisor = Advisor()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(hk)
                .environmentObject(tasks)
                .environmentObject(speech)
                .environmentObject(sugg)
                .environmentObject(advisor)
                .onAppear {
                    hk.requestAuthorization()
                    advisor.bind(hk: hk, tasks: tasks, engine: sugg)
                }
        }
    }
}
