import SwiftUI
import LocalAuthentication

/// Estado global: bloqueio por Face ID / senha e ponte com a página.
@MainActor
final class Estado: ObservableObject {
    @Published var bloqueado: Bool
    let ponte = Ponte()
    private var saiuEm: Date?
    private var autenticando = false

    /// Tempo em segundo plano a partir do qual o app pede Face ID de novo.
    private let tolerancia: TimeInterval = 20

    init() {
        bloqueado = Config.bloqueio
        ponte.liberado = !Config.bloqueio
        ponte.aoMudarBloqueio = { [weak self] ligado in
            guard let self = self else { return }
            Config.bloqueio = ligado
            if !ligado { self.bloqueado = false; self.ponte.liberar() }
        }
    }

    func mudouFase(_ nova: ScenePhase) {
        switch nova {
        case .background:
            if saiuEm == nil { saiuEm = Date() }
        case .active:
            if Config.bloqueio, let t = saiuEm, Date().timeIntervalSince(t) > tolerancia { bloqueado = true }
            saiuEm = nil
            if bloqueado { desbloquear() }
        default:
            break
        }
    }

    func desbloquear() {
        guard bloqueado, !autenticando else { return }
        let ctx = LAContext()
        var erro: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &erro) else {
            // aparelho sem senha/Face ID configurados: não há como travar
            liberar()
            return
        }
        autenticando = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Abrir o app Márcia Colmati") { [weak self] ok, _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.autenticando = false
                if ok { self.liberar() }
            }
        }
    }

    private func liberar() {
        bloqueado = false
        ponte.liberar()
    }
}
