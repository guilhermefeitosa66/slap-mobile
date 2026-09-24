import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/banco.dart';
import '../data/schema.dart';
import 'providers.dart';

/// Tema escolhido pela pessoa. `sistema` acompanha o modo claro ou escuro do
/// aparelho, e é o padrão.
enum Tema {
  sistema('Sistema', ThemeMode.system),
  claro('Claro', ThemeMode.light),
  escuro('Escuro', ThemeMode.dark);

  /// Como aparece no seletor dos ajustes.
  final String rotulo;

  /// O que o `MaterialApp` recebe.
  final ThemeMode modo;

  const Tema(this.rotulo, this.modo);

  /// O tema gravado com este nome; ausente ou desconhecido vale [sistema].
  static Tema doNome(String? nome) {
    for (final tema in values) {
      if (tema.name == nome) return tema;
    }
    return sistema;
  }
}

/// Preferências deste aparelho. Não são dado do inventário: não sincronizam.
class Preferencias {
  /// Chave do tema na tabela `config`, gravada com o nome do [Tema]. Fica
  /// aqui, e não em [Config], porque só as preferências a leem.
  static const chaveTema = 'pref_tema';

  /// Manter a tela ligada no levantamento e na câmera.
  final bool manterTelaLigada;

  /// Som de retorno a cada leitura.
  final bool sons;

  /// Vibração de retorno a cada leitura.
  final bool vibracao;

  /// Tema claro, escuro ou o do sistema.
  final Tema tema;

  const Preferencias({
    this.manterTelaLigada = true,
    this.sons = true,
    this.vibracao = true,
    this.tema = Tema.sistema,
  });

  static Preferencias doBanco(Banco banco) {
    bool ler(String chave) => banco.lerConfig(chave) != '0';
    return Preferencias(
      manterTelaLigada: ler(Config.manterTelaLigada),
      sons: ler(Config.sons),
      vibracao: ler(Config.vibracao),
      tema: Tema.doNome(banco.lerConfig(chaveTema)),
    );
  }
}

class ControladorPreferencias extends Notifier<Preferencias> {
  @override
  Preferencias build() => Preferencias.doBanco(ref.watch(bancoProvider));

  void manterTelaLigada(bool valor) =>
      _gravarBool(Config.manterTelaLigada, valor);

  void sons(bool valor) {
    _gravarBool(Config.sons, valor);
    ref.read(sonsProvider).silencioso = !valor;
  }

  void vibracao(bool valor) {
    _gravarBool(Config.vibracao, valor);
    ref.read(sonsProvider).vibrar = valor;
  }

  void tema(Tema valor) => _gravar(Preferencias.chaveTema, valor.name);

  void _gravarBool(String chave, bool valor) =>
      _gravar(chave, valor ? '1' : '0');

  void _gravar(String chave, String valor) {
    final banco = ref.read(bancoProvider);
    banco.gravarConfig(chave, valor);
    state = Preferencias.doBanco(banco);
  }
}

final preferenciasProvider =
    NotifierProvider<ControladorPreferencias, Preferencias>(
      ControladorPreferencias.new,
    );
