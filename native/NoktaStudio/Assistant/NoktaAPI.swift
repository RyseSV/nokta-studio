import Foundation

/// Nokta's Mongo schemas are `strict:false`, so numeric fields sometimes
/// arrive as JSON numbers and sometimes as numeric strings depending on
/// which route last wrote the record. Decode leniently either way, and
/// tolerate the key being entirely absent (group-specific fields like
/// `cantPiezas` only exist on some Trabajo docs).
@propertyWrapper
struct Flex: Codable {
    var wrappedValue: Double?
    init(wrappedValue: Double?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { wrappedValue = d }
        else if let s = try? c.decode(String.self) { wrappedValue = Double(s) }
        else { wrappedValue = nil }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = wrappedValue { try c.encode(v) } else { try c.encodeNil() }
    }
}
extension KeyedDecodingContainer {
    func decode(_ type: Flex.Type, forKey key: Key) throws -> Flex {
        try decodeIfPresent(Flex.self, forKey: key) ?? Flex(wrappedValue: nil)
    }
}

/// Same leniency as `Flex`, but for Int fields (e.g. Quincena.q) that can
/// arrive as either a JSON number or a numeric string.
@propertyWrapper
struct FlexInt: Codable {
    var wrappedValue: Int
    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { wrappedValue = i }
        else if let d = try? c.decode(Double.self) { wrappedValue = Int(d) }
        else if let s = try? c.decode(String.self), let i = Int(s) { wrappedValue = i }
        else { wrappedValue = 0 }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(wrappedValue)
    }
}

/// Tolerant string decoding for fields the server never parses at all
/// (`cantPiezas`, `diaCobro`) — always written as a string from the web
/// form, but decode a stray JSON number too rather than crash the whole
/// `[NoktaTrabajo]` fetch over one odd document.
@propertyWrapper
struct FlexString: Codable {
    var wrappedValue: String?
    init(wrappedValue: String?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { wrappedValue = s }
        else if let d = try? c.decode(Double.self) { wrappedValue = d == d.rounded() ? String(Int(d)) : String(d) }
        else { wrappedValue = nil }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let v = wrappedValue { try c.encode(v) } else { try c.encodeNil() }
    }
}
extension KeyedDecodingContainer {
    func decode(_ type: FlexString.Type, forKey key: Key) throws -> FlexString {
        try decodeIfPresent(FlexString.self, forKey: key) ?? FlexString(wrappedValue: nil)
    }
}

struct NoktaTrabajo: Codable {
    var id: String
    var cliente: String
    var clienteId: String?
    var servicio: String
    var grupo: String?
    var grupoNombre: String?
    var estado: String
    @Flex var monto: Double?
    @Flex var anticipo: Double?
    @Flex var saldo: Double?
    @Flex var pagoMensual: Double?
    var fecha: String?
    var horaInicio: String?
    var horaFin: String?
    var lugar: String?
    var empresa: String?
    @FlexString var cantPiezas: String?
    var formato: String?
    var fechaEntrega: String?
    var alcance: String?
    var fechaInicio: String?
    @FlexString var diaCobro: String?
    var estadoContrato: String?
    var notas: String?
    var creado: String?
    var quincenas: [NoktaQuincena]?
    var sesiones: [NoktaSesion]?

    var grupoResuelto: String { grupo ?? ServicioGrupoMap.grupo(for: servicio) }
}

/// Pago recurrente suelto (ej. clase semanal) — mismo formato que produce/lee
/// el panel "Sesiones" en admin.html vía PATCH /api/trabajos/:id/sesiones.
struct NoktaSesion: Codable {
    var id: String
    var fecha: String
    @Flex var monto: Double?
    var estado: String
    var fechaPago: String?
}

struct NoktaQuincena: Codable {
    var periodo: String
    @FlexInt var q: Int
    @Flex var monto: Double?
    var estado: String
    var fechaPago: String?
}

struct NoktaGasto: Codable {
    var id: String
    var concepto: String
    var categoria: String
    @Flex var monto: Double?
    var fecha: String
}

struct NoktaServicioLinea: Codable {
    var descripcion: String
    @Flex var monto: Double?
}

