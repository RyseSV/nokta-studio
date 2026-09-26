import SwiftUI

let ESTADO_CLIENTE_LABEL: [String: String] = ["activo": "Activo", "pausado": "Pausado", "cancelado": "Cancelado"]
let ESTADO_CLIENTE_COLOR: (String) -> Color = { estado in
    switch estado {
    case "activo": return NoktaPalette.green
    case "pausado": return NoktaPalette.yellow
    default: return NoktaPalette.red
    }
}

struct ClienteRow: Identifiable {
    let nombre: String
    let trabajos: [NoktaTrabajo]
    let cobrado: Double
    let porCobrar: Double
    let estado: String
    var id: String { nombre }
}

@Observable
final class ClientesViewModel {
    var trabajos: [NoktaTrabajo] = []
    var clientes: [NoktaCliente] = []
    var clienteEstados: [NoktaClienteEstado] = []
    var filtroEstado = "todos"
    var isLoading = true

    func load() async {
        isLoading = true
        defer { isLoading = false }
        async let t: [NoktaTrabajo]? = try? NoktaAPI.get("/api/trabajos")
        async let c: [NoktaCliente]? = try? NoktaAPI.get("/api/clientes")
        async let e: [NoktaClienteEstado]? = try? NoktaAPI.get("/api/clientes-estados")
        let (tt, cc, ee) = await (t, c, e)
        trabajos = tt ?? []
        clientes = cc ?? []
        clienteEstados = ee ?? []
    }

    func estadoDe(_ nombre: String) -> String {
        clienteEstados.first { $0.nombre == nombre }?.estado ?? "activo"
    }

    /// Todos los clientes (sin filtro), con las mismas cuentas que Trabajos.
    var todos: [ClienteRow] {
        var nombres: [String] = []
        var seen = Set<String>()
        for n in (clientes.map(\.nombre) + trabajos.map(\.cliente)) where !n.isEmpty && !seen.contains(n) {
            seen.insert(n); nombres.append(n)
        }
        return nombres.map { nombre in
            let ts = trabajos.filter { $0.cliente == nombre }
            return ClienteRow(nombre: nombre, trabajos: ts,
                              cobrado: ts.reduce(0) { $0 + IngresosCalculator.cobrado($1) },
                              porCobrar: ts.reduce(0) { $0 + IngresosCalculator.porCobrar($1, estados: clienteEstados) },
                              estado: estadoDe(nombre))
        }
    }

    var rows: [ClienteRow] {
        let r = todos
        return filtroEstado == "todos" ? r : r.filter { $0.estado == filtroEstado }
    }
}

/// Monograma de Nokta: iniciales en naranja sobre un círculo naranja suave.
struct MonogramaCliente: View {
    let nombre: String
    var tamano: CGFloat = 36
    var body: some View {
        Text(NoktaFormato.iniciales(nombre))
            .font(NoktaFont.poppins(tamano * 0.32, .medium))
            .foregroundStyle(NoktaTheme.marca)
            .frame(width: tamano, height: tamano)
            .background(NoktaTheme.marcaSuave, in: Circle())
    }
}

/// Pastilla de estado (punto + texto sobre fondo del mismo color).
struct PastillaEstado: View {
    let estado: String
    var tamano: CGFloat = 10.5
    var body: some View {
        let c = ESTADO_CLIENTE_COLOR(estado)
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 5, height: 5)
            Text(ESTADO_CLIENTE_LABEL[estado] ?? estado.capitalized)
        }
        .font(NoktaFont.poppins(tamano, .medium))
        .foregroundStyle(c)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(c.opacity(0.12), in: Capsule())
        .fixedSize()
    }
}

/// Mac/iPad: lista de tarjetas a la izquierda y la ficha a la derecha.
/// iPhone: la lista y, al tocar, la ficha a pantalla completa.
struct ClientesContainerView: View {
    @State private var vm = ClientesViewModel()
    @State private var seleccionado: String?
    @State private var ancho: CGFloat = 1000

