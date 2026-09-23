import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Sigilo do corpo da sincronização.
///
/// A assinatura HMAC já garante que só quem tem a chave do inventário lê e
/// escreve, e que uma requisição capturada não é alterada nem repetida. Mas o
/// corpo ia em claro: quem estivesse autenticado na mesma rede e capturando
/// pacotes lia descrição, sala e responsável dos patrimônios. Aqui o corpo de
/// cada requisição e de cada resposta autenticada vai cifrado com AES-256-GCM.
///
/// - **Chaves derivadas.** A `chave_sync` do QR code não é usada direto: o
///   HKDF-SHA256 deriva dela uma chave para a cifra e outra para a assinatura,
///   de modo que nenhuma das duas funções vaza nada sobre a outra.
/// - **Nonce novo a cada mensagem**, 96 bits de `Random.secure()`. Com a mesma
///   chave, a chance de repetir fica desprezível muito além de 2^32 mensagens
///   — um inventário troca alguns milhares.
/// - **Contexto autenticado.** O GCM autentica também método, caminho e
///   sentido (pedido ou resposta): um corpo cifrado não serve em outra rota,
///   nem uma resposta pode ser devolvida como pedido.
/// - **Compressão antes da cifra.** O JSON de um inventário encolhe umas dez
///   vezes com gzip; depois de cifrado, não encolheria mais nada.
///
/// Formato na rede: base64url(nonce ‖ texto cifrado ‖ etiqueta).
class CifraSync {
  static const _tamanhoNonce = 12;
  static const _tamanhoEtiqueta = 128;

  final Uint8List _chaveCifra;

  /// Chave da assinatura HMAC, derivada da mesma `chave_sync`.
  final Uint8List chaveAssinatura;

  CifraSync._(this._chaveCifra, this.chaveAssinatura);

  factory CifraSync(String chaveSync) {
    final material = base64Url.decode(chaveSync);
    return CifraSync._(
      hkdfSha256(material, info: utf8.encode('slap/sync/cifra')),
      hkdfSha256(material, info: utf8.encode(infoAssinatura)),
    );
  }

  /// Rótulo HKDF da chave de assinatura.
  static const infoAssinatura = 'slap/sync/assinatura';

  static final _aleatorio = Random.secure();

  String cifrar(Map<String, dynamic> conteudo, {required String contexto}) {
    final claro = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode(conteudo))),
    );
    final nonce = Uint8List.fromList(
      List.generate(_tamanhoNonce, (_) => _aleatorio.nextInt(256)),
    );
    final cifrado = _gcm(true, nonce, contexto).process(claro);

    final envelope = Uint8List(nonce.length + cifrado.length)
      ..setAll(0, nonce)
      ..setAll(nonce.length, cifrado);
    return base64Url.encode(envelope);
  }

  /// Decifra e confere a autenticidade. Lança [CorpoIlegivel] se o texto foi
  /// alterado, se a chave é outra ou se o contexto não é o esperado.
  Map<String, dynamic> decifrar(String texto, {required String contexto}) {
    try {
      final envelope = base64Url.decode(texto.trim());
      if (envelope.length <= _tamanhoNonce) throw const FormatException();
      final nonce = Uint8List.sublistView(envelope, 0, _tamanhoNonce);
      final cifrado = Uint8List.sublistView(envelope, _tamanhoNonce);
      final claro = _gcm(false, nonce, contexto).process(cifrado);
      return jsonDecode(utf8.decode(gzip.decode(claro)))
          as Map<String, dynamic>;
    } on InvalidCipherTextException {
      throw CorpoIlegivel();
    } on FormatException {
      throw CorpoIlegivel();
    } on ArgumentError {
      throw CorpoIlegivel();
    }
  }

  GCMBlockCipher _gcm(bool cifrando, Uint8List nonce, String contexto) {
    return GCMBlockCipher(AESEngine())..init(
      cifrando,
      AEADParameters(
        KeyParameter(_chaveCifra),
        _tamanhoEtiqueta,
        nonce,
        Uint8List.fromList(utf8.encode(contexto)),
      ),
    );
  }

  /// Contexto de um pedido: o corpo só vale naquela rota.
  static String contextoPedido(String metodo, String caminho) =>
      'pedido $metodo $caminho';

  /// Contexto da resposta a um pedido.
  static String contextoResposta(String metodo, String caminho) =>
      'resposta $metodo $caminho';
}

/// O corpo não pôde ser decifrado: foi alterado, ou a chave é outra.
class CorpoIlegivel implements Exception {
  @override
  String toString() => 'Corpo da sincronização ilegível.';
}

/// HKDF-SHA256 (RFC 5869), com um bloco de saída — 32 bytes.
Uint8List hkdfSha256(
  List<int> material, {
  required List<int> info,
  List<int> sal = const [],
}) {
  // Extração: sem sal, a RFC manda usar zeros do tamanho do hash.
  final chaveExtracao = sal.isEmpty ? List<int>.filled(32, 0) : sal;
  final prk = Hmac(sha256, chaveExtracao).convert(material).bytes;
  // Expansão: T(1) = HMAC(PRK, info ‖ 0x01).
  final t1 = Hmac(sha256, prk).convert([...info, 1]).bytes;
  return Uint8List.fromList(t1);
}
