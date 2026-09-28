import SwiftUI

struct ChargerView: View {
    @StateObject private var model = ChargerViewModel()
    @State private var showSettings = false
    @State private var confirmStart = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Conexión") {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(model.isConnected ? .green : .red)
                            .frame(width: 12, height: 12)
                        Text(model.isConnected ? "Conectado" : "No conectado")
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
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
                    Button("Iniciar carga") { confirmStart = true }.disabled(model.isCommandRunning)
                    Button("Detener carga", role: .destructive) { model.stopCharging() }.disabled(model.isCommandRunning)
                    HStack {
                        Text("Límite de corriente")
                        Spacer()
                        Button { adjustCurrent(-1) } label: { Image(systemName: "minus.circle") }
                        Text("\(model.dashboard.values?.maxCurrentAmps ?? 16) A").monospacedDigit()
                        Button { adjustCurrent(1) } label: { Image(systemName: "plus.circle") }
                    }.disabled(model.isCommandRunning)
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
            .navigationTitle(model.activeChargerName)
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
    @State private var editingCharger: BenyChargerProfile?
    @State private var chargerToDelete: BenyChargerProfile?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Gestionar cargadores") {
                    if model.chargers.isEmpty {
                        Text("Todavía no has añadido ningún cargador.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.chargers) { charger in
                        HStack(spacing: 12) {
                            Button {
                                Task { await model.selectCharger(charger.id) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(charger.name).foregroundStyle(.primary)
                                        Text(charger.ipAddress.isEmpty ? "Sin dirección IP" : charger.ipAddress)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 8)
                                    if charger.id == model.activeChargerID {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                            .accessibilityLabel("Cargador activo")
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                editingCharger = charger
                            } label: {
                                Image(systemName: "pencil")
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Editar \(charger.name)")
                        }
                        .disabled(model.isCommandRunning)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                chargerToDelete = charger
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        editingCharger = BenyChargerProfile.empty(name: model.chargers.isEmpty ? "Mi cargador" : "Cargador nuevo")
                    } label: {
                        Label("Añadir cargador", systemImage: "plus.circle.fill")
                    }
                    .disabled(model.isCommandRunning)
                }
                if let errorMessage {
                    Section("Problema") { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Ajustes")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Listo") { isPresented = false } } }
            .sheet(item: $editingCharger) { charger in
                ChargerEditorView(model: model, charger: charger)
            }
            .confirmationDialog(
                "¿Eliminar este cargador?",
                isPresented: Binding(
                    get: { chargerToDelete != nil },
                    set: { if !$0 { chargerToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Eliminar", role: .destructive) {
                    guard let chargerToDelete else { return }
                    Task {
                        errorMessage = await model.deleteCharger(chargerToDelete.id)
                        self.chargerToDelete = nil
                    }
                }
                Button("Cancelar", role: .cancel) { chargerToDelete = nil }
            } message: {
                Text("Se eliminarán su nombre, su configuración y su PIN guardado.")
            }
        }
    }
}

private struct ChargerEditorView: View {
    @ObservedObject var model: ChargerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: BenyChargerProfile
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(model: ChargerViewModel, charger: BenyChargerProfile) {
        self.model = model
        _draft = State(initialValue: charger)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identificación") {
                    TextField("Nombre personalizado", text: $draft.name)
                        .textInputAutocapitalization(.words)
                }
                Section("Conexión") {
                    TextField("Dirección IP", text: $draft.ipAddress)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("Puerto UDP", text: $draft.portText)
                        .keyboardType(.numberPad)
                    TextField("Número de serie (9 dígitos)", text: $draft.serialNumber)
                        .keyboardType(.numberPad)
                    SecureField("PIN (6 dígitos)", text: $draft.pin)
                        .keyboardType(.numberPad)
                }
                if let errorMessage {
                    Section("Revisa los datos") { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(draft.name.isEmpty ? "Nuevo cargador" : draft.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(isSaving || model.isCommandRunning)
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        isSaving = true
        Task {
            let result = await model.saveCharger(draft)
            isSaving = false
            if let result {
                errorMessage = result
            } else {
                dismiss()
            }
        }
    }
}
