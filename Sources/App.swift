import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

typealias Stored<Value> = SwiftUI.State<Value>

@main
struct FotoLimpaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        WindowGroup("Foto Limpa") { ContentView().preferredColorScheme(.dark) }
            .defaultSize(width: 1100, height: 850)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .help) {
                    Button("Como funciona o selo de IA") {
                        NSWorkspace.shared.open(URL(string: "https://about.fb.com/news/2024/04/metas-approach-to-labeling-ai-generated-content-and-manipulated-media/")!)
                    }
                }
            }
    }
}
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
struct ContentView: View {
    @Stored private var input: URL?
    @Stored private var image: NSImage?
    @Stored private var outputImage: NSImage?
    @Stored private var photoData: Data?
    @Stored private var details = "JPEG, PNG, HEIC ou TIFF · até 100 MP"
    @Stored private var format: OutputFormat = .jpeg
    @Stored private var passes = 1
    @Stored private var neutralName = true
    @Stored private var busy = false
    @Stored private var status = ""
    @Stored private var error: String?
    @Stored private var saved: URL?
    @Stored private var before: MetadataSnapshot?
    @Stored private var after: MetadataSnapshot?
    @Stored private var cleaned: CleanResult?
    @Stored private var tab = 0
    @Stored private var onlyChanges = true
    @Stored private var search = ""
    private let mint = Color(red: 0.46, green: 0.90, blue: 0.75)
    private var changes: [MetadataChange] {
        guard let a = before, let b = after else { return [] }
        return MetadataAudit.compare(a, b)
    }
    private var visibleChanges: [MetadataChange] {
        changes.filter { row in
            (!onlyChanges || row.status != "Mantido") && (search.isEmpty ||
                [row.key, row.before ?? "", row.after ?? ""].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "photo.on.rectangle.angled").font(.system(size: 30)).foregroundColor(mint)
                    .frame(width: 58, height: 58).background(mint.opacity(0.1)).cornerRadius(16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Foto Limpa").font(.system(size: 27, weight: .semibold))
                    Text("Limpe os registros. Veja o que mudou.").foregroundColor(.secondary)
                }
                Spacer()
                Label("100% no seu Mac", systemImage: "lock.shield").font(.caption).foregroundColor(mint)
                Button("Selecionar foto…", action: choose).disabled(busy)
            }
            TabView(selection: $tab) {
                photoView.padding(.top, 18).tabItem { Label("Foto e limpeza", systemImage: "photo") }.tag(0)
                comparisonView.padding(.top, 18).tabItem { Label("Antes × depois", systemImage: "tablecells") }.tag(1)
            }
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle").foregroundColor(mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Limpeza verificada de metadados; nenhuma garantia sobre o selo de IA.").font(.callout.weight(.medium))
                    Text("O app não detecta nem remove SynthID ou outras marcas nos pixels. Repetir a exportação, mudar o nome ou alterar o hash não comprova que a imagem ficou irreconhecível. Criptografia impediria a publicação como foto.")
                        .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(mint.opacity(0.065)).cornerRadius(14)
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Text(status).foregroundColor(mint).font(.caption).lineLimit(2)
                Spacer()
                if let saved = saved { Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([saved]) }.font(.caption) }
                Text("Original preservado").font(.caption).foregroundColor(.secondary)
            }.frame(height: 28)
        }.padding(26).frame(minWidth: 1000, minHeight: 800)
            .background(Color(red: 0.055, green: 0.075, blue: 0.09))
            .onChange(of: format) { _ in invalidate() }
            .onChange(of: passes) { _ in invalidate() }
            .alert("Não foi possível concluir", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
    }
    private var photoView: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(Color.white.opacity(0.035))
                    RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: image == nil ? [7] : []))
                    if let image = image { Image(nsImage: image).resizable().scaledToFit().padding(16) }
                    else {
                        VStack(spacing: 16) {
                            Image(systemName: "photo.badge.plus").font(.system(size: 48, weight: .ultraLight)).foregroundColor(mint)
                            Text("Escolha sua foto").font(.title3.weight(.medium))
                            Text("O arquivo fica no seu computador.").font(.callout).foregroundColor(.secondary)
                            Button("Abrir foto…", action: choose).buttonStyle(.borderedProminent).tint(mint).foregroundColor(.black).disabled(busy)
                        }
                    }
                    if busy { RoundedRectangle(cornerRadius: 20).fill(.black.opacity(0.65)); ProgressView().controlSize(.large) }
                }.frame(minHeight: 320, maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 4) {
                    Text(input?.lastPathComponent ?? "Nenhuma foto selecionada").font(.callout.weight(.medium)).lineLimit(1)
                    Text(details).font(.caption).foregroundColor(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Reconstruir e verificar").font(.title3.weight(.semibold))
                Text("Cria um arquivo novo e descarta EXIF, GPS, IPTC, XMP, comentários, blocos adicionais e C2PA incorporado da origem.")
                    .font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("FORMATO DA CÓPIA").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                Picker("Formato", selection: $format) {
                    ForEach(OutputFormat.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().disabled(busy)
                Picker("Passagens", selection: $passes) {
                    ForEach(1...5, id: \.self) { Text("\($0)" + ($0 == 1 ? " · recomendada" : " passagens")).tag($0) }
                }.disabled(busy)
                Text(passes > 1 ? "Cada passagem decodifica e exporta de novo. Em JPEG, a perda de qualidade pode se acumular; não há garantia extra contra o selo." : "Uma passagem já remove os registros que o app consegue limpar.")
                    .font(.caption).foregroundColor(passes > 1 ? .orange : .secondary).fixedSize(horizontal: false, vertical: true)
                Toggle("Usar nome neutro na cópia", isOn: $neutralName).font(.callout).disabled(busy)
                Text("Nome aleatório sem referência ao editor ou ao arquivo original. Não esconde marcas nos pixels.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(action: generate) {
                    Label(busy ? "Processando…" : "Limpar e comparar", systemImage: "sparkles")
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                }.buttonStyle(.borderedProminent).tint(mint).foregroundColor(.black).disabled(photoData == nil || busy)
                Button("Salvar cópia…", action: saveImage).frame(maxWidth: .infinity).disabled(cleaned == nil || busy)
                Text(format == .jpeg ? "JPEG 95%, fundo branco para transparência. Saída sRGB/8 bits/SDR." : "PNG conserva transparência, com codificação sem perdas após a conversão para sRGB/8 bits/SDR.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("HDR e cores fora de sRGB podem mudar de aparência.").font(.caption).foregroundColor(.secondary)
            }.frame(width: 310)
        }
    }
    @ViewBuilder private var comparisonView: some View {
        if let a = before, let b = after, let cleaned = cleaned {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 20) {
                    preview(image, title: "ANTES · " + bytes(a.byteCount))
                    preview(outputImage, title: "DEPOIS · " + bytes(b.byteCount))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("\(changes.filter { $0.status == "Removido" }.count) campos removidos").font(.headline).foregroundColor(mint)
                        Text("\(changes.filter { $0.status == "Alterado" }.count) alterados · \(changes.filter { $0.status == "Adicionado" }.count) adicionados")
                        Text("\(cleaned.passes) passagem(ns) concluída(s)").foregroundColor(.secondary)
                        Text(b.hasSensitiveMetadata ? "Verificação não aprovada" : "Sem metadados adicionais na leitura da saída")
                            .font(.caption).foregroundColor(mint)
                        HStack {
                            Button("Salvar cópia…", action: saveImage)
                            Button("Salvar relatório…", action: saveReport)
                        }.disabled(busy)
                    }.font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: 140)
                Text("Cobertura antes: " + a.coverage).font(.caption).foregroundColor(.secondary).lineLimit(3)
                Text("Cobertura depois: " + b.coverage).font(.caption).foregroundColor(.secondary).lineLimit(3)
                HStack {
                    Toggle("Só alterações", isOn: $onlyChanges).toggleStyle(.checkbox)
                    Spacer()
                    TextField("Buscar campo ou valor", text: $search).textFieldStyle(.roundedBorder).frame(width: 270)
                }.font(.callout)
                HStack(spacing: 12) {
                    Text("CAMPO").frame(maxWidth: .infinity, alignment: .leading)
                    Text("ANTES").frame(maxWidth: .infinity, alignment: .leading)
                    Text("DEPOIS").frame(maxWidth: .infinity, alignment: .leading)
                    Text("ESTADO").frame(width: 84, alignment: .leading)
                }.font(.caption.weight(.semibold)).foregroundColor(.secondary).padding(.horizontal, 12)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if visibleChanges.isEmpty { Text("Nenhum campo corresponde a este filtro.").foregroundColor(.secondary).padding() }
                        ForEach(visibleChanges) { row in
                            HStack(alignment: .top, spacing: 12) {
                                valueCell(row.key)
                                valueCell(row.before ?? "Não presente na leitura")
                                valueCell(row.after ?? "Não presente na leitura")
                                Text(row.status).foregroundColor(row.status == "Removido" ? mint : .secondary).frame(width: 84, alignment: .leading)
                            }.font(.system(size: 11, design: .monospaced)).padding(12)
                            Divider().opacity(0.4)
                        }
                    }
                }.background(Color.white.opacity(0.035)).cornerRadius(10)
                Text("O relatório inclui os valores originais, inclusive GPS se existir. Salve-o apenas se quiser guardar esses dados. Nenhuma marca nos pixels foi verificada.")
                    .font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "tablecells").font(.system(size: 44)).foregroundColor(mint)
                Text("Compare os dados da foto").font(.title2.weight(.medium))
                Text("Selecione uma foto e clique em Limpar e comparar. A tabela mostrará os campos encontrados antes e depois, os blocos adicionais, o tamanho e o hash de cada arquivo.")
                    .foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 530)
                Button("Limpar e comparar", action: generate).buttonStyle(.borderedProminent).tint(mint).foregroundColor(.black).disabled(photoData == nil || busy)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    private func valueCell(_ value: String) -> some View {
        Text(value).lineLimit(4).textSelection(.enabled).help(value).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func preview(_ photo: NSImage?, title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            if let photo = photo { Image(nsImage: photo).resizable().scaledToFit().frame(width: 150, height: 110).background(Color.white.opacity(0.04)).cornerRadius(8) }
        }.frame(width: 150)
    }
    private func bytes(_ count: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file) }
    private func invalidate() {
        cleaned = nil; after = nil; outputImage = nil; saved = nil
        if photoData != nil { status = "Configuração alterada. Clique em Limpar e comparar novamente." }
    }
    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.jpeg, .png, .heic, .tiff]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false; panel.prompt = "Selecionar foto"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; status = "Lendo e inspecionando a foto…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 250_000_000 else { throw CleanError.tooLarge }
                let data = try Data(contentsOf: url)
                guard let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
                      let w = props[kCGImagePropertyPixelWidth] as? Int,
                      let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0 else { throw CleanError.invalid }
                guard CGImageSourceGetCount(src) == 1 else { throw CleanError.multipleFrames }
                guard w <= 100_000_000 / h else { throw CleanError.tooLarge }
                let snapshot = try MetadataAudit.inspect(data)
                let thumb = try thumbnail(data)
                DispatchQueue.main.async {
                    invalidate(); input = url; photoData = data; image = thumb; before = snapshot; tab = 0
                    details = "\(w) × \(h) px · \(bytes(data.count)) · \(snapshot.fields.count) campos na leitura"
                    status = "Foto inspecionada. Pronta para limpar e comparar."; busy = false
                }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; status = ""; busy = false } }
        }
    }
    private func thumbnail(_ data: Data) throws -> NSImage {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1200] as CFDictionary) else { throw CleanError.invalid }
        return NSImage(cgImage: cg, size: .zero)
    }
    private func generate() {
        guard let data = photoData else { return }
        let chosenFormat = format, count = passes
        busy = true; cleaned = nil; after = nil; outputImage = nil; saved = nil
        status = "Processando \(count) passagem(ns) e verificando os registros…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try PhotoCleaner.process(data, format: chosenFormat, passes: count)
                let snapshot = try MetadataAudit.inspect(result.data)
                let thumb = try thumbnail(result.data)
                DispatchQueue.main.async {
                    cleaned = result; after = snapshot; outputImage = thumb; tab = 1; onlyChanges = true; search = ""
                    status = "\(count) passagem(ns) concluída(s). Revise antes e depois e salve a cópia."; busy = false
                }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; status = ""; busy = false } }
        }
    }
    private func saveImage() {
        guard let result = cleaned, let original = input else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.type]; panel.canCreateDirectories = true; panel.prompt = "Salvar cópia"
        panel.nameFieldStringValue = neutralName ? "foto-\(UUID().uuidString.prefix(8).lowercased()).\(format.ext)" : original.deletingPathExtension().lastPathComponent + "-limpa." + format.ext
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true; status = "Salvando e conferindo o arquivo no disco…"
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try PhotoCleaner.save(result, to: destination, original: original)
                DispatchQueue.main.async { saved = destination; status = "Cópia salva e verificada no disco · \(result.passes) passagem(ns)"; busy = false }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; status = ""; busy = false } }
        }
    }
    private func saveReport() {
        guard let a = before, let b = after, let result = cleaned, let original = input else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.canCreateDirectories = true; panel.prompt = "Salvar relatório"
        panel.nameFieldStringValue = "comparacao-foto-\(UUID().uuidString.prefix(8).lowercased()).json"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let dst = destination.resolvingSymlinksInPath().standardizedFileURL
            let protectedURLs = [original, saved].compactMap { $0 }.map { $0.resolvingSymlinksInPath().standardizedFileURL }
            guard !protectedURLs.contains(dst) else { throw CleanError.original }
            try MetadataAudit.report(before: a, after: b, passes: result.passes).write(to: destination, options: .atomic)
            status = "Relatório salvo. Ele contém os valores anteriores à limpeza."
        } catch { self.error = error.localizedDescription }
    }
}
