
import Combine
final class Advisor: ObservableObject {
    @Published var latestSuggestion:String="Tap Suggest"
    private var bag=Set<AnyCancellable>()
    func bind(hk:HealthKitManager,tasks:TaskStore,engine:SuggestionEngine){
        hk.$level.removeDuplicates().sink{ lvl in
            self.latestSuggestion=engine.suggest(level:lvl,tasks:tasks.tasks)
        }.store(in:&bag)
    }
}
