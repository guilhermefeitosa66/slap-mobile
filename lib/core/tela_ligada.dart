import 'package:flutter/services.dart';

/// Impede a tela de apagar enquanto alguém precisa dela acesa.
///
/// Numa sala grande o intervalo entre duas leituras passa do tempo de
/// bloqueio. O aparelho apaga, a pessoa desbloqueia e reencontra o campo de
/// leitura — o que derruba o ritmo que o aplicativo existe para preservar.
///
/// Conta os pedidos: o levantamento e a câmera, aberta por cima dele, pedem
/// cada um; a tela volta ao normal só quando os dois saem. Manter ligada em
/// outras telas gastaria bateria à toa.
class TelaLigada {
  static const canal = MethodChannel('slap/tela');

  static final TelaLigada instancia = TelaLigada._();

  TelaLigada._();

  int _pedidos = 0;

  /// Há alguém mantendo a tela ligada agora.
  bool get ligada => _pedidos > 0;

  Future<void> pedir() async {
    _pedidos++;
    if (_pedidos == 1) await _definir(true);
  }

  Future<void> liberar() async {
    if (_pedidos == 0) return;
    _pedidos--;
    if (_pedidos == 0) await _definir(false);
  }

  Future<void> _definir(bool ligada) async {
    try {
      await canal.invokeMethod<void>('manterLigada', ligada);
    } on MissingPluginException {
      // Plataforma sem o canal: a tela segue o bloqueio normal.
    } on PlatformException {
      // Idem. Não é motivo para interromper o levantamento.
    }
  }
}
