import SwiftUI

struct ChargerView: View {
    @StateObject private var model = ChargerViewModel()
    @State private var selectedTab: MainTab = .home

    var body: some View {
        Group {
            switch selectedTab {
            case .home: DashboardTab(model: model)
            case .programming: ProgrammingView(model: model)
            case .settings: ChargerSettingsTab(model: model)
            case .connection: ConnectionsTab(model: model)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            BottomNavigationBar(selection: $selectedTab)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 8)
        }
        .task { await model.refreshAutomatically() }
    }
}

private enum MainTab: String, CaseIterable, Identifiable {
    case home, programming, settings, connection

    var id: Self { self }
    var title: String {
        switch self {
        case .home: return "Inicio"
        case .programming: return "Programación"
        case .settings: return "Ajustes"
        case .connection: return "Conexión"
        }
    }
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .programming: return "clock.fill"
        case .settings: return "gearshape.fill"
        case .connection: return "wifi"
        }
    }
}

private struct BottomNavigationBar: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 25, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 34, style: .continuous)
                                .fill(Color(uiColor: .tertiarySystemFill))
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 3)
    }
}

private struct DashboardTab: View {
    @ObservedObject var model: ChargerViewModel
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
            }
            .navigationTitle(model.activeChargerName)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ChargerLogoMark().frame(width: 34, height: 40).accessibilityLabel("Logotipo BenyControl") }
            }
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

private struct ChargerLogoMark: View {
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 9, y: 14))
                path.addCurve(to: CGPoint(x: 5, y: 31), control1: CGPoint(x: -2, y: 22), control2: CGPoint(x: 0, y: 32))
                path.addCurve(to: CGPoint(x: 29, y: 31), control1: CGPoint(x: 10, y: 42), control2: CGPoint(x: 28, y: 41))
                path.addCurve(to: CGPoint(x: 27, y: 14), control1: CGPoint(x: 36, y: 28), control2: CGPoint(x: 36, y: 20))
            }
            .stroke(Color.cyan.opacity(0.75), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.24), lineWidth: 1))
                .frame(width: 18, height: 31)
                .overlay(alignment: .center) {
                    VStack(spacing: 2) {
                        HStack(spacing: 1.5) { ForEach(0..<3) { _ in Capsule().fill(Color.cyan).frame(width: 2, height: 6) } }
                        Capsule().fill(Color.cyan.opacity(0.6)).frame(width: 2, height: 10)
                    }
                }
                .offset(y: -2)
        }
        .frame(width: 34, height: 40)
    }
}

