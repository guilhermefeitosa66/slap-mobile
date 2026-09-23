import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../data/banco.dart';
import '../../data/repos/operacoes.dart';
import '../../data/repos/patrimonios.dart';
import 'importador.dart';
import 'leitor_planilha.dart';
import 'mapeamento.dart';

/// A importação fora da thread de interface.
///
/// Uma planilha de campus tem milhares de linhas. Ler o XLSX e gravar tudo na
/// thread de interface congelava o aplicativo por vários segundos, e o Android
/// chegava a oferecer "fechar o aplicativo". Aqui cada etapa pesada roda num
/// isolate, e a gravação usa uma segunda conexão SQLite aberta lá dentro —
/// com WAL, a interface continua lendo enquanto isso.
///
/// A transação continua única: falha no meio desfaz tudo, e o inventário
/// nunca fica com metade da planilha.

/// Quanto da gravação já foi feito.
class ProgressoImportacao {
  final int feitos;
  final int total;

  const ProgressoImportacao(this.feitos, this.total);

  double get fracao => total == 0 ? 1 : feitos / total;
}

class FalhaImportacao implements Exception {
  final String mensagem;
  FalhaImportacao(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Lê o arquivo e reconhece as colunas, num isolate.
Future<(PlanilhaLida, Mapeamento)> lerPlanilhaEmSegundoPlano({
  required String nomeArquivo,
  required Uint8List bytes,
}) {
  return Isolate.run(() {
    final planilha = LeitorPlanilha.ler(nomeArquivo: nomeArquivo, bytes: bytes);
    return (planilha, detectarMapeamento(planilha.linhas));
  });
}

/// Converte as linhas em patrimônios, sem gravar, num isolate.
Future<PreviaImportacao> prepararEmSegundoPlano(
  PlanilhaLida planilha,
  Mapeamento mapeamento,
) {
  return Isolate.run(() => Importador.preparar(planilha, mapeamento));
}

/// Grava a prévia no inventário, informando o progresso.
///
/// Com o banco em arquivo, grava num isolate por uma segunda conexão. Com o
/// banco em memória — só nos testes —, não há como compartilhar a conexão, e
/// a gravação acontece aqui mesmo, com o mesmo progresso.
Future<ResultadoImportacao> importarEmSegundoPlano({
  required Banco banco,
  required String inventarioId,
  required PreviaImportacao previa,
  Set<String> edsExcluidos = const {},
  void Function(ProgressoImportacao)? aoProgredir,
}) async {
  final caminho = banco.caminho;
  if (caminho == null) {
    return Importador.aplicar(
      repositorio: RepositorioPatrimonios(banco, RepositorioOperacoes(banco)),
      inventarioId: inventarioId,
      previa: previa,
      edsExcluidos: edsExcluidos,
      aoProgredir: aoProgredir == null
          ? null
          : (feitos, total) => aoProgredir(ProgressoImportacao(feitos, total)),
    );
  }

  final mensagens = ReceivePort();
  try {
    await Isolate.spawn(
      _gravar,
      _Pedido(
        resposta: mensagens.sendPort,
        caminho: caminho,
        inventarioId: inventarioId,
        previa: previa,
        edsExcluidos: edsExcluidos,
      ),
      // Erro não tratado ou saída sem resposta também chegam aqui: a tela
      // nunca fica esperando para sempre.
      onError: mensagens.sendPort,
      onExit: mensagens.sendPort,
    );

    await for (final mensagem in mensagens) {
      switch (mensagem) {
        case final ProgressoImportacao p:
          aoProgredir?.call(p);
        case final ResultadoImportacao r:
          return r;
        case final _Falha f:
          throw FalhaImportacao(f.mensagem);
        case [final erro, _]:
          throw FalhaImportacao('$erro');
        case null:
          throw FalhaImportacao('A importação terminou sem resposta.');
      }
    }
    throw FalhaImportacao('A importação terminou sem resposta.');
  } finally {
    mensagens.close();
  }
}

class _Pedido {
  final SendPort resposta;
  final String caminho;
  final String inventarioId;
  final PreviaImportacao previa;
  final Set<String> edsExcluidos;

  const _Pedido({
    required this.resposta,
    required this.caminho,
    required this.inventarioId,
    required this.previa,
    required this.edsExcluidos,
  });
}

class _Falha {
  final String mensagem;
  const _Falha(this.mensagem);
}

Future<void> _gravar(_Pedido pedido) async {
  final banco = await Banco.abrir(caminho: pedido.caminho);
  try {
    final resultado = Importador.aplicar(
      repositorio: RepositorioPatrimonios(banco, RepositorioOperacoes(banco)),
      inventarioId: pedido.inventarioId,
      previa: pedido.previa,
      edsExcluidos: pedido.edsExcluidos,
      aoProgredir: (feitos, total) =>
          pedido.resposta.send(ProgressoImportacao(feitos, total)),
    );
    pedido.resposta.send(resultado);
  } catch (e) {
    pedido.resposta.send(_Falha('$e'));
  } finally {
    banco.fechar();
  }
}
