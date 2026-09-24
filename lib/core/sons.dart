import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Os três resultados possíveis de uma leitura.
///
/// A diferenciação sonora é parte da operação, não enfeite: o usuário faz o
/// levantamento apontando o leitor para os patrimônios, sem olhar a tela. É
/// pelo som que ele sabe se precisa parar e conferir alguma coisa.
enum Som {
  sucesso('sons/sucesso.wav'),
  jaVerificado('sons/ja_verificado.wav'),
  naoLocalizado('sons/nao_localizado.wav');

  final String arquivo;
  const Som(this.arquivo);
}

/// O mínimo que [Sons] precisa de um tocador de áudio.
///
/// Existe pela testabilidade: o teste não tem saída de áudio, e sem esta
/// costura não havia como conferir que cada leitura pede o som certo — que é
/// exatamente o defeito que passou meses despercebido.
abstract interface class TocadorDeSom {
  /// Deixa o arquivo pronto para tocar. Lança se não conseguir.
  Future<void> carregar(String arquivo);

  /// Toca do começo, inclusive se já estiver tocando.
  Future<void> tocar();

  Future<void> dispose();
}

/// Toca o retorno das leituras.
///
/// Um tocador por som, com a fonte já carregada: decidir a fonte na hora da
/// leitura introduz um atraso perceptível, e com ele o usuário perde a
/// associação entre o bipe e o item que acabou de ler.
class Sons {
  /// Quanto uma emissão pode demorar antes de ser abandonada.
  ///
  /// Nada aqui está no caminho da interface, mas uma chamada de plataforma
  /// que não volta deixaria o tocador ocupado para sempre — e foi assim que o
  /// aplicativo ficou mudo pelo resto da execução.
  static const limite = Duration(seconds: 2);

  final TocadorDeSom Function() _criarTocador;

  final Map<Som, TocadorDeSom> _tocadores = {};
  Future<void>? _preparacao;

  bool silencioso = false;

  /// Vibração além do som. O levantamento acontece em sala de aula, corredor
  /// e biblioteca, onde nem sempre dá para ficar com o volume alto.
  bool vibrar = true;

  /// Para onde vai uma falha de áudio.
  ///
  /// O `catch (_)` que havia aqui engolia tudo, em depuração e em uso: a
  /// fonte era criada, a reprodução nunca começava e não sobrava rastro
  /// nenhum de por quê.
  void Function(Object erro, StackTrace pilha) aoFalhar = _registrarFalha;

  Sons({TocadorDeSom Function()? criarTocador})
    : _criarTocador = criarTocador ?? _TocadorAudioPlayers.new;

  /// Carrega os três sons. Chamada na inicialização, para a primeira leitura
  /// já ter retorno imediato; repetir não recarrega nada.
  Future<void> preparar() => _preparacao ??= _preparar();

  Future<void> _preparar() async {
    for (final som in Som.values) {
      final tocador = _criarTocador();
      try {
        await tocador.carregar(som.arquivo);
        // Só entra no mapa se carregou. Um tocador sem fonte aceita o pedido
        // de tocar e não faz nada — falha silenciosa, que é pior que a
        // ausência de som, porque nem aparece.
        _tocadores[som] = tocador;
      } catch (erro, pilha) {
        aoFalhar(erro, pilha);
        await _descartar(tocador);
      }
    }
  }

  /// Dá o retorno de uma leitura: som e vibração.
  ///
  /// **Não espera.** O retorno visual da leitura não pode ficar atrás de uma
  /// chamada de áudio: enquanto este método devolvia um `Future`, a tela de
  /// levantamento esperava o som terminar para mostrar o item na lista, e
  /// com o áudio quebrado o item simplesmente não aparecia.
  void tocar(Som som) {
    _ultimaEmissao = Future.wait([
      if (!silencioso) _emitir(som),
      if (vibrar) _vibrar(som),
    ]);
  }

  Future<void>? _ultimaEmissao;

  /// A emissão em andamento, para os testes esperarem o que a interface de
  /// propósito não espera.
  @visibleForTesting
  Future<void> get ultimaEmissao => _ultimaEmissao ?? Future.value();

  Future<void> _emitir(Som som) async {
    try {
      // A primeira leitura pode chegar antes de a carga terminar. Esperar
      // aqui é de graça — ninguém está esperando este método.
      await preparar();
      final tocador = _tocadores[som];
      if (tocador == null) return;
      await tocador.tocar().timeout(limite);
    } catch (erro, pilha) {
      // O levantamento continua pela vibração e pela cor, como antes; o que
      // muda é que a falha deixa rastro.
      aoFalhar(erro, pilha);
    }
  }

  /// Padrões de vibração distintos, pelo mesmo motivo dos sons: o usuário
  /// precisa distinguir os casos sem olhar.
  Future<void> _vibrar(Som som) async {
    try {
      switch (som) {
        case Som.sucesso:
          await HapticFeedback.lightImpact();
        case Som.jaVerificado:
          await HapticFeedback.mediumImpact();
        case Som.naoLocalizado:
          await HapticFeedback.heavyImpact();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await HapticFeedback.heavyImpact();
      }
    } catch (_) {
      // Aparelho sem motor de vibração.
    }
  }

  Future<void> dispose() async {
    for (final tocador in _tocadores.values) {
      await _descartar(tocador);
    }
    _tocadores.clear();
    _preparacao = null;
  }

  Future<void> _descartar(TocadorDeSom tocador) async {
    try {
      await tocador.dispose();
    } catch (_) {
      // Descarte de um tocador que já estava quebrado não interessa a
      // ninguém.
    }
  }

  /// Em depuração o erro aparece no console; em uso fica registrado sem
  /// interromper o levantamento.
  static void _registrarFalha(Object erro, StackTrace pilha) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: erro,
        stack: pilha,
        library: 'slap · som',
        context: ErrorDescription('ao dar o retorno sonoro de uma leitura'),
        silent: !kDebugMode,
      ),
    );
  }
}

/// O tocador de verdade, sobre o `audioplayers`.
class _TocadorAudioPlayers implements TocadorDeSom {
  final AudioPlayer _player = AudioPlayer();

  @override
  Future<void> carregar(String arquivo) async {
    await _player.setReleaseMode(ReleaseMode.stop);
    // No Android, `lowLatency` toca por SoundPool: é o que mantém o bipe
    // colado na leitura.
    await _player.setPlayerMode(PlayerMode.lowLatency);
    await _player.setSource(AssetSource(arquivo));
  }

  /// `stop` antes de `resume`, e não `seek(Duration.zero)`.
  ///
  /// O SoundPool não reposiciona: `seekTo(0)` chama `stop()` e só retoma se
  /// já estivesse tocando. Pior, o `play()` do plugin ignora o pedido quando
  /// acha que já está tocando — e ele marca isso como verdadeiro mesmo na vez
  /// em que não conseguiu tocar, antes de a fonte ficar pronta. Uma falha no
  /// começo deixava o tocador mudo pelo resto da execução. `stop` desfaz essa
  /// marca, então cada leitura começa do zero.
  @override
  Future<void> tocar() async {
    await _player.stop();
    await _player.resume();
  }

  @override
  Future<void> dispose() => _player.dispose();
}
