import SwiftUI
import CryptoKit

enum K {
    static let pri = Color(hex: 0x387DEB), ok = Color(hex: 0x14B875), warn = Color(hex: 0xF29E1A)
    static let bad = Color(hex: 0xE63D4D), navy = Color(hex: 0x0D1973), bg = Color(hex: 0xF2F5FA)
    static let card = Color(hex: 0xE6E8ED), sub = Color(hex: 0x6B7A9E), purple = Color(hex: 0x8C59EB)
}
extension Color {
    init(hex: UInt) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

/// Same default account as the PHP app: admin / Kurinji@123 (stored as SHA-256). Change the hash to change the password.
final class AppState: ObservableObject {
    @Published var user: String?
    private let hash = "307143b44f16b314d6a7810efeab7d9b7d76f038651923f9cd527b10a4aa188a"
    func login(_ u: String, _ p: String) -> Bool {
        let h = SHA256.hash(data: Data(p.utf8)).map { String(format: "%02x", $0) }.joined()
        if u.trimmingCharacters(in: .whitespaces) == "admin" && h == hash { user = "admin"; return true }
        return false
    }
}

@main struct KurinjiApp: App {
    @StateObject var app = AppState()
    var body: some Scene {
        WindowGroup {
            if app.user == nil { LoginView().environmentObject(app) } else { RootView().environmentObject(app) }
        }
    }
}
