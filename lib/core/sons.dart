import 'package:audioplayers/audioplayers.dart';
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

/// Toca o retorno das leituras.
///
/// Um tocador por som, com a fonte já carregada: decidir a fonte na hora da
/// leitura introduz um atraso perceptível, e com ele o usuário perde a
/// associação entre o bipe e o item que acabou de ler.
class Sons {
  final Map<Som, AudioPlayer> _tocadores = {};
  bool _pronto = false;
  bool silencioso = false;

  /// Vibração além do som. O levantamento acontece em sala de aula, corredor
  /// e biblioteca, onde nem sempre dá para ficar com o volume alto.
  bool vibrar = true;

  Future<void> preparar() async {
    if (_pronto) return;

    for (final som in Som.values) {
      final tocador = AudioPlayer();
      try {
        await tocador.setReleaseMode(ReleaseMode.stop);
        await tocador.setPlayerMode(PlayerMode.lowLatency);
        await tocador.setSource(AssetSource(som.arquivo));
      } catch (_) {
        // Sem áudio, o levantamento continua pela indicação visual e pela
        // vibração; não é motivo para impedir o uso do aplicativo.
      }
      _tocadores[som] = tocador;
    }

    _pronto = true;
  }

  Future<void> tocar(Som som) async {
    if (!silencioso) {
      final tocador = _tocadores[som];
      if (tocador != null) {
        try {
          // `seek` antes de tocar: sem isso, uma segunda leitura durante a
          // reprodução da primeira não emite som nenhum, e o usuário pensa
          // que a leitura falhou.
          await tocador.seek(Duration.zero);
          await tocador.resume();
        } catch (_) {
          // Falha de áudio não pode interromper o levantamento.
        }
      }
    }

    if (vibrar) await _vibrar(som);
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
          await Future.delayed(const Duration(milliseconds: 120));
          await HapticFeedback.heavyImpact();
      }
    } catch (_) {
      // Aparelho sem motor de vibração.
    }
  }

  Future<void> dispose() async {
    for (final tocador in _tocadores.values) {
      await tocador.dispose();
    }
    _tocadores.clear();
    _pronto = false;
  }
}
