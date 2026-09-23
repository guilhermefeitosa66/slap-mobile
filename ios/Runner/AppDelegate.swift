import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registrarCanalDaTela()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Mantém a tela ligada durante o levantamento (canal `slap/tela`).
  ///
  /// Numa sala grande o intervalo entre duas leituras passa do tempo de
  /// bloqueio; o Dart liga ao entrar no levantamento e desliga ao sair.
  private func registrarCanalDaTela() {
    guard let registrar = self.registrar(forPlugin: "SlapTela") else { return }
    let canal = FlutterMethodChannel(
      name: "slap/tela",
      binaryMessenger: registrar.messenger()
    )
    canal.setMethodCallHandler { chamada, resultado in
      switch chamada.method {
      case "manterLigada":
        UIApplication.shared.isIdleTimerDisabled = (chamada.arguments as? Bool) ?? false
        resultado(nil)
      default:
        resultado(FlutterMethodNotImplemented)
      }
    }
  }
}