    var body: some View {
        Group {
            if ancho >= 760 {
                HStack(alignment: .top, spacing: 0) {
                    ListaClientes(vm: vm, seleccionado: $seleccionado)
                        .frame(width: ancho >= 1100 ? 340 : 300)
                    Group {
                        if let n = seleccionado {
                            ClienteDetailView(nombre: n, alCambiar: { Task { await vm.load() } })
                                .id(n)
                                .transition(.opacity.combined(with: .offset(x: 12)))
                        } else {
                            NoktaVacio(icono: "person.crop.circle", titulo: "Elige un cliente", detalle: "Verás lo cobrado, lo que sigue y sus trabajos.")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .animation(.spring(duration: 0.4, bounce: 0.1), value: seleccionado)
            } else if let n = seleccionado {
                ClienteDetailView(nombre: n, onBack: { seleccionado = nil }, alCambiar: { Task { await vm.load() } })
            } else {
                ListaClientes(vm: vm, seleccionado: $seleccionado)
            }
        }
        .background(NoktaTheme.fondo)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { ancho = $0 }
        .task {
            await vm.load()
            if seleccionado == nil, ancho >= 760 { seleccionado = ListaClientes.ordenar(vm.rows).first?.nombre }
        }
    }
}

private let clienteTabs: [(valor: String, texto: String)] = [("todos", "Todos"), ("activo", "Activos"), ("pausado", "Pausados"), ("cancelado", "Cancelados")]

/// Lista de tarjetas: el cliente elegido se marca con una línea de luz naranja.
private struct ListaClientes: View {
    @Bindable var vm: ClientesViewModel
    @Binding var seleccionado: String?
    @State private var busqueda = ""
    @State private var aparecio = false

    /// Primero los que te deben, luego activos, y al final por lo cobrado.
    static func ordenar(_ r: [ClienteRow]) -> [ClienteRow] {
        let peso = ["activo": 0, "pausado": 1, "cancelado": 2]
        return r.sorted {
            if ($0.porCobrar > 0) != ($1.porCobrar > 0) { return $0.porCobrar > 0 }
            if $0.estado != $1.estado { return (peso[$0.estado] ?? 3) < (peso[$1.estado] ?? 3) }
            return $0.cobrado > $1.cobrado
        }
    }

    private var filas: [ClienteRow] {
        let q = busqueda.trimmingCharacters(in: .whitespaces)
        let opts: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return Self.ordenar(vm.rows.filter { q.isEmpty || $0.nombre.range(of: q, options: opts) != nil })
    }

    private var subtitulo: String {
        let t = vm.todos
        let n = t.count == 1 ? "1 cliente" : "\(t.count) clientes"
        let debe = t.reduce(0) { $0 + $1.porCobrar }
        return debe > 0 ? "\(n) · te deben \(NoktaFormato.dinero(debe))" : n
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NoktaEncabezado(titulo: "Clientes", subtitulo: vm.isLoading && vm.todos.isEmpty ? nil : subtitulo)
                .noktaEntrada(aparecio, 0)
            NoktaBuscador(texto: $busqueda, placeholder: "Buscar cliente…")
                .noktaEntrada(aparecio, 1)
            NoktaChips(opciones: clienteTabs, seleccion: $vm.filtroEstado)
                .noktaEntrada(aparecio, 2)

            ScrollView {
                LazyVStack(spacing: 8) {
                    if vm.isLoading && vm.todos.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in NoktaFilaCargando().padding(.horizontal, 12) }
                    } else if filas.isEmpty {
                        Text(busqueda.isEmpty ? "Sin clientes en este filtro" : "Nadie con ese nombre")
                            .font(NoktaFont.poppins(12)).foregroundStyle(NoktaTheme.textoTenue)
                            .frame(maxWidth: .infinity).padding(.vertical, 30)
                    }
                    ForEach(Array(filas.enumerated()), id: \.element.id) { i, r in
                        TarjetaCliente(fila: r, seleccionado: seleccionado == r.nombre) {
                            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { seleccionado = r.nombre }
                        }
                        .noktaEntrada(aparecio, 3 + i)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 18).padding(.top, 28)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.1)) { aparecio = true } }
    }
}

private struct TarjetaCliente: View {
    let fila: ClienteRow
    let seleccionado: Bool
    let accion: () -> Void
    @State private var hover = false

    var body: some View {
        let forma = RoundedRectangle(cornerRadius: 14, style: .continuous)
        Button(action: accion) {
            HStack(spacing: 11) {
                MonogramaCliente(nombre: fila.nombre, tamano: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(fila.nombre).font(NoktaFont.poppins(13, .medium)).foregroundStyle(NoktaTheme.texto).lineLimit(1)
                    PastillaEstado(estado: fila.estado, tamano: 9.5)
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(NoktaFormato.dinero(fila.cobrado))
                        .font(NoktaFont.poppins(14, .light)).tracking(-0.4).foregroundStyle(NoktaTheme.texto)
                        .contentTransition(.numericText(value: fila.cobrado))
                    if fila.porCobrar > 0 {
                        Text("debe " + NoktaFormato.dinero(fila.porCobrar))
                            .font(NoktaFont.poppins(10)).foregroundStyle(NoktaTheme.aviso)
                    }
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 12)
            .background {
                ZStack {
                    forma.fill(NoktaTheme.superficie)
                    forma.fill(LinearGradient(colors: [NoktaTheme.marca.opacity(0.1), .clear], startPoint: .leading, endPoint: .trailing))
                        .opacity(seleccionado ? 1 : hover ? 0.4 : 0)
                }
            }
            .overlay(forma.strokeBorder(seleccionado ? NoktaTheme.marca.opacity(0.45) : NoktaTheme.borde, lineWidth: 1))
            // Línea de luz: crece desde el centro cuando eliges al cliente.
            .overlay(alignment: .leading) {
                Capsule().fill(NoktaTheme.marca)
                    .frame(width: 3, height: 26)
                    .shadow(color: NoktaTheme.marca.opacity(0.9), radius: 6)
                    .shadow(color: NoktaTheme.marca.opacity(0.5), radius: 12)
                    .scaleEffect(y: seleccionado ? 1 : 0.01)
                    .opacity(seleccionado ? 1 : 0)
                    .offset(x: -1)
            }
            .contentShape(forma)
            .scaleEffect(hover && !seleccionado ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.2)) { hover = h } }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: seleccionado)
    }
}
