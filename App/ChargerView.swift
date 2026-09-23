import SwiftUI

struct ChargerView: View {
    @StateObject private var model = ChargerViewModel()
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Section("BENY Charger") {
                    LabeledContent("Connection") {
                        Label(model.isConnected ? "Connected" : "Disconnected", systemImage: model.isConnected ? "circle.fill" : "circle")
                            .foregroundStyle(model.isConnected ? .green : .secondary)
                    }
                    LabeledContent("IP", value: model.ipAddress)
                    LabeledContent("Modelo", value: model.dashboard.model)
                }
                Section("Estado") {
                    LabeledContent("Status", value: model.dashboard.values?.state.displayName ?? "—")
                    LabeledContent("Power", value: model.dashboard.values.map { String(format: "%.1f kW", $0.powerKilowatts) } ?? "—")
                    LabeledContent("Current", value: model.dashboard.values.map { "\($0.currentAmps) A" } ?? "—")
                    LabeledContent("Voltage", value: model.dashboard.values.map { "\($0.voltageVolts) V" } ?? "—")
                    LabeledContent("Energy", value: model.dashboard.values.map { String(format: "%.1f kWh", $0.totalEnergyKilowattHours) } ?? "—")
                    LabeledContent("Error", value: model.dashboard.status.activeFaults.isEmpty ? "Ninguno" : model.dashboard.status.activeFaults.joined(separator: ", "))
                }
                Section {
                    Button("Refresh") { model.refresh() }.disabled(model.isWorking)
                    Button("Start Charging") { model.startCharging() }.disabled(model.isWorking)
                    Button("Stop Charging", role: .destructive) { model.stopCharging() }.disabled(model.isWorking)
                    HStack {
                        Text("Current limit")
                        Spacer()
                        Button { adjustCurrent(-1) } label: { Image(systemName: "minus.circle") }
                        Text("\(model.dashboard.values?.maxCurrentAmps ?? 16) A").monospacedDigit()
                        Button { adjustCurrent(1) } label: { Image(systemName: "plus.circle") }
                    }.disabled(model.isWorking)
                }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                Section("Diagnóstico") {
                    Toggle("Activar registro", isOn: $model.debugEnabled)
                    if model.debugEnabled {
                        ForEach(model.debugEvents) { event in
                            VStack(alignment: .leading) {
                                Text("\(event.direction) \(event.detail)").font(.caption).foregroundStyle(.secondary)
                                Text(event.hex).font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .navigationTitle("BENY Charger")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Settings") { showSettings = true } } }
            .overlay { if model.isWorking { ProgressView().controlSize(.large) } }
            .sheet(isPresented: $showSettings) { SettingsView(model: model, isPresented: $showSettings) }
        }
    }

    private func adjustCurrent(_ delta: Int) {
        let current = model.dashboard.values?.maxCurrentAmps ?? 16
        model.setCurrent(min(32, max(6, current + delta)))
    }
}

private struct SettingsView: View {
    @ObservedObject var model: ChargerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("IP address", text: $model.ipAddress).textInputAutocapitalization(.never).keyboardType(.numbersAndPunctuation)
                TextField("UDP port", text: $model.portText).keyboardType(.numberPad)
                TextField("Serial number", text: $model.serialNumber).keyboardType(.numberPad)
                SecureField("PIN", text: $model.pin).keyboardType(.numberPad)
                Button("Test Connection") { model.testConnection() }.disabled(model.isWorking)
                Button("Save") { model.save(); isPresented = false }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { isPresented = false } } }
        }
    }
}
