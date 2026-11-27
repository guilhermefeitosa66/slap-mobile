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
    registrarCanalDeRecebidos()
    if let url = launchOptions?[.url] as? URL, url.isFileURL {
      arquivoPendente = copiarRecebido(url)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Arquivo de inventário aberto de fora ("Abrir com SLAP" no WhatsApp, no
  /// Mail, no Arquivos). Copiado para a pasta temporária e entregue ao Dart:
  /// pelo método `pendente` quando abriu o aplicativo, pelo `recebido` quando
  /// o aplicativo já estava aberto.
  private var arquivoPendente: String?
  private var canalRecebidos: FlutterMethodChannel?

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    guard url.isFileURL else {
      return super.application(app, open: url, options: options)
    }
    guard let caminho = copiarRecebido(url) else { return false }
    if let canal = canalRecebidos {
      canal.invokeMethod("recebido", arguments: caminho)
    } else {
      arquivoPendente = caminho
    }
    return true
  }

  private func registrarCanalDeRecebidos() {
    guard let registrar = self.registrar(forPlugin: "SlapRecebidos") else { return }
    let canal = FlutterMethodChannel(
      name: "slap/recebidos",
      binaryMessenger: registrar.messenger()
    )
    canal.setMethodCallHandler { [weak self] chamada, resultado in
      switch chamada.method {
      case "pendente":
        resultado(self?.arquivoPendente)
        self?.arquivoPendente = nil
      default:
        resultado(FlutterMethodNotImplemented)
      }
    }
    canalRecebidos = canal
  }

  /// Copia o arquivo para a pasta temporária e apaga o original da caixa de
  /// entrada do aplicativo, para onde o iOS o copiou.
  private func copiarRecebido(_ url: URL) -> String? {
    let acesso = url.startAccessingSecurityScopedResource()
    defer { if acesso { url.stopAccessingSecurityScopedResource() } }
    let destino = FileManager.default.temporaryDirectory
      .appendingPathComponent("recebido-\(UUID().uuidString).db")
    do {
      try FileManager.default.copyItem(at: url, to: destino)
      if url.path.contains("/Inbox/") {
        try? FileManager.default.removeItem(at: url)
      }
      return destino.path
    } catch {
      return nil
    }
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
