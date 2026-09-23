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
    registrarCanalDeArquivos()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Tira arquivos do backup do iCloud (canal `slap/arquivos`).
  ///
  /// O banco carrega a identidade do aparelho: restaurado num iPhone novo
  /// enquanto o antigo continua em uso, os dois escreveriam com a mesma
  /// identidade. A cópia de segurança do próprio aplicativo existe para isso.
  private func registrarCanalDeArquivos() {
    guard let registrar = self.registrar(forPlugin: "SlapArquivos") else { return }
    let canal = FlutterMethodChannel(
      name: "slap/arquivos",
      binaryMessenger: registrar.messenger()
    )
    canal.setMethodCallHandler { chamada, resultado in
      switch chamada.method {
      case "excluirDoBackup":
        guard let caminho = chamada.arguments as? String else {
          resultado(false)
          return
        }
        var url = URL(fileURLWithPath: caminho)
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        do {
          try url.setResourceValues(valores)
          resultado(true)
        } catch {
          resultado(false)
        }
      default:
        resultado(FlutterMethodNotImplemented)
      }
    }
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
