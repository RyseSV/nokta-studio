import SwiftUI
import FoundationModels

private struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

/// Suggestions on the empty screen — same prompts as before, now as cards.
private let sugerencias: [(icono: String, titulo: String, detalle: String, texto: String)] = [
    ("banknote", "¿Cuánto me deben este mes?", "Cobros y quincenas", "¿Cuánto me deben este mes?"),
    ("bell", "Resume mis alertas", "Lo urgente primero", "Resume las alertas sin leer"),
    ("doc.text", "Crea una cotización", "Para Juan Pérez, logo $150", "Crea una cotización para Juan Pérez: diseño de logo $150"),
    ("pause.circle", "Pausa a un cliente", "TuBoleto no responde", "Pausa a TuBoleto, dejó de responder desde julio"),
]

struct AssistantView: View {
    @Bindable var vm: AssistantViewModel
    @FocusState private var inputFocused: Bool
    @State private var previewing: PDFPreviewItem?
    @State private var aparecio = false
    @State private var nombre: String?

    private var puedeEnviar: Bool {
        !vm.draft.trimmingCharacters(in: .whitespaces).isEmpty && !vm.isResponding
    }

    var body: some View {
        VStack(spacing: 0) {
            if !vm.isAvailable { unavailableBanner }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if vm.messages.isEmpty {
                            emptyState
                        } else {
                            encabezadoChat
                        }
                        ForEach(vm.messages) { message in
                            burbuja(message)
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .offset(y: 12).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        if vm.isResponding {
                            HStack(alignment: .center, spacing: 12) {
                                IconoAsistente(tamano: 30, pensando: true)
                                PuntosPensando()
                            }
                            .id("pensando")
                            .transition(.opacity)
                        }
                    }
                    .animation(.spring(duration: 0.45, bounce: 0.12), value: vm.messages)
                    .animation(.easeOut(duration: 0.2), value: vm.isResponding)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: vm.messages) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onChange(of: vm.isResponding) { _, pensando in
                    if pensando { withAnimation { proxy.scrollTo("pensando", anchor: .bottom) } }
                }
            }