private struct ProgrammingView: View {
    @ObservedObject var model: ChargerViewModel
    @State private var startTime = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? .now
    @State private var endTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? .now
    @State private var selectedDays = Array(repeating: true, count: 7)
    @State private var monthlyLimit = ""
    @State private var sessionLimit = ""
    @State private var optionsError: String?
    private let dayNames = ["L", "M", "X", "J", "V", "S", "D"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Temporizador de carga") {
                    DatePicker("Hora de inicio", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Hora de fin", selection: $endTime, displayedComponents: .hourAndMinute)
                    Button("Programar temporizador") {
                        model.setTimer(startHour: hour(startTime), startMinute: minute(startTime), endHour: hour(endTime), endMinute: minute(endTime))
                    }.disabled(model.isCommandRunning)
                    Button("Cancelar temporizador", role: .destructive) { model.resetTimer() }
                        .disabled(model.isCommandRunning)
                }
                Section("Horario semanal") {
                    HStack {
                        ForEach(0..<7, id: \.self) { index in
                            Button(dayNames[index]) { selectedDays[index].toggle() }
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(selectedDays[index] ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
                                .foregroundStyle(selectedDays[index] ? .white : .primary)
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"][index]): \(selectedDays[index] ? "seleccionado" : "no seleccionado")")
                        }
                    }
                    DatePicker("Desde", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Hasta", selection: $endTime, displayedComponents: .hourAndMinute)
                    Button("Guardar horario semanal") { model.setWeeklySchedule(makeSchedule()) }
                        .disabled(model.isCommandRunning || !selectedDays.contains(true))
                    Button("Leer horario del cargador") { model.requestWeeklySchedule() }
                        .disabled(model.isCommandRunning)
                    if let schedule = model.weeklySchedule {
                        Text("Configurado: \(schedule.startTime)–\(schedule.endTime)")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Límites de energía") {
                    TextField("Límite mensual (kWh, 0–65535)", text: $monthlyLimit).keyboardType(.numberPad)
                    Button("Guardar límite mensual") { saveLimit(monthly: true) }
                        .disabled(model.isCommandRunning)
                    TextField("Límite por sesión (kWh, 0–255)", text: $sessionLimit).keyboardType(.numberPad)
                    Button("Guardar límite por sesión") { saveLimit(monthly: false) }
                        .disabled(model.isCommandRunning)
                }
                if let optionsError { Section("Revisa los datos") { Text(optionsError).foregroundStyle(.red) } }
                if let error = model.errorMessage { Section("Problema") { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Programación")
            .onAppear {
                monthlyLimit = model.savedEnergyLimit(monthly: true)
                sessionLimit = model.savedEnergyLimit(monthly: false)
                if let start = model.dashboard.values?.timerStartTime { startTime = date(from: start) }
                if let end = model.dashboard.values?.timerEndTime { endTime = date(from: end) }
                model.requestWeeklySchedule()
            }
            .onChange(of: model.weeklySchedule) { schedule in
                guard let schedule else { return }
                selectedDays = schedule.weekdays
                startTime = date(from: schedule.startTime)
                endTime = date(from: schedule.endTime)
            }
        }
    }

    private func hour(_ date: Date) -> Int { Calendar.current.component(.hour, from: date) }
    private func minute(_ date: Date) -> Int { Calendar.current.component(.minute, from: date) }
    private func date(from value: String) -> Date {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return .now }
        return Calendar.current.date(from: DateComponents(hour: parts[0], minute: parts[1])) ?? .now
    }
    private func makeSchedule() -> BenyWeeklySchedule {
        func formatted(_ date: Date) -> String { String(format: "%02d:%02d", hour(date), minute(date)) }
        return BenyWeeklySchedule(weekdays: selectedDays, startTime: formatted(startTime), endTime: formatted(endTime))
    }
    private func saveLimit(monthly: Bool) {
        guard let value = Int(monthly ? monthlyLimit : sessionLimit), value >= 0,
              value <= (monthly ? 65_535 : 255) else {
            optionsError = monthly ? "Introduce un número entre 0 y 65535 kWh." : "Introduce un número entre 0 y 255 kWh."
            return
        }
        optionsError = nil
        if monthly { model.setMonthlyEnergyLimit(value) } else { model.setSessionEnergyLimit(value) }
    }
}

private struct ChargerSettingsTab: View {
    @ObservedObject var model: ChargerViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Modo de inicio") {
                    ForEach(BenyChargeStartMode.allCases) { mode in
                        Button {
                            model.setChargeStartMode(mode)
                        } label: {
                            HStack {
                                Text(mode.displayName).foregroundStyle(.primary)
                                Spacer()
                                if model.chargeStartMode == mode {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(model.isCommandRunning)
                    }
                    if let currentMode = model.chargeStartMode {
                        Text("Modo actual del cargador: \(currentMode.displayName).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Pruebas de lectura") {
                    Text("Herramientas de diagnóstico del protocolo. Las consultas no cambian la configuración del cargador.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Probar lectura directa del modo") { model.probeChargeStartModeRead() }
                        .disabled(model.isCommandRunning)
                    if let result = model.chargeStartModeReadResult {
                        LabeledContent("Respuesta", value: result)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button("Probar consulta genérica") { model.probeGenericChargeStartModeRead() }
                        .disabled(model.isCommandRunning)
                    if let result = model.genericChargeStartModeReadResult {
                        LabeledContent("Respuesta genérica", value: result)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Button("Probar varias consultas") { model.probeChargeStartModeReadCandidates() }
                        .disabled(model.isCommandRunning)
                    ForEach(Array(model.chargeStartModeProbeResults.enumerated()), id: \.offset) { _, result in
                        Text(result)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                Section("Registro técnico") {
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
                if let error = model.errorMessage {
                    Section("Problema") { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Ajustes")
        }
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

private struct ConnectionsTab: View {
    @ObservedObject var model: ChargerViewModel
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
            .navigationTitle("Conexión")
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
