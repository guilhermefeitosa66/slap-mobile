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

/// Acordo de chave efêmero, para entregar a `chave_sync` a quem ainda não a
/// tem.
///
/// O canal cifrado da sincronização deriva da própria `chave_sync`: ele não
/// serve para *entregar* a chave, porque quem está entrando ainda não tem com
/// que decifrar nada. O pedido de entrada resolve isso com um acordo
/// Diffie-Hellman de curva elíptica feito na hora: cada lado gera um par de
/// chaves que existe só para aquele pedido, troca a parte pública em claro, e
/// os dois chegam ao mesmo segredo sem que ele jamais trafegue.
///
/// **A curva é a P-256 (`prime256v1`), e não a X25519** da especificação
/// original: o `pointycastle` 4.0, já usado aqui para o AES-GCM, não oferece
/// X25519, e acrescentar uma segunda biblioteca de criptografia só por causa
/// dela seria pior — duas implementações para auditar no lugar de uma.
///
/// Do segredo combinado sai, por HKDF, uma [CifraSync] comum: a chave viaja
/// no mesmo envelope AES-256-GCM do resto do protocolo, com o rótulo do
/// pedido autenticado junto. Como os dois pares são descartados depois, quem
/// tiver gravado a rede não decifra o pedido nem mais tarde.
///
/// **O que isto não resolve:** um atacante que consiga se pôr no meio da
/// conversa na mesma rede local pode trocar as duas chaves públicas e ler a
/// entrega. O que o impede é o aceite: quem compartilha vê o nome e o
/// aparelho de quem pede, e recusa o que não reconhece.
class AcordoEfemero {
  /// P-256 (NIST) — a curva de `ECDHBasicAgreement` disponível no
  /// `pointycastle`.
  static final ECDomainParameters curva = ECDomainParameters('prime256v1');

  final ECPrivateKey _privada;
  final ECPublicKey _publica;

  AcordoEfemero._(this._privada, this._publica);

  /// Um par de chaves novo, válido para um único pedido de entrada.
  factory AcordoEfemero.gerar() {
    final semente = Uint8List.fromList(
      List.generate(32, (_) => _aleatorio.nextInt(256)),
    );
    final sorteio = FortunaRandom()..seed(KeyParameter(semente));
    final gerador = ECKeyGenerator()
      ..init(ParametersWithRandom(ECKeyGeneratorParameters(curva), sorteio));
    final par = gerador.generateKeyPair();
    return AcordoEfemero._(
      par.privateKey as ECPrivateKey,
      par.publicKey as ECPublicKey,
    );
  }

  static final _aleatorio = Random.secure();

  /// A parte pública, em base64url. É o que vai em claro no pedido e na
  /// resposta — sozinha não abre nada.
  String get publica => base64Url.encode(_publica.Q!.getEncoded(false));

  /// Combina com a pública do outro lado e devolve o canal cifrado do pedido.
  ///
  /// O [rotulo] entra na derivação e amarra a chave àquele pedido: inventário,
  /// token e as duas públicas, na mesma ordem dos dois lados. Trocar qualquer
  /// um deles produz uma chave diferente, e o GCM recusa a mensagem.
  ///
  /// Lança [CorpoIlegivel] quando a pública recebida não é um ponto válido
  /// desta curva — o que também barra a tentativa de arrancar o segredo
  /// mandando um ponto de outra curva.
  CifraSync combinar(String publicaRemota, {required String rotulo}) {
    final ponto = _pontoDe(publicaRemota);
    final acordo = ECDHBasicAgreement()..init(_privada);
    final segredo = acordo.calculateAgreement(ECPublicKey(ponto, curva));
    final material = hkdfSha256(
      _paraBytes(segredo, (curva.curve.fieldSize + 7) ~/ 8),
      info: utf8.encode(rotulo),
    );
    return CifraSync(base64Url.encode(material));
  }

  static ECPoint _pontoDe(String publica) {
    try {
      final ponto = curva.curve.decodePoint(base64Url.decode(publica));
      if (ponto == null || ponto.isInfinity || !_naCurva(ponto)) {
        throw CorpoIlegivel();
      }
      return ponto;
    } on FormatException {
      throw CorpoIlegivel();
    } on ArgumentError {
      throw CorpoIlegivel();
    }
  }

  /// Confere `y² = x³ + ax + b`. O `decodePoint` monta o ponto sem verificar,
  /// e um ponto fora da curva é o começo do ataque de curva inválida.
  static bool _naCurva(ECPoint p) {
    final x = p.x;
    final y = p.y;
    final a = curva.curve.a;
    final b = curva.curve.b;
    if (x == null || y == null || a == null || b == null) return false;
    final esquerda = (y * y).toBigInteger();
    final direita = (x * x * x + a * x + b).toBigInteger();
    return esquerda == direita;
  }

  /// Coordenada do segredo em bytes, com o tamanho fixo do campo.
  ///
  /// Sem o preenchimento à esquerda, um segredo que por acaso começasse com
  /// zero produziria material de tamanho diferente nos dois lados, e a chave
  /// derivada não bateria — uma falha em uma entrada a cada 256.
  static Uint8List _paraBytes(BigInt valor, int tamanho) {
    final bytes = Uint8List(tamanho);
    var resto = valor;
    for (var i = tamanho - 1; i >= 0; i--) {
      bytes[i] = (resto & BigInt.from(0xff)).toInt();
      resto = resto >> 8;
    }
    return bytes;
  }
}
