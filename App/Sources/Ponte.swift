import Foundation
import WebKit
import UIKit
import Security

// MARK: - Configuração guardada no aparelho

enum Config {
    private static let chaveUrl = "colmati.url"
    private static let chaveBloqueio = "colmati.bloqueio"
    private static let chaveToken = "colmati.token"

    static var url: String {
        get { UserDefaults.standard.string(forKey: chaveUrl) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: chaveUrl) }
    }

    static var bloqueio: Bool {
        get {
            if UserDefaults.standard.object(forKey: chaveBloqueio) == nil { return true }
            return UserDefaults.standard.bool(forKey: chaveBloqueio)
        }
        set { UserDefaults.standard.set(newValue, forKey: chaveBloqueio) }
    }

    /// O código de acesso fica no Keychain (nunca em arquivo nem na página).
    static var token: String {
        get { Cofre.ler(chaveToken) ?? "" }
        set { if newValue.isEmpty { Cofre.apagar(chaveToken) } else { Cofre.gravar(chaveToken, newValue) } }
    }
}

enum Cofre {
    private static func base(_ chave: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "br.com.colmati.semijoias",
            kSecAttrAccount as String: chave
        ]
    }

    static func ler(_ chave: String) -> String? {
        var q = base(chave)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var saida: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &saida) == errSecSuccess, let dados = saida as? Data else { return nil }
        return String(data: dados, encoding: .utf8)
    }

    static func gravar(_ chave: String, _ valor: String) {
        apagar(chave)
        var q = base(chave)
        q[kSecValueData as String] = Data(valor.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func apagar(_ chave: String) {
        SecItemDelete(base(chave) as CFDictionary)
    }
}

// MARK: - Chamada ao Apps Script

enum ApiClient {
    private static func erro(_ codigo: String, _ mensagem: String) -> [String: Any] {
        return ["ok": false, "erro": ["codigo": codigo, "mensagem": mensagem]]
    }

    /// Envia {t, rota, payload} ao endereço /exec e devolve o JSON do sistema ({ok, dados|erro}).
    static func chamar(url: String, token: String, rota: String, payload: Any) async -> [String: Any] {
        guard let u = URL(string: url), u.scheme == "https", u.host == "script.google.com" else {
            return erro("URL", "Endereço do sistema inválido. Ele deve começar com https://script.google.com/macros/s/ e terminar em /exec.")
        }
        if token.isEmpty { return erro("TOKEN", "Código de acesso não informado.") }

        var req = URLRequest(url: u, timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("text/plain;charset=utf-8", forHTTPHeaderField: "Content-Type")
        let corpo: [String: Any] = ["t": token, "rota": rota, "payload": payload]
        guard JSONSerialization.isValidJSONObject(corpo), let dados = try? JSONSerialization.data(withJSONObject: corpo) else {
            return erro("REQUISICAO", "Não consegui montar a requisição.")
        }
        req.httpBody = dados

        do {
            // o Apps Script responde com redirecionamento; o URLSession o segue sozinho
            let (resp, http) = try await URLSession.shared.data(for: req)
            if let obj = (try? JSONSerialization.jsonObject(with: resp)) as? [String: Any], obj["ok"] != nil {
                return obj
            }
            let status = (http as? HTTPURLResponse)?.statusCode ?? 0
            return erro("RESPOSTA", "Resposta inesperada do servidor (HTTP \(status)). Confira se a implantação do app está como “Executar como: eu” e “Quem tem acesso: qualquer pessoa”.")
        } catch let e as URLError {
            switch e.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return erro("REDE", "Sem internet no momento. Verifique o Wi-Fi ou os dados móveis e tente de novo.")
            case .timedOut:
                return erro("REDE", "O sistema demorou demais para responder. Tente de novo.")
            default:
                return erro("REDE", "Falha de comunicação: \(e.localizedDescription)")
            }
        } catch {
            return erro("REDE", "Falha de comunicação: \(error.localizedDescription)")
        }
    }
}

// MARK: - Ponte página ⇄ nativo

@MainActor
final class Ponte: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    var liberado = false
    var aoMudarBloqueio: ((Bool) -> Void)?
    private var aguardando: [Int] = []

    /// Chamado após o Face ID: libera a página para começar a animação de abertura.
    func liberar() {
        liberado = true
        let ids = aguardando
        aguardando = []
        ids.forEach { responder($0, ["ok": true]) }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let corpo = message.body as? [String: Any],
              let id = (corpo["id"] as? NSNumber)?.intValue,
              let acao = corpo["acao"] as? String else { return }

        switch acao {
        case "cfgGet":
            responder(id, ["url": Config.url, "tem": !Config.token.isEmpty, "bloqueio": Config.bloqueio])

        case "cfgSet":
            if let u = corpo["url"] as? String { Config.url = u }
            if let t = corpo["token"] as? String { Config.token = t }
            if let b = corpo["bloqueio"] as? Bool { aoMudarBloqueio?(b) }
            responder(id, ["ok": true])

        case "cfgLimpar":
            Config.token = ""
            responder(id, ["ok": true])

        case "haptico":
            let g = UINotificationFeedbackGenerator()
            g.notificationOccurred((corpo["tipo"] as? String) == "err" ? .error : .success)
            responder(id, ["ok": true])

        case "liberado":
            if liberado { responder(id, ["ok": true]) } else { aguardando.append(id) }

        case "api":
            let rota = corpo["rota"] as? String ?? ""
            let payload: Any = corpo["payload"] ?? [String: Any]()
            let url = (corpo["url"] as? String) ?? Config.url
            let token = (corpo["token"] as? String) ?? Config.token
            Task { [weak self] in
                let r = await ApiClient.chamar(url: url, token: token, rota: rota, payload: payload)
                self?.responder(id, r)
            }

        default:
            responder(id, ["ok": false])
        }
    }

    /// Devolve o resultado à página: JSON em base64 (evita qualquer problema de aspas ou acentos).
    func responder(_ id: Int, _ objeto: [String: Any]) {
        guard let dados = try? JSONSerialization.data(withJSONObject: objeto) else { return }
        let b64 = dados.base64EncodedString()
        webView?.evaluateJavaScript("window.__nativo(\(id),'\(b64)')", completionHandler: nil)
    }
}