            if let error = vm.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(NoktaFont.poppins(12))
                    .foregroundStyle(NoktaTheme.error)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
                    .frame(maxWidth: 760, alignment: .leading)
            }

            barraEntrada
        }
        .background(NoktaTheme.fondo)
        .navigationTitle("Asistente")
        .sheet(item: $previewing) { item in
            PDFPreviewSheet(url: item.url, title: item.title)
        }
        .task {
            withAnimation(.spring(duration: 0.7, bounce: 0.15)) { aparecio = true }
            if nombre == nil, let me: NoktaUsuario = try? await NoktaAPI.get("/api/admin/me") {
                nombre = me.nombre?.split(separator: " ").first.map(String.init)
            }
            inputFocused = true
        }
    }

    // MARK: - Pieces

    private var unavailableBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(NoktaTheme.marca)
            Text(vm.unavailableReason())
                .font(NoktaFont.poppins(12))
                .foregroundStyle(NoktaTheme.texto)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NoktaTheme.marcaSuave)
        .overlay(alignment: .bottom) { Rectangle().fill(NoktaTheme.borde).frame(height: 1) }
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            IconoAsistente(tamano: 76, pensando: false)
                .noktaEntrada(aparecio, 0)
            VStack(spacing: 6) {
                Text(nombre.map { "¿En qué te ayudo, \($0)?" } ?? "¿En qué te ayudo?")
                    .font(NoktaFont.poppins(32, .light)).tracking(-1)
                    .foregroundStyle(NoktaTheme.texto)
                Text("Pregúntame sobre tu negocio o pídeme una acción.")
                    .font(NoktaFont.poppins(14))
                    .foregroundStyle(NoktaTheme.textoSuave)
            }
            .multilineTextAlignment(.center)
            .noktaEntrada(aparecio, 1)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(Array(sugerencias.enumerated()), id: \.offset) { i, s in
                    TarjetaSugerencia(icono: s.icono, titulo: s.titulo, detalle: s.detalle) {
                        vm.draft = s.texto
                        Task { await vm.send() }
                    }
                    .disabled(vm.isResponding || !vm.isAvailable)
                    .noktaEntrada(aparecio, 2 + i)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var encabezadoChat: some View {
        HStack(spacing: 10) {
            IconoAsistente(tamano: 26, pensando: vm.isResponding)
            Text("Asistente").font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto)
            Spacer()
            Button {
                withAnimation(.spring(duration: 0.4)) { vm.reset() }
            } label: {
                Label("Nueva conversación", systemImage: "square.and.pencil")
            }
            .buttonStyle(NoktaBotonSecundario())
            .disabled(vm.isResponding)
            .help("Empezar una conversación nueva")
        }
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func burbuja(_ message: ChatMessage) -> some View {
        let texto = (try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text)
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                Text(texto)
                    .font(NoktaFont.poppins(13))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background(
                        LinearGradient(colors: [Color(hex: 0xD8743F), Color(hex: 0xB85228)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 5, topTrailingRadius: 16, style: .continuous)
                    )
            }
        case .assistant, .system:
            HStack(alignment: .top, spacing: 12) {
                IconoAsistente(tamano: 30, pensando: false)
                VStack(alignment: .leading, spacing: 10) {
                    if !message.text.isEmpty {
                        Text(texto)
                            .font(NoktaFont.poppins(13))
                            .lineSpacing(4)
                            .foregroundStyle(message.role == .system ? NoktaTheme.error : NoktaTheme.texto)
                            .textSelection(.enabled)
                            .padding(.top, 5)
                    }
                    if let pdfURL = message.pdfURL {
                        tarjetaPDF(url: pdfURL, title: message.pdfTitle ?? "Documento")
                    }
                }
                Spacer(minLength: 40)
            }
        }
    }

    private func tarjetaPDF(url: URL, title: String) -> some View {
        let forma = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return HStack(spacing: 14) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(hex: 0xF4F1EA))
                Text("PDF").font(NoktaFont.poppins(8, .semibold)).foregroundStyle(NoktaTheme.marca).padding(.bottom, 5)
            }
            .frame(width: 34, height: 42)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                Text("Listo para ver o compartir").font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoTenue)
            }
            Spacer(minLength: 16)
            Button("Ver") { previewing = PDFPreviewItem(url: url, title: title) }
                .buttonStyle(NoktaBotonSecundario())
            ShareLink(item: url, preview: SharePreview(title, image: Image(systemName: "doc.richtext"))) {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(NoktaBotonSecundario())
        }
        .padding(14)
        .frame(maxWidth: 520, alignment: .leading)
        .background(NoktaTheme.superficie, in: forma)
        .overlay(forma.strokeBorder(NoktaTheme.marca.opacity(0.3), lineWidth: 1))
        .contentShape(forma)
        .onTapGesture { previewing = PDFPreviewItem(url: url, title: title) }
    }

    private var barraEntrada: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $vm.draft, prompt: Text("Escribe una pregunta o pide una acción…").foregroundStyle(NoktaTheme.textoTenue), axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(NoktaFont.poppins(13))
                    .foregroundStyle(NoktaTheme.texto)
                    .lineLimit(1...5)
                    .focused($inputFocused)
                    .padding(.vertical, 9)
                    // A vertical-axis TextField treats plain Return as a newline
                    // (needed for multi-line input), so `.onSubmit` never fires —
                    // intercept Return ourselves and only pass it through as a
                    // newline when Shift is held.
                    .onKeyPress(keys: [.return]) { press in
                        if press.modifiers.contains(.shift) { return .ignored }
                        Task { await vm.send() }
                        return .handled
                    }
                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(puedeEnviar ? NoktaTheme.fondo : NoktaTheme.textoTenue)
                        .frame(width: 34, height: 34)
                        .background(puedeEnviar ? NoktaTheme.texto : NoktaTheme.superficie2, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(!puedeEnviar)
                .animation(.easeOut(duration: 0.15), value: puedeEnviar)
                .help("Enviar")
            }
            .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 5)
            .background(NoktaTheme.superficie, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(inputFocused ? NoktaTheme.marca.opacity(0.55) : NoktaTheme.borde, lineWidth: 1)
            )
            .shadow(color: NoktaTheme.marca.opacity(inputFocused ? 0.12 : 0), radius: 10)
            .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
            .animation(.easeOut(duration: 0.2), value: inputFocused)

            Text("Enter para enviar · Shift + Enter para una línea nueva")
                .font(NoktaFont.poppins(10))
                .foregroundStyle(NoktaTheme.textoTenue)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 18)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Assistant identity

