import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/sons.dart';

/// O retorno sonoro das leituras.
///
/// Nenhum teste olhava para isto, e por meses nenhuma leitura emitiu som:
/// a vibração continuava funcionando e a falha passou despercebida. Os
/// testes abaixo são sobre o que o levantamento em campo depende — três sons
/// distintos, e o mesmo som de novo na leitura seguinte.
void main() {
  /// Tocador de mentira: registra o que foi pedido, sem saída de áudio.
  late _TocadorFalso ultimo;
  late List<_TocadorFalso> criados;

  Sons montar({bool falharAoCarregar = false}) {
    criados = [];
    final sons = Sons(
      criarTocador: () {
        ultimo = _TocadorFalso(falharAoCarregar: falharAoCarregar);
        criados.add(ultimo);
        return ultimo;
      },
    )..vibrar = false;
    addTearDown(sons.dispose);
    return sons;
  }

  /// Toca e espera o que a interface, de propósito, não espera.
  Future<void> tocar(Sons sons, Som som) async {
    sons.tocar(som);
    await sons.ultimaEmissao;
  }

  List<String> tocados() => [
    for (final t in criados)
      for (var i = 0; i < t.tocadas; i++) t.arquivo!,
  ];

  test('cada resultado toca o seu som', () async {
    final sons = montar();
    await sons.preparar();

    await tocar(sons, Som.sucesso);
    await tocar(sons, Som.jaVerificado);
    await tocar(sons, Som.naoLocalizado);

    expect(tocados(), [
      Som.sucesso.arquivo,
      Som.jaVerificado.arquivo,
      Som.naoLocalizado.arquivo,
    ]);
  });

  test('a segunda leitura do mesmo tipo toca de novo', () async {
    // É o defeito em si: uma falha no começo deixava o tocador marcado como
    // ocupado, e daí em diante toda leitura era silenciosa.
    final sons = montar();

    await tocar(sons, Som.sucesso);
    await tocar(sons, Som.sucesso);
    await tocar(sons, Som.sucesso);

    expect(tocados(), List.filled(3, Som.sucesso.arquivo));
  });

  test('tocar antes de preparar carrega e toca assim mesmo', () async {
    // A primeira leitura pode chegar antes de a carga terminar; era aí que o
    // som se perdia para sempre.
    final sons = montar();

    await tocar(sons, Som.sucesso);

    expect(tocados(), [Som.sucesso.arquivo]);
  });

  test('sem som, nada é tocado e a leitura segue', () async {
    final sons = montar()..silencioso = true;
    await sons.preparar();

    await tocar(sons, Som.sucesso);

    expect(tocados(), isEmpty);
  });

  test('falha ao carregar é registrada, não engolida', () async {
    final sons = montar(falharAoCarregar: true);
    final falhas = <Object>[];
    sons.aoFalhar = (erro, _) => falhas.add(erro);

    await sons.preparar();
    await tocar(sons, Som.sucesso);

    expect(falhas, hasLength(Som.values.length));
    expect(tocados(), isEmpty, reason: 'tocador sem fonte não entra no mapa');
  });

  test('tocador que não responde não prende a emissão', () async {
    final sons = montar();
    await sons.preparar();
    final falhas = <Object>[];
    sons.aoFalhar = (erro, _) => falhas.add(erro);
    ultimo.travar = true;

    // Sem o tempo limite, esta espera não terminaria.
    await tocar(
      sons,
      Som.naoLocalizado,
    ).timeout(Sons.limite + const Duration(seconds: 2));

    expect(falhas.single, isA<TimeoutException>());
  });
}

class _TocadorFalso implements TocadorDeSom {
  final bool falharAoCarregar;

  String? arquivo;
  int tocadas = 0;

  /// Chamada de plataforma que nunca volta, como a do defeito original.
  bool travar = false;

  _TocadorFalso({this.falharAoCarregar = false});

  @override
  Future<void> carregar(String arquivo) async {
    if (falharAoCarregar) throw StateError('sem saída de áudio');
    this.arquivo = arquivo;
  }

  @override
  Future<void> tocar() {
    if (travar) return Completer<void>().future;
    tocadas++;
    return Future.value();
  }

  @override
  Future<void> dispose() async {}
}
