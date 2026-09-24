import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../core/andamento.dart';
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

class FalhaImportacao implements Exception {
  final String mensagem;
  FalhaImportacao(this.mensagem);

  @override
  String toString() => mensagem;
}

/// Lê o arquivo e reconhece as colunas, num isolate.
///
/// Com a planilha do campus — dez mil linhas —, esta é a espera mais longa
/// das três, e era a única sem número nenhum na tela.
Future<(PlanilhaLida, Mapeamento)> lerPlanilhaEmSegundoPlano({
  required String nomeArquivo,
  required Uint8List bytes,
  void Function(Andamento)? aoProgredir,
  String? etapa,
}) async {
  final passo = etapa ?? 'Lendo $nomeArquivo…';
  final canal = _CanalAndamento(aoProgredir);
  final porta = canal.porta;
  try {
    return await Isolate.run(() {
      final planilha = LeitorPlanilha.ler(
        nomeArquivo: nomeArquivo,
        bytes: bytes,
        aoProgredir: porta == null
            ? null
            : (feitas, total) => porta.send(
                Andamento(
                  passo,
                  feitos: feitas,
                  total: total,
                  unidade: 'linhas lidas',
                ),
              ),
      );
      return (planilha, detectarMapeamento(planilha.linhas));
    });
  } finally {
    await canal.fechar();
  }
}

/// Converte as linhas em patrimônios, sem gravar, num isolate.
Future<PreviaImportacao> prepararEmSegundoPlano(
  PlanilhaLida planilha,
  Mapeamento mapeamento, {
  void Function(Andamento)? aoProgredir,
  String etapa = 'Conferindo as linhas…',
}) async {
  final canal = _CanalAndamento(aoProgredir);
  final porta = canal.porta;
  try {
    return await Isolate.run(
      () => Importador.preparar(
        planilha,
        mapeamento,
        aoProgredir: porta == null
            ? null
            : (feitas, total) => porta.send(
                Andamento(
                  etapa,
                  feitos: feitas,
                  total: total,
                  unidade: 'linhas conferidas',
                ),
              ),
      ),
    );
  } finally {
    await canal.fechar();
  }
}

/// Canal de volta para o andamento de quem roda num isolate.
///
/// `Isolate.run` não tem por onde avisar nada, mas uma [SendPort] é enviável
/// e o isolate escreve nela — é o mesmo canal que a gravação usa, com uma
/// linha a mais. O trabalho continua dentro de `Isolate.run` de propósito: é
/// ele que devolve a exceção original ([PlanilhaInvalida], por exemplo) do
/// outro lado.
///
/// **O que vai para o isolate é só a porta**, nunca um fecho desta função:
/// fecho que captura variável de tipo não é enviável, e a importação falharia
/// com um erro obscuro sobre argumento ilegal em mensagem de isolate.
class _CanalAndamento {
  final ReceivePort? _avisos;
  final StreamSubscription<dynamic>? _assinatura;

  const _CanalAndamento._(this._avisos, this._assinatura);

  /// Sem quem escute, não cria porta nenhuma.
  factory _CanalAndamento(void Function(Andamento)? aoProgredir) {
    if (aoProgredir == null) return const _CanalAndamento._(null, null);
    final avisos = ReceivePort();
    return _CanalAndamento._(
      avisos,
      avisos.listen((mensagem) {
        if (mensagem is Andamento) aoProgredir(mensagem);
      }),
    );
  }

  SendPort? get porta => _avisos?.sendPort;

  Future<void> fechar() async {
    await _assinatura?.cancel();
    _avisos?.close();
  }
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
  void Function(Andamento)? aoProgredir,
  String etapa = 'Gravando os patrimônios…',
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
          : (feitos, total) => aoProgredir(_gravando(etapa, feitos, total)),
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
        etapa: etapa,
      ),
      // Erro não tratado ou saída sem resposta também chegam aqui: a tela
      // nunca fica esperando para sempre.
      onError: mensagens.sendPort,
      onExit: mensagens.sendPort,
    );

    await for (final mensagem in mensagens) {
      switch (mensagem) {
        case final Andamento p:
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

/// O andamento da gravação, dito do jeito que a barra mostra.
Andamento _gravando(String etapa, int feitos, int total) => Andamento(
  etapa,
  feitos: feitos,
  total: total,
  unidade: 'patrimônios gravados',
);

class _Pedido {
  final SendPort resposta;
  final String caminho;
  final String inventarioId;
  final PreviaImportacao previa;
  final Set<String> edsExcluidos;
  final String etapa;

  const _Pedido({
    required this.resposta,
    required this.caminho,
    required this.inventarioId,
    required this.previa,
    required this.edsExcluidos,
    required this.etapa,
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
          pedido.resposta.send(_gravando(pedido.etapa, feitos, total)),
    );
    pedido.resposta.send(resultado);
  } catch (e) {
    pedido.resposta.send(_Falha('$e'));
  } finally {
    banco.fechar();
  }
}