/// The assistant's mark: an "n" in a rounded square with the brand dot, and
/// a light (ember → cream) travelling round the border — same "borde de luz"
/// as the login. It speeds up while the assistant is thinking.
struct IconoAsistente: View {
    var tamano: CGFloat
    var pensando: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let radio = tamano * 0.28
        let forma = RoundedRectangle(cornerRadius: radio, style: .continuous)
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let vuelta = reduceMotion ? 0.15 : (t * (pensando ? 0.9 : 0.25)).truncatingRemainder(dividingBy: 1)
            ZStack {
                forma.fill(NoktaTheme.superficie2)
                forma.strokeBorder(NoktaTheme.borde, lineWidth: 1)
                forma.strokeBorder(
                    AngularGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .clear, location: 0.68),
                            .init(color: NoktaTheme.marca, location: 0.83),
                            .init(color: NoktaTheme.texto.opacity(0.7), location: 0.9),
                            .init(color: .clear, location: 0.97),
                        ],
                        center: .center,
                        angle: .degrees(vuelta * 360)
                    ),
                    lineWidth: max(1.2, tamano * 0.03)
                )
                HStack(alignment: .lastTextBaseline, spacing: tamano * 0.02) {
                    Text("n")
                        .font(NoktaFont.poppins(tamano * 0.46, .medium))
                        .foregroundStyle(NoktaTheme.texto)
                    Circle()
                        .fill(NoktaTheme.marca)
                        .frame(width: tamano * 0.1, height: tamano * 0.1)
                        .shadow(color: NoktaTheme.marca.opacity(pensando ? 0.9 : 0.4), radius: pensando ? tamano * 0.08 : tamano * 0.03)
                }
                .offset(y: -tamano * 0.03)
            }
        }
        .frame(width: tamano, height: tamano)
        .shadow(color: NoktaTheme.marca.opacity(pensando ? 0.25 : 0), radius: tamano * 0.25)
        .animation(.easeInOut(duration: 0.4), value: pensando)
        .accessibilityLabel("Asistente")
    }
}

/// Three dots bouncing while the assistant writes.
private struct PuntosPensando: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let fase = (t * 2.4 - Double(i) * 0.25).truncatingRemainder(dividingBy: 1.2)
                    let sube = fase > 0 && fase < 0.5 ? sin(fase / 0.5 * .pi) : 0
                    Circle()
                        .fill(NoktaTheme.textoSuave)
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * sube)
                        .offset(y: -4 * sube)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(NoktaTheme.superficie, in: Capsule())
            .overlay(Capsule().strokeBorder(NoktaTheme.borde, lineWidth: 1))
        }
        .accessibilityLabel("El asistente está pensando")
    }
}

private struct TarjetaSugerencia: View {
    let icono: String
    let titulo: String
    let detalle: String
    let accion: () -> Void
    @State private var encima = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 16, style: .continuous)
        Button(action: accion) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icono)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(NoktaTheme.marca)
                    .frame(width: 34, height: 34)
                    .background(NoktaTheme.marcaSuave, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto)
                        .multilineTextAlignment(.leading)
                    Text(detalle).font(NoktaFont.poppins(11)).foregroundStyle(NoktaTheme.textoSuave)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NoktaTheme.superficie, in: forma)
            .overlay(forma.strokeBorder(encima ? NoktaTheme.marca.opacity(0.55) : NoktaTheme.borde, lineWidth: 1))
            .offset(y: encima ? -2 : 0)
            .contentShape(forma)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(duration: 0.3)) { encima = h } }
    }
}
