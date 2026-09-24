import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Mantém o banco fora do backup do sistema.
///
/// O banco carrega a identidade do aparelho. Se o backup do sistema o
/// restaurasse num celular novo enquanto o antigo continua em uso, os dois
/// escreveriam com a mesma identidade. No Android isso é resolvido no
/// manifesto; no iOS, marcando os arquivos. A cópia de segurança do próprio
/// aplicativo cobre a perda do aparelho sem esse risco.
Future<void> manterForaDoBackup(String caminhoDoBanco) async {
  if (defaultTargetPlatform != TargetPlatform.iOS) return;

  const canal = MethodChannel('slap/arquivos');
  for (final sufixo in ['', '-wal', '-shm']) {
    final arquivo = '$caminhoDoBanco$sufixo';
    if (!File(arquivo).existsSync()) continue;
    try {
      await canal.invokeMethod<bool>('excluirDoBackup', arquivo);
    } on PlatformException {
      // Sem a marcação o aplicativo funciona igual; só o backup do sistema
      // passa a incluir o banco.
    } on MissingPluginException {
      return;
    }
  }
}
