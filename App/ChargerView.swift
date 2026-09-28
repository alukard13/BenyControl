import SwiftUI

struct ChargerView: View {
    @StateObject private var model = ChargerViewModel()
    @State private var showSettings = false
    @State private var confirmStart = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cargador BENY") {
                    LabeledContent("Conexión") {
                        HStack(spacing: 8) {
                            Label(model.isConnected ? (model.isWorking ? "Actualizando" : "Conectado") : "Desconectado", systemImage: model.isConnected ? "circle.fill" : "circle")
                                .foregroundStyle(model.isConnected ? .green : .secondary)
                            if model.isWorking { ProgressView().controlSize(.small) }
                        }
                    }
                    LabeledContent("Dirección IP", value: model.ipAddress)
                    LabeledContent("Modelo", value: model.dashboard.model)
                    if let lastUpdated = model.lastUpdated {
                        LabeledContent("Última actualización", value: lastUpdated.formatted(date: .omitted, time: .shortened))
                    }
                }
                Section {
                    PowerGaugeView(values: model.dashboard.values)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section("Estado") {
                    LabeledContent("Estado", value: model.dashboard.values?.state.displayName ?? "Sin datos")
                    LabeledContent("Energía total", value: model.dashboard.values.map { String(format: "%.1f kWh", $0.totalEnergyKilowattHours) } ?? "—")
                    LabeledContent("Temperatura", value: model.dashboard.values.map { "\($0.temperatureCelsius) °C" } ?? "—")
                    LabeledContent("Alertas", value: model.dashboard.status.activeFaults.isEmpty ? "Ninguna" : model.dashboard.status.activeFaults.joined(separator: ", "))
                }
                Section {
                    Button("Actualizar estado") { model.refresh() }.disabled(model.isWorking)
                    Button("Iniciar carga") { confirmStart = true }.disabled(model.isWorking)
                    Button("Detener carga", role: .destructive) { model.stopCharging() }.disabled(model.isWorking)
                    HStack {
                        Text("Límite de corriente")
                        Spacer()
                        Button { adjustCurrent(-1) } label: { Image(systemName: "minus.circle") }
                        Text("\(model.dashboard.values?.maxCurrentAmps ?? 16) A").monospacedDigit()
                        Button { adjustCurrent(1) } label: { Image(systemName: "plus.circle") }
                    }.disabled(model.isWorking)
                }
                if let error = model.errorMessage { Section("Problema") { Text(error).foregroundStyle(.red) } }
                Section("Diagnóstico técnico") {
                    Toggle("Mostrar registro técnico", isOn: $model.debugEnabled)
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Ajustes") { showSettings = true } } }
            .sheet(isPresented: $showSettings) { SettingsView(model: model, isPresented: $showSettings) }
            .task { await model.refreshAutomatically() }
            .confirmationDialog("¿Iniciar la carga?", isPresented: $confirmStart, titleVisibility: .visible) {
                Button("Iniciar carga") { model.startCharging() }
                Button("Cancelar", role: .cancel) { }
            } message: {
                Text("Se enviará la orden de inicio al cargador configurado.")
            }
        }
    }

    private func adjustCurrent(_ delta: Int) {
        let current = model.dashboard.values?.maxCurrentAmps ?? 16
        model.setCurrent(min(32, max(6, current + delta)))
    }
}

private struct PowerGaugeView: View {
    let values: BenyChargerValues?

    private var progress: Double {
        min(max((values?.powerKilowatts ?? 0) / 7.4, 0), 1)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                }

            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 150, height: 150)
                .blur(radius: 30)
                .offset(x: 85, y: -65)

            VStack(spacing: 12) {
                Text("POTENCIA ACTUAL")
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(.secondary)

                ZStack {
                    Circle()
                        .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 15, lineCap: .round))
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            AngularGradient(colors: [.cyan, .blue, .indigo], center: .center, startAngle: .degrees(0), endAngle: .degrees(300)),
                            style: StrokeStyle(lineWidth: 15, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .shadow(color: .blue.opacity(0.24), radius: 6)

                    VStack(spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(values.map { String(format: "%.1f", $0.powerKilowatts) } ?? "—")
                                .font(.system(size: 42, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("kW")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        if let values {
                            Text("\(values.currentAmps) A  ·  \(values.voltageVolts) V")
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Esperando datos")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 190, height: 190)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Potencia actual")
                .accessibilityValue(values.map { "\(String(format: "%.1f", $0.powerKilowatts)) kilovatios, \($0.currentAmps) amperios, \($0.voltageVolts) voltios" } ?? "Sin datos")
            }
            .padding(.vertical, 22)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .animation(.easeInOut(duration: 0.45), value: progress)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: ChargerViewModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            Form {
                TextField("Dirección IP", text: $model.ipAddress).textInputAutocapitalization(.never).keyboardType(.numbersAndPunctuation)
                TextField("Puerto UDP", text: $model.portText).keyboardType(.numberPad)
                TextField("Número de serie", text: $model.serialNumber).keyboardType(.numberPad)
                SecureField("PIN de 6 dígitos", text: $model.pin).keyboardType(.numberPad)
                Button("Probar conexión") { model.testConnection() }.disabled(model.isWorking)
                Button("Guardar") { model.save(); if model.errorMessage == nil { isPresented = false } }
            }
            .navigationTitle("Ajustes")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { isPresented = false } } }
        }
    }
}
