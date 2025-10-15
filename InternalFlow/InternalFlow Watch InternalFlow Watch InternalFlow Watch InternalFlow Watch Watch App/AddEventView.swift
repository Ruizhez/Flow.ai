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
    @State private var newEventEstimateTime = 0.00
    @State private var newEventLevel = ""
    let levels = ["Easy", "Medium", "Hard"]
    var body: some View {
        Form {
            Section("Event Name") {
                TextField("Math Project", text: $newEventName)
            }

            Section("Deadline") {
                DatePicker("", selection: $newEventDeadline, displayedComponents: .date)
            }
            Section("Estimated Time (hrs)") {
                Stepper(value: $newEventEstimateTime, in: 0...24, step: 0.5) {
                    Text("Estimate Time \(newEventEstimateTime, specifier: "%.1f") hrs")
                        .font(.footnote) // 或 .caption、.caption2 都可以
                           }
                       }
            Section("Difficulty Level") {
                Picker("Choose Level", selection: $newEventLevel) {
                    ForEach(levels, id: \.self) { level in
                        Text(level)
                               }
                           }
                       }
            Button("Confirm Add") {
                if !newEventName.isEmpty {
                    EventManager.shared.addEvent(name: newEventName, deadline: newEventDeadline, time: newEventEstimateTime, level: newEventLevel)
                    dismiss()
                }
            }
        }
    }
}
