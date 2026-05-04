import SwiftUI

/// Avoids shadowing `SwiftUI.Alert` and keeps alert presentation in one place.
struct SimVirtualLocationAlertModifier: ViewModifier {
    let isPresented: Binding<Bool>
    let text: String

    func body(content: Content) -> some View {
        if #available(macOS 12.0, *) {
            content
                .alert(text, isPresented: isPresented) {
                    Text("OK")
                }
        } else {
            content.alert(isPresented: isPresented) {
                SwiftUI.Alert(
                    title: Text(text)
                )
            }
        }
    }
}
