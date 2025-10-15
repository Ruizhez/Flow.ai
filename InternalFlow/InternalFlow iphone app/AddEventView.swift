//
//  AddEventView.swift
//  InternalFlow
//
//  Created by Ruizhe Zheng on 4/25/25.
//

import SwiftUI

struct AddEventView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var newEventName = ""
    @State private var newEventDeadline = Date()
    @State private var newEventTime = 1.0
    @State private var newEventLevel = "Easy"

    let levels = ["Easy", "Medium", "Hard"]

    var body: some View {
        VStack(spacing: 20) {
            Text("Add New Event")
                .font(.title)
                .bold()

            TextField("Enter event name", text: $newEventName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            DatePicker("Select Deadline", selection: $newEventDeadline, displayedComponents: .date)
                .datePickerStyle(GraphicalDatePickerStyle())
                .padding(.horizontal)

            Stepper(value: $newEventTime, in: 0.5...12, step: 0.5) {
                Text("Estimated time: \(newEventTime, specifier: "%.1f") hours")
            }
            .padding(.horizontal)

            Picker("Difficulty", selection: $newEventLevel) {
                ForEach(levels, id: \.self) { level in
                    Text(level)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            Button("Add") {
                if !newEventName.isEmpty {
                    EventManager.shared.addEvent(
                        name: newEventName,
                        deadline: newEventDeadline,
                        time: newEventTime,
                        level: newEventLevel
                    )
                    dismiss()
                }
            }
        }
        .padding()
    }
}
