import SwiftUI

struct ContentView: View {
    @EnvironmentObject var estado: Estado
    @Environment(\.scenePhase) private var fase

    var body: some View {
        ZStack {
            Color(red: 0.114, green: 0.094, blue: 0.086).ignoresSafeArea()
            WebContainer(ponte: estado.ponte)
                .ignoresSafeArea()
            // protege os dados no seletor de apps e enquanto está bloqueado
            if estado.bloqueado || fase != .active {
                TelaBloqueio(mostrarBotao: estado.bloqueado) { estado.desbloquear() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: estado.bloqueado)
        .onAppear { estado.desbloquear() }
    }
}

struct TelaBloqueio: View {
    var mostrarBotao: Bool
    var acao: () -> Void

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color(red: 0.227, green: 0.184, blue: 0.169), Color(red: 0.114, green: 0.094, blue: 0.086)],
                center: .center, startRadius: 10, endRadius: 650
            ).ignoresSafeArea()
            VStack(spacing: 34) {
                Image("LogoDourada")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)
                    .shadow(color: Color(red: 0.90, green: 0.78, blue: 0.54).opacity(0.35), radius: 22)
                if mostrarBotao {
                    Button(action: acao) {
                        Label("Desbloquear", systemImage: "faceid")
                            .font(.system(size: 17, weight: .medium))
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(Color(red: 0.79, green: 0.64, blue: 0.36))
                            .foregroundColor(Color(red: 0.145, green: 0.129, blue: 0.122))
                            .clipShape(Capsule())
                    }
                }
            }
        }
    }
}
