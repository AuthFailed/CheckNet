import SwiftUI
import UniformTypeIdentifiers

/// Exporting a result as a picture, next to the existing text export.
///
/// A ping summary pasted into a chat as text loses its shape; a screenshot of a
/// diagnostic is what people actually send to support or to an ISP. `ImageRenderer`
/// re-renders the SwiftUI view off-screen, so the export is the card itself at
/// 2× — not a capture of whatever happens to be on screen, and not clipped by
/// the window.
@MainActor
enum ResultExport {
    /// Renders a view to PNG data.
    static func png<V: View>(_ view: V, scale: CGFloat = 2) -> Data? {
        let renderer = ImageRenderer(content:
            view
                .padding(16)
                .background(Palette.groupedBackground)
                .frame(width: ToolLayout.contentWidth)
        )
        renderer.scale = scale
        #if os(macOS)
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return renderer.uiImage?.pngData()
        #endif
    }

    /// Writes the PNG to a temporary file so it can be shared or saved.
    static func pngFile<V: View>(_ view: V, name: String) throws -> URL {
        guard let data = png(view) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}

/// A PNG of a result, produced only when the share sheet asks for it.
struct ResultImage<Content: View>: Transferable {
    let name: String
    /// Marked `@MainActor` at the call boundary instead of on the property, so
    /// the memberwise initializer stays nonisolated and the type can be built
    /// from a view body.
    let content: @MainActor @Sendable () -> Content

    init(name: String, content: @escaping @MainActor @Sendable () -> Content) {
        self.name = name
        self.content = content
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            await MainActor.run {
                ResultExport.png(item.content()) ?? Data()
            }
        }
        .suggestedFileName { $0.name + ".png" }
    }
}

/// Share control offering the result both ways: as a picture and as text.
///
/// Both live in one menu rather than two buttons, because they are the same
/// action — "send this result to someone" — differing only in form.
struct ResultShareMenu<Content: View>: View {
    /// What the picture should contain. Usually the result card, without the
    /// input field and the run button.
    let snapshot: @MainActor @Sendable () -> Content
    /// The same result as plain text, for places a picture is wrong.
    let text: String
    var name: String = "checknet-result"

    @State private var isRendering = false
    @State private var failure: String?

    var body: some View {
        Menu {
            ShareLink(
                item: ResultImage(name: name, content: snapshot),
                preview: SharePreview("Результат проверки")
            ) {
                Label("Поделиться картинкой", systemImage: "photo")
            }
            ShareLink(item: text) {
                Label("Поделиться текстом", systemImage: "text.alignleft")
            }
            #if os(macOS)
            Divider()
            Button {
                saveImage()
            } label: {
                Label("Сохранить картинку…", systemImage: "square.and.arrow.down")
            }
            #endif
        } label: {
            Label("Поделиться", systemImage: "square.and.arrow.up")
        }
        .alert("Не удалось сохранить картинку", isPresented: .constant(failure != nil)) {
            Button("Ок") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    #if os(macOS)
    /// On the Mac a share sheet is the wrong default for "give me the file" —
    /// people expect a save panel.
    private func saveImage() {
        guard let data = ResultExport.png(snapshot()) else {
            failure = "Не удалось построить изображение."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = name + ".png"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            failure = error.localizedDescription
        }
    }
    #endif
}
