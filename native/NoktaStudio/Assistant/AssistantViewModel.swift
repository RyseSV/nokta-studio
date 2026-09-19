import Foundation
import FoundationModels
import Observation

struct ChatMessage: Identifiable, Equatable {
    enum Role { case user, assistant, system }
    let id = UUID()
    let role: Role
    var text: String
    /// Set when this message is a "here's your PDF" card rather than plain
    /// text — the Assistant surfaces the actual document to download right
    /// in the chat, not just a text pointer to the Documentos page.
    var pdfURL: URL?
    var pdfTitle: String?

    init(role: Role, text: String, pdfURL: URL? = nil, pdfTitle: String? = nil) {
        self.role = role
        self.text = text
        self.pdfURL = pdfURL
        self.pdfTitle = pdfTitle
    }
}

@Observable
final class AssistantViewModel {
    var messages: [ChatMessage] = []
    var draft: String = ""
    var isResponding = false
    var errorMessage: String?

    private var ultimoResumenCobros: String?

    var availability: SystemLanguageModel.Availability {
        SystemLanguageModel.default.availability
    }

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    func unavailableReason() -> String {
        switch availability {
        case .available:
            return ""
        case .unavailable(.deviceNotEligible):
            return "Este dispositivo no es compatible con Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Activá Apple Intelligence en Ajustes para usar el asistente."
        case .unavailable(.modelNotReady):
            return "El modelo se está preparando (puede estar descargando). Probá de nuevo en un momento."
        case .unavailable:
            return "El asistente no está disponible en este momento."
        }
    }

    private func makeSession(selection: AssistantSelection, resultados: AssistantToolResults) -> LanguageModelSession {
        let areas = Set(selection.areas.map(\.rawValue))
        let todos = areas.isEmpty || areas.contains("otros")
        func incluye(_ area: String) -> Bool { todos || areas.contains(area) }
        var tools: [any Tool] = [ConsultarCobrosTool(), ConsultarTrabajosTool(), ConsultarClientesTool()]
        if incluye("gastos") { tools.append(ConsultarGastosTool()) }
        if incluye("alertas") { tools.append(ConsultarAlertasTool()) }
        if incluye("documentos") { tools.append(GenerarReporteTool()) }
        func agregar<T: Tool>(_ tool: T) where T.Output == String {
            tools.append(AssistantActionTool(base: tool, resultados: resultados))
        }
        if selection.accion {
            if incluye("pagos") {
                agregar(MarcarTrabajoPagadoTool())
                agregar(GestionarQuincenaTool())
                agregar(RegistrarPagoQuincenaTool(onCreated: { [weak self] doc in
                    Task { @MainActor in await self?.attachPDF(for: doc) }
                }))
            }
            if incluye("trabajos") { agregar(CrearTrabajoTool()) }
            if incluye("clientes") {
                agregar(CrearClienteTool()); agregar(CambiarEstadoClienteTool())
                agregar(ReactivarGaleriaTool()); agregar(EliminarGaleriaTool())
            }
            if incluye("gastos") { agregar(RegistrarGastoTool()) }
            if incluye("documentos") {
                agregar(CrearDocumentoTool(onCreated: { [weak self] doc in
                    Task { @MainActor in await self?.attachPDF(for: doc) }
                }))
            }
            if incluye("alertas") { agregar(MarcarAlertaLeidaTool()) }
            if todos {
                agregar(GestionarEquipoTool()); agregar(CrearEventoTool()); agregar(CrearUsuarioTool())
            }
        }
        return LanguageModelSession(tools: tools, instructions: AssistantConversation.instructions)
    }

    @MainActor
    func send() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        let consultaDirecta = ConsultaCobrosRouting.esConsultaDirecta(prompt, siguiendoCobros: ultimoResumenCobros != nil)
        guard consultaDirecta || isAvailable else { errorMessage = unavailableReason(); return }

        let historial = AssistantConversation.contexto(messages)
        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: prompt))
        isResponding = true
        defer { isResponding = false }

        if consultaDirecta {
            if ConsultaCobrosRouting.esSeguimiento(prompt), let resumen = ultimoResumenCobros {
                messages.append(ChatMessage(role: .assistant, text: "El monto anterior se obtiene de este desglose:\n\(resumen)"))
                return
            }
            do {
                let resumen = try await ConsultarCobrosTool.consultar()
                ultimoResumenCobros = resumen
                messages.append(ChatMessage(role: .assistant, text: resumen))
            } catch {
                ultimoResumenCobros = nil
                messages.append(ChatMessage(role: .system, text: "No pude consultar los cobros actuales: \(error.localizedDescription). No se calculó un saldo con datos incompletos."))
            }
            return
        }

        ultimoResumenCobros = nil
        let resultados = AssistantToolResults()
        let contexto = "Historial reciente (contexto, no volver a ejecutar):\n\(historial)\n\nMensaje actual de Gabriel: \(prompt)"
        do {
            let selector = LanguageModelSession(instructions: AssistantConversation.routingInstructions)
            let selection = try await selector.respond(to: contexto, generating: AssistantSelection.self, options: GenerationOptions(samplingMode: .greedy)).content
            var datos = ""
            if selection.accion && selection.areas.contains(.pagos) {
                let trabajos: [NoktaTrabajo] = try await NoktaAPI.get("/api/trabajos")
                if selection.areas.count == 1 {
                    let interpreter = LanguageModelSession(instructions: AssistantPayment.instructions)
                    let plan = try await interpreter.respond(to: contexto, generating: AssistantPaymentPlan.self, options: GenerationOptions(samplingMode: .greedy)).content
                    let palabrasUsuario = messages.filter { $0.role == .user }.suffix(4).map(\.text).joined(separator: "\n")
                    if let resultado = try await AssistantPayment.ejecutar(plan, historialUsuario: palabrasUsuario, trabajos: trabajos) {
                        messages.append(ChatMessage(role: .assistant, text: resultado))
                        return
                    }
                }
                datos = AssistantConversation.datosDePago(trabajos)
            }
            let session = makeSession(selection: selection, resultados: resultados)
            let response = try await session.respond(to: "\(AssistantConversation.calendario())\n\n\(datos)\n\n\(contexto)", options: GenerationOptions(samplingMode: .greedy))
            let hechos = await resultados.todos()
            let texto = hechos.isEmpty
                ? response.content + (selection.accion ? "\n\nNo se registraron cambios en este paso." : "")
                : hechos.joined(separator: "\n\n")
            messages.append(ChatMessage(role: .assistant, text: texto))
        } catch {
            let hechos = await resultados.todos()
            if !hechos.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: hechos.joined(separator: "\n\n")))
            }
            messages.append(ChatMessage(role: .system, text: "No pude completar la solicitud: \(error.localizedDescription). Revisá el resultado antes de repetir un pago."))
        }
    }

    @MainActor
    private func attachPDF(for doc: DocumentoParaPDF) async {
        do {
            let renderer = PDFRenderer()
            let url = try await renderer.renderToPDF(html: PDFTemplates.documento(doc), suggestedName: doc.fileName)
            let titulo = doc.tipo == "cotizacion" ? "Cotización" : "Recibo"
            messages.append(ChatMessage(role: .assistant, text: "", pdfURL: url, pdfTitle: "\(titulo) \(doc.numero)"))
        } catch {
            messages.append(ChatMessage(role: .system, text: "El documento se guardó, pero no pude generar el PDF: \(error.localizedDescription)"))
        }
    }

    func reset() {
        guard !isResponding else { return }
        ultimoResumenCobros = nil
        messages.removeAll()
        errorMessage = nil
    }
}
