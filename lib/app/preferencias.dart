import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/banco.dart';
import '../data/schema.dart';
import 'providers.dart';

/// Preferências deste aparelho. Não são dado do inventário: não sincronizam.
class Preferencias {
  /// Manter a tela ligada no levantamento e na câmera.
  final bool manterTelaLigada;

  /// Som de retorno a cada leitura.
  final bool sons;

  /// Vibração de retorno a cada leitura.
  final bool vibracao;

  const Preferencias({
    this.manterTelaLigada = true,
    this.sons = true,
    this.vibracao = true,
  });

  static Preferencias doBanco(Banco banco) {
    bool ler(String chave) => banco.lerConfig(chave) != '0';
    return Preferencias(
      manterTelaLigada: ler(Config.manterTelaLigada),
      sons: ler(Config.sons),
      vibracao: ler(Config.vibracao),
    );
  }
}

class ControladorPreferencias extends Notifier<Preferencias> {
  @override
  Preferencias build() => Preferencias.doBanco(ref.watch(bancoProvider));

  void manterTelaLigada(bool valor) => _gravar(Config.manterTelaLigada, valor);

  void sons(bool valor) {
    _gravar(Config.sons, valor);
    ref.read(sonsProvider).silencioso = !valor;
  }

  void vibracao(bool valor) {
    _gravar(Config.vibracao, valor);
    ref.read(sonsProvider).vibrar = valor;
  }

  void _gravar(String chave, bool valor) {
    final banco = ref.read(bancoProvider);
    banco.gravarConfig(chave, valor ? '1' : '0');
    state = Preferencias.doBanco(banco);
  }
}

final preferenciasProvider =
    NotifierProvider<ControladorPreferencias, Preferencias>(
      ControladorPreferencias.new,
    );
