import SwiftUI

struct ContentView:  View {
    @State private var message = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Study Reminder Assistant")
                    .font(.headline)

                NavigationLink("Add Event") {
                    AddEventView()
                }

                NavigationLink("Start Now") {
                    UserFeelings()
                }

                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .padding()
        }
    }
}
