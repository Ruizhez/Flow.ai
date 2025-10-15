import SwiftUI
struct ContentView: View {
    @State private var message = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Study Reminder Assistant")
                    .font(.title)
                    .bold()
                NavigationLink("Add an Event") {
                    AddEventView()
                }
                .buttonStyle(.borderedProminent)
                NavigationLink("Get Today's Plan") {
                    CurrentPlanView()
                }
                Text(message)
                    .padding()
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}
