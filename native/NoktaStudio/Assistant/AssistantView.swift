import SwiftUI
import FoundationModels

private enum Palette {
    static let bg = Color(red: 0x1C/255.0, green: 0x1C/255.0, blue: 0x1A/255.0)
    static let card = Color(red: 0x2E/255.0, green: 0x2E/255.0, blue: 0x2B/255.0)
    static let ember = Color(red: 0xB8/255.0, green: 0x52/255.0, blue: 0x28/255.0)
    static let cream = Color(red: 0xF0/255.0, green: 0xEC/255.0, blue: 0xE4/255.0)
    static let muted = Color(red: 0x7A/255.0, green: 0x7A/255.0, blue: 0x72/255.0)
}

private struct PDFPreviewItem: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
}

struct AssistantView: View {
    @Bindable var vm: AssistantViewModel
    @FocusState private var inputFocused: Bool
    @State private var previewing: PDFPreviewItem?

    var body: some View {
        VStack(spacing: 0) {
            if !vm.isAvailable {
                unavailableBanner
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if vm.messages.isEmpty {
                            emptyState
                        }
                        ForEach(vm.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if vm.isResponding {
                            HStack(spacing: 8) {
                                ProgressView().tint(Palette.ember).controlSize(.small)
                                Text("Pensando…").font(.footnote).foregroundStyle(Palette.muted)
                            }
                            .padding(.leading, 4)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: vm.messages) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }

            inputBar
        }
        .background(Palette.bg)
        .navigationTitle("Asistente")
        .toolbar {
            ToolbarItem {
                Button {
                    vm.reset()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.glass)
                .help("Nueva conversación")
                .disabled(vm.isResponding)
            }
        }
        .sheet(item: $previewing) { item in
            PDFPreviewSheet(url: item.url, title: item.title)
        }
    }

    private var unavailableBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(Palette.ember)
            Text(vm.unavailableReason())
                .font(.footnote)
                .foregroundStyle(Palette.cream)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Palette.card), in: Rectangle())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preguntame sobre tu negocio")
                .font(.headline)
                .foregroundStyle(Palette.cream)
            GlassEffectContainer(spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach([
                        "¿Cuánto me deben este mes?",
                        "Resume las alertas sin leer",
                        "Crea una cotización para Juan Pérez: diseño de logo $150",
                        "Pausa a TuBoleto, dejó de responder desde julio",
                    ], id: \.self) { suggestion in
                        Button {
                            vm.draft = suggestion
                            Task { await vm.send() }
                        } label: {
                            Text(suggestion)
                                .font(.footnote)
                                .foregroundStyle(Palette.muted)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
    }

    private func bubble(_ message: ChatMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            if let pdfURL = message.pdfURL {
                pdfCard(url: pdfURL, title: message.pdfTitle ?? "Documento")
            } else {
                Text((try? AttributedString(markdown: message.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(message.text))
                    .font(.callout)
                    .foregroundStyle(message.role == .system ? .red : Palette.cream)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .glassEffect(
                        .regular.tint(message.role == .user ? Palette.ember.opacity(0.85) : Palette.card),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private func pdfCard(url: URL, title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext.fill")
                .font(.system(size: 26))
                .foregroundStyle(Palette.ember)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.medium)).foregroundStyle(Palette.cream)
                Text("Toca para previsualizar").font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            ShareLink(item: url, preview: SharePreview(title, image: Image(systemName: "doc.richtext.fill"))) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Palette.ember)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { previewing = PDFPreviewItem(url: url, title: title) }
        .padding(12)
        .glassEffect(.regular.tint(Palette.card), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.ember.opacity(0.4), lineWidth: 1))
    }

    private var inputBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Preguntá algo o pedí una acción…", text: $vm.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .glassEffect(.regular.tint(Palette.card), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(Palette.cream)
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
                        .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(.glass(.regular.tint(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? Palette.muted.opacity(0.3) : Palette.ember)))
                .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isResponding)
            }
        }
        .padding(12)
        .background(Palette.bg)
    }
}
