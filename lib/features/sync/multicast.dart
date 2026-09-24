import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Trava de multicast do Wi-Fi.
///
/// No Android, o Wi-Fi descarta pacotes multicast para economizar bateria, a
/// menos que algum aplicativo segure um `MulticastLock`. Sem ele, o beacon
/// UDP da descoberta envia, mas nunca recebe — e o defeito é silencioso,
/// porque o mDNS ainda acha alguns aparelhos e a descoberta parece funcionar.
///
/// Segurar a trava custa bateria, então ela só existe enquanto a descoberta
/// está ligada, e é liberada sempre que ela para, inclusive quando falha.
abstract class TravaMulticast {
  /// Adquire a trava. Devolve `null` quando conseguiu, ou o motivo da falha.
  Future<String?> adquirir();

  Future<void> liberar();

  /// A do sistema: canal de plataforma no Android, nada nos demais.
  factory TravaMulticast.doSistema() =>
      defaultTargetPlatform == TargetPlatform.android
      ? TravaMulticastAndroid()
      : const _SemTrava();
}

/// Fala com o `MainActivity` pelo canal `slap/rede`.
class TravaMulticastAndroid implements TravaMulticast {
  static const canal = MethodChannel('slap/rede');

  @override
  Future<String?> adquirir() async {
    try {
      await canal.invokeMethod<bool>('adquirirMulticast');
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    } on MissingPluginException {
      return 'canal de plataforma ausente';
    }
  }

  @override
  Future<void> liberar() async {
    try {
      await canal.invokeMethod<void>('liberarMulticast');
    } on PlatformException catch (e) {
      // Liberar é melhor-esforço, mas uma falha aqui significa trava presa
      // consumindo bateria: fica registrada.
      developer.log(
        'Falha ao liberar o MulticastLock: ${e.message}',
        name: 'slap.descoberta',
        level: 900,
      );
    } on MissingPluginException {
      // Sem canal não houve trava.
    }
  }
}

/// Plataformas em que o multicast não depende de trava.
class _SemTrava implements TravaMulticast {
  const _SemTrava();

  @override
  Future<String?> adquirir() async => null;

  @override
  Future<void> liberar() async {}
}
