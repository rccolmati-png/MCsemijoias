import SwiftUI

@main
struct ColmatiApp: App {
    @StateObject private var estado = Estado()
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(estado)
                .preferredColorScheme(.dark)
                .onChange(of: fase) { nova in
                    estado.mudouFase(nova)
                }
        }
    }
}
