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

struct NoktaTrabajo: Codable {
    var id: String
    var cliente: String
    var servicio: String
    var grupo: String?
    var estado: String
    @Flex var monto: Double?
    @Flex var anticipo: Double?
    @Flex var saldo: Double?
    @Flex var pagoMensual: Double?
    var fecha: String?
    var fechaInicio: String?
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

struct NoktaAlerta: Codable {
    var id: String
    var tipo: String
    var leida: Bool
    var fecha: String
    var datos: NoktaAlertaDatos
}
struct NoktaAlertaDatos: Codable {
    var nombre: String?
    var cliente: String?
    var mensaje: String?
    var servicio: String?
    @Flex var saldo: Double?
    var diasRestantes: Int?
}

struct NoktaCliente: Codable {
    var codigo: String
    var nombre: String
    var estado: String
    var whatsapp: String?
}

struct NoktaClienteEstado: Codable {
    var nombre: String
    var estado: String
    var notas: String?
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
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
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
