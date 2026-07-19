import SwiftUI

/// Presents a short warning + consent prompt before a scanning tool runs.
/// The user can proceed once, disable all future confirmations, or cancel.
/// Consent is managed centrally by `AppSettings`.
struct SensitiveConsentModifier: ViewModifier {
    let tool: Tool
    @Binding var isPresented: Bool
    let onProceed: () -> Void
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        content.confirmationDialog("Запустить «\(tool.title)»?",
                                   isPresented: $isPresented, titleVisibility: .visible) {
            Button("Понимаю, запустить") {
                settings.grantConsent(for: tool)
                onProceed()
            }
            Button("Запускать без подтверждений") {
                settings.disableSensitivePrompts()
                onProceed()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text(tool.sensitivityNote ?? "Эта проверка активно опрашивает сеть.")
        }
    }
}

extension View {
    /// Gate a sensitive tool's run action behind a consent prompt.
    func sensitiveConsent(_ tool: Tool, isPresented: Binding<Bool>,
                          onProceed: @escaping () -> Void) -> some View {
        modifier(SensitiveConsentModifier(tool: tool, isPresented: isPresented, onProceed: onProceed))
    }
}
