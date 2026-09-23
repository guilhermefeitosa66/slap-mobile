import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sons.dart';
import '../data/banco.dart';
import '../data/repos/conflitos.dart';
import '../data/repos/inventarios.dart';
import '../data/repos/operacoes.dart';
import '../data/repos/patrimonios.dart';
import '../data/schema.dart';
import '../domain/divergencia.dart';
import '../features/sync/cliente.dart';
import '../features/sync/servidor.dart';

/// Ligação entre as telas e a camada de dados.
///
/// O banco é aberto antes da primeira tela aparecer, e sobrescrito aqui na
/// inicialização — nenhuma tela lida com o carregamento dele.
final bancoProvider = Provider<Banco>((ref) {
  throw UnimplementedError('Banco definido na inicialização do aplicativo.');
});

final operacoesProvider = Provider<RepositorioOperacoes>(
  (ref) => RepositorioOperacoes(ref.watch(bancoProvider)),
);

final patrimoniosProvider = Provider<RepositorioPatrimonios>(
  (ref) => RepositorioPatrimonios(
    ref.watch(bancoProvider),
    ref.watch(operacoesProvider),
  ),
);

final inventariosProvider = Provider<RepositorioInventarios>(
  (ref) => RepositorioInventarios(
    ref.watch(bancoProvider),
    ref.watch(operacoesProvider),
  ),
);

final conflitosProvider = Provider<RepositorioConflitos>(
  (ref) => RepositorioConflitos(
    ref.watch(bancoProvider),
    ref.watch(operacoesProvider),
  ),
);

final sonsProvider = Provider<Sons>((ref) {
  final sons = Sons();
  ref.onDispose(sons.dispose);
  return sons;
});

final clienteSyncProvider = Provider<ClienteSync>(
  (ref) => ClienteSync(ref.watch(operacoesProvider)),
);

final servidorSyncProvider = Provider<ServidorSync>((ref) {
  final servidor = ServidorSync(
    banco: ref.watch(bancoProvider),
    ops: ref.watch(operacoesProvider),
    inventarios: ref.watch(inventariosProvider),
    patrimonios: ref.watch(patrimoniosProvider),
  );
  ref.onDispose(servidor.dispose);
  return servidor;
});

// ------------------------------------------------------------- identidade ---

/// Identidade local do usuário: nome e matrícula, sem senha.
///
/// É o que atribui cada verificação a uma pessoa nos relatórios. A consistência
/// do sistema distribuído vem do identificador do aparelho, não daqui — trocar
/// o nome não afeta a convergência dos dados.
class Identidade {
  final String? nome;
  final String? matricula;

  const Identidade({this.nome, this.matricula});

  bool get configurada => nome != null && nome!.trim().isNotEmpty;
}

class ControladorIdentidade extends Notifier<Identidade> {
  @override
  Identidade build() {
    final banco = ref.watch(bancoProvider);
    return Identidade(
      nome: banco.lerConfig(Config.usuarioNome),
      matricula: banco.lerConfig(Config.usuarioMatricula),
    );
  }

  void definir({required String nome, String? matricula}) {
    final banco = ref.read(bancoProvider);

    banco.gravarConfig(Config.usuarioNome, nome.trim());
    if (matricula == null || matricula.trim().isEmpty) {
      banco.apagarConfig(Config.usuarioMatricula);
    } else {
      banco.gravarConfig(Config.usuarioMatricula, matricula.trim());
    }

    state = Identidade(nome: nome.trim(), matricula: matricula?.trim());
  }
}

final identidadeProvider = NotifierProvider<ControladorIdentidade, Identidade>(
  ControladorIdentidade.new,
);

// ------------------------------------------------------------- inventários ---

/// Contador incrementado a cada gravação, para as telas recarregarem.
///
/// O banco é síncrono e as consultas são baratas, então recarregar a lista
/// inteira é mais simples e mais confiável que manter um cache incremental,
/// ainda mais com operações chegando pela rede a qualquer momento.
class Revisao extends Notifier<int> {
  @override
  int build() => 0;

  void mudou() => state = state + 1;
}

final revisaoProvider = NotifierProvider<Revisao, int>(Revisao.new);

final listaInventariosProvider = Provider((ref) {
  ref.watch(revisaoProvider);
  return ref.watch(inventariosProvider).listar();
});

final inventarioProvider = Provider.family((ref, String id) {
  ref.watch(revisaoProvider);
  return ref.watch(inventariosProvider).porId(id);
});

final progressoProvider = Provider.family<ProgressoInventario, String>((
  ref,
  id,
) {
  ref.watch(revisaoProvider);
  return ref.watch(patrimoniosProvider).progresso(id);
});

final conflitosPendentesProvider = Provider.family<int, String>((ref, id) {
  ref.watch(revisaoProvider);
  return ref.watch(conflitosProvider).contarPendentes(id);
});
