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

    private var session: LanguageModelSession?

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

    private func makeSession() -> LanguageModelSession {
        let instructions = """
        Eres el asistente de Nokta Studio, un estudio de fotografía y video. \
        Respondes en español, de forma breve y directa, con montos en dólares con dos decimales. \
        Usas las herramientas disponibles para consultar o modificar datos reales del negocio: trabajos, \
        quincenas de paquetes mensuales, gastos, alertas, clientes (financieros y de galería), equipo, \
        calendario, documentos (cotizaciones/recibos), reportes, y usuarios. \
        Antes de crear o modificar algo, confirma que entendiste bien los datos si falta información \
        importante, pero si el usuario ya dio todo lo necesario, actúa directamente sin pedir confirmación \
        de más. Para acciones DESTRUCTIVAS (eliminar una galería), siempre confirma explícitamente antes \
        de ejecutar, incluso si el usuario pareció ya haberlo pedido claro. \
        Si una pregunta requiere datos que no tienes, usa la herramienta correspondiente antes de responder — \
        nunca inventes cifras. \
        Cuando el usuario diga que un cliente con paquete mensual (grupo B, como quincenas) ya pagó y pida \
        la factura, el recibo, o simplemente registrar el pago, usa SIEMPRE registrar_pago_quincena en vez de \
        gestionar_quincena — esa herramienta calcula la fecha real, detecta si el pago llegó atrasado, y genera \
        el recibo con el PDF en un solo paso. Nunca calcules tú si algo está atrasado ni inventes fechas: esa \
        herramienta ya usa la fecha real del dispositivo. \
        crear_trabajo y crear_evento suenan parecido pero NO son intercambiables: crear_trabajo registra un \
        ingreso real (cuenta en dashboard, saldo, facturación) — úsala siempre que el usuario diga 'trabajo', \
        'cobro', 'clase', 'venta' o pida registrar un pago, aunque tenga fecha/hora como un evento. crear_evento \
        es solo un recordatorio de calendario sin dinero asociado — úsala solo cuando el usuario pida agendar \
        algo explícitamente sin mencionar cobro. Si el usuario pide crear un trabajo Y marcarlo pagado en el \
        mismo mensaje, hazlo en una sola llamada a crear_trabajo usando su argumento 'pagado' — no uses \
        marcar_trabajo_pagado después, esa herramienta es solo para trabajos que ya existían de antes.
        """
        return LanguageModelSession(
            tools: [
                // Consultar
                ConsultarTrabajosTool(), ConsultarGastosTool(), ConsultarAlertasTool(), ConsultarClientesTool(),
                // Trabajos y finanzas
                CrearTrabajoTool(), MarcarTrabajoPagadoTool(), GestionarQuincenaTool(), RegistrarGastoTool(),
                RegistrarPagoQuincenaTool(onCreated: { [weak self] doc in
                    Task { @MainActor in await self?.attachPDF(for: doc) }
                }),
                // Clientes
                CrearClienteTool(), CambiarEstadoClienteTool(), ReactivarGaleriaTool(), EliminarGaleriaTool(),
                // Documentos y reportes
                CrearDocumentoTool(onCreated: { [weak self] doc in
                    Task { @MainActor in await self?.attachPDF(for: doc) }
                }),
                GenerarReporteTool(),
                // Alertas, equipo, calendario, usuarios
                MarcarAlertaLeidaTool(), GestionarEquipoTool(), CrearEventoTool(), CrearUsuarioTool(),
            ],
            instructions: instructions
        )
    }

    @MainActor
    func send() async {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }
        guard isAvailable else { errorMessage = unavailableReason(); return }

        draft = ""
        errorMessage = nil
        messages.append(ChatMessage(role: .user, text: prompt))
        isResponding = true
        defer { isResponding = false }

        if session == nil { session = makeSession() }
        guard let session else { return }

        do {
            let response = try await session.respond(to: prompt)
            messages.append(ChatMessage(role: .assistant, text: response.content))
        } catch let error as LanguageModelSession.ToolCallError {
            messages.append(ChatMessage(role: .system, text: "Error usando \(error.tool.name): \(error.underlyingError.localizedDescription)"))
        } catch {
            messages.append(ChatMessage(role: .system, text: "Error: \(error.localizedDescription)"))
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
        session = nil
        messages.removeAll()
        errorMessage = nil
    }
}