/// Cotización o recibo guardado desde Documentos — mismo shape para ambas
/// colecciones (Cotizacion/Recibo) del server.
struct NoktaDocumento: Codable {
    var id: String
    var numero: String
    var clienteNombre: String
    var empresa: String?
    var telefono: String?
    var email: String?
    var fechaEmision: String?
    var fechaValidez: String?
    var servicios: [NoktaServicioLinea]?
    @Flex var total: Double?
    var notas: String?
}

struct NoktaAlerta: Codable {
    var id: String
    var tipo: String
    var leida: Bool
    var fecha: String
    var datos: NoktaAlertaDatos
}
struct NoktaAlertaDatos: Codable {
    var id: String?
    var codigo: String?
    var nombre: String?
    var cliente: String?
    var mensaje: String?
    var servicio: String?
    var tipo: String?
    var fecha: String?
    var hora: String?
    @Flex var saldo: Double?
    var diasRestantes: Int?
}

/// Evento suelto en el calendario (no ligado a un trabajo) — ver
/// admin.html's modal-evento / POST /api/eventos.
struct NoktaEvento: Codable, Identifiable {
    var id: String
    var titulo: String?
    var tipo: String?
    var fecha: String
    var horaInicio: String?
    var horaFin: String?
    var lugar: String?
    @Flex var monto: Double?
    @Flex var anticipo: Double?
    @Flex var saldo: Double?
}

struct NoktaCliente: Codable {
    var codigo: String
    var nombre: String
    var estado: String
    var tipo: String?
    var whatsapp: String?
    var email: String?
    var empresa: String?
    var creado: String?
    var expira: String?
    var visitas: [NoktaClienteVisita]?
    var descargas: [NoktaClienteDescarga]?
    var reactivaciones: [NoktaReactivacion]?
}
/// Solo se usa para contar entradas — la forma exacta de cada visita no importa aquí.
struct NoktaClienteVisita: Codable {}
struct NoktaClienteDescarga: Codable {
    var fecha: String
    var tipo: String?
}
struct NoktaReactivacion: Codable {
    var fecha: String
    @FlexInt var dias: Int
}

struct NoktaClienteEstado: Codable {
    var nombre: String
    var estado: String
    var notas: String?
}

extension String {
    /// Percent-encodes everything except RFC 3986 unreserved characters —
    /// matches JS's `encodeURIComponent`, so a "/" (or "?", "&", etc.) in a
    /// client name can't be misread as an extra path segment or query string
    /// when building a REST path like `/api/clientes-estados/<nombre>`.
    var urlPathComponentEncoded: String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return addingPercentEncoding(withAllowedCharacters: unreserved) ?? self
    }
}

enum NoktaAPIError: Error, LocalizedError {
    case http(Int, String)
    case invalidURL
    var errorDescription: String? {
        switch self {
        case .http(let code, let msg): return "Error \(code): \(msg)"
        case .invalidURL: return "URL inválida"
        }
    }
}

/// Talks to the exact same REST API the web panel uses. No separate backend,
/// no separate data model — whatever the Assistant does here is immediately
/// visible on nokta-studio.onrender.com/admin too.
enum NoktaAPI {
    static let baseURL = URL(string: "https://nokta-studio.onrender.com")!

    private static var session: URLSession {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        return URLSession(configuration: config)
    }

    static func get<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "GET", body: Data?.none)
    }

    static func post<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await request(path, method: "POST", body: try JSONEncoder().encode(AnyEncodable(body)))
    }

    static func put<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await request(path, method: "PUT", body: try JSONEncoder().encode(AnyEncodable(body)))
    }

    static func patch<T: Decodable>(_ path: String, body: Encodable) async throws -> T {
        try await request(path, method: "PATCH", body: try JSONEncoder().encode(AnyEncodable(body)))
    }

    static func delete<T: Decodable>(_ path: String) async throws -> T {
        try await request(path, method: "DELETE", body: Data?.none)
    }

    private static func request<T: Decodable>(_ path: String, method: String, body: Data?) async throws -> T {
        await CookieSync.syncFromWebView()
        // Callers encode individual path components; preserve those escapes.
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw NoktaAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw NoktaAPIError.invalidURL }
        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "—"
            throw NoktaAPIError.http(http.statusCode, msg)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct AnyEncodable: Encodable {
    let wrapped: Encodable
    init(_ wrapped: Encodable) { self.wrapped = wrapped }
    func encode(to encoder: Encoder) throws { try wrapped.encode(to: encoder) }
}

struct OKResponse: Decodable { let ok: Bool? }
