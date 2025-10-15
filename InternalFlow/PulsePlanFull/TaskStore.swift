
import Combine
import Foundation

final class TaskStore: ObservableObject {
    @Published var tasks: [Task] = []
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("tasks.json")
    private var bag = Set<AnyCancellable>()

    init() { load(); $tasks.dropFirst().sink{ [weak self] _ in self?.save() }.store(in:&bag) }
    func add(_ t:Task){ tasks.append(t) }
    func remove(at o:IndexSet){ tasks.remove(atOffsets:o) }
    private func load(){ if let d=try?Data(contentsOf:url), let t=try?JSONDecoder().decode([Task].self,from:d){ tasks=t } }
    private func save(){ if let d=try?JSONEncoder().encode(tasks){ try? d.write(to:url)} }
}
