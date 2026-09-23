import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/formato.dart';
import '../../data/banco.dart';
import '../../data/repos/inventarios.dart';
import '../../data/repos/patrimonios.dart';
import '../import/importacao_em_segundo_plano.dart';
import '../import/importador.dart';

/// Ações de manutenção de um inventário, com as confirmações que pedem.

/// Altera nome e ano.
Future<void> editarInventario(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final dados = await showDialog<({String nome, int ano})>(
    context: context,
    builder: (_) => DialogoInventario(
      titulo: 'Editar inventário',
      rotuloConfirmar: 'Salvar',
      nomeInicial: inventario.nome,
      anoInicial: inventario.ano,
    ),
  );
  if (dados == null) return;

  ref
      .read(inventariosProvider)
      .editar(inventario.id, nome: dados.nome, ano: dados.ano);
  ref.read(revisaoProvider.notifier).mudou();
}

/// Cria um inventário novo com os mesmos patrimônios, para o ano seguinte.
///
/// Leva o que veio do SUAP e os EDs excluídos; o levantamento começa do zero.
/// Devolve o inventário criado, ou `null` se a pessoa desistiu.
Future<Inventario?> duplicarInventario(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final dados = await showDialog<({String nome, int ano})>(
    context: context,
    builder: (_) => DialogoInventario(
      titulo: 'Duplicar para outro ano',
      rotuloConfirmar: 'Duplicar',
      nomeInicial: inventario.nome,
      anoInicial: inventario.ano + 1,
      explicacao:
          'Um inventário novo, com os mesmos patrimônios e os mesmos '
          'elementos de despesa excluídos. O levantamento começa do zero, e '
          'este continua como está.',
    ),
  );
  if (dados == null || !context.mounted) return null;

  final progresso = ValueNotifier<ProgressoImportacao?>(null);
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Duplicando…'),
          content: ValueListenableBuilder(
            valueListenable: progresso,
            builder: (_, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: p?.fracao),
                const SizedBox(height: 12),
                Text(
                  p == null
                      ? 'Preparando os patrimônios'
                      : '${formatarInteiro(p.feitos)} de '
                            '${formatarInteiro(p.total)} patrimônios',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  try {
    final novo = await duplicarEstrutura(
      banco: ref.read(bancoProvider),
      inventarios: ref.read(inventariosProvider),
      patrimonios: ref.read(patrimoniosProvider),
      origem: inventario,
      nome: dados.nome,
      ano: dados.ano,
      aoProgredir: (p) => progresso.value = p,
    );
    ref.read(revisaoProvider.notifier).mudou();
    return novo;
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progresso.dispose();
  }
}

/// A duplicação em si, sem interface: cria, copia os originais do SUAP em
/// segundo plano e reaplica os EDs excluídos.
Future<Inventario> duplicarEstrutura({
  required Banco banco,
  required RepositorioInventarios inventarios,
  required RepositorioPatrimonios patrimonios,
  required Inventario origem,
  required String nome,
  required int ano,
  void Function(ProgressoImportacao)? aoProgredir,
}) async {
  final itens = [
    for (final p in patrimonios.todos(origem.id, incluirIgnorados: true))
      PatrimonioImportado(
        ordem: p.ordem,
        tombo: p.tombo,
        codigoBarras: p.codigoBarras,
        ed: p.ed,
        descricao: p.descricao,
        responsavel: p.responsavelOriginal,
        sala: p.salaOriginal,
        valor: p.valor,
        conservacao: p.conservacaoOriginal,
        situacao: p.situacaoOriginal,
      ),
  ];

  final novo = inventarios.criar(nome: nome, ano: ano);
  await importarEmSegundoPlano(
    banco: banco,
    inventarioId: novo.id,
    previa: PreviaImportacao(
      itens: itens,
      linhasExaminadas: itens.length,
      semTombo: 0,
      tombosDuplicados: const [],
      contagemPorEd: const {},
    ),
    aoProgredir: aoProgredir,
  );
  if (origem.edsExcluidos.isNotEmpty) {
    inventarios.definirEdsExcluidos(novo.id, origem.edsExcluidos);
  }
  return novo;
}

/// Apaga a réplica deste aparelho, dizendo antes o que se perde.
///
/// Devolve `true` se apagou.
Future<bool> apagarInventario(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final perda = ref.read(operacoesProvider).trabalhoNaoEntregue(inventario.id);

  final String aviso;
  if (perda.nada) {
    aviso =
        'Tudo o que foi feito neste aparelho já está em outro. Sincronizar '
        'de novo com eles traz o inventário de volta.';
  } else if (!perda.jaSincronizou) {
    aviso =
        'Este aparelho nunca sincronizou este inventário. '
        '${_verificacoes(perda.verificacoes)} feitas aqui '
        '${perda.verificacoes == 1 ? 'se perde' : 'se perdem'} para sempre.';
  } else {
    aviso =
        '${_verificacoes(perda.verificacoes)} feitas neste aparelho ainda '
        '${perda.verificacoes == 1 ? 'não chegou' : 'não chegaram'} a nenhum '
        'outro e ${perda.verificacoes == 1 ? 'se perde' : 'se perdem'}. '
        'Sincronize antes de apagar para não perder esse trabalho.';
  }

  final confirmou = await showDialog<bool>(
    context: context,
    builder: (contexto) {
      final esquema = Theme.of(contexto).colorScheme;
      return AlertDialog(
        title: const Text('Apagar deste aparelho?'),
        content: Text(
          'Só a cópia deste aparelho é apagada. Os outros aparelhos do '
          'inventário não são afetados.\n\n$aviso',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(contexto, true),
            style: FilledButton.styleFrom(
              backgroundColor: esquema.error,
              foregroundColor: esquema.onError,
              minimumSize: const Size(0, 48),
            ),
            child: Text(perda.nada ? 'Apagar' : 'Apagar mesmo assim'),
          ),
        ],
      );
    },
  );
  if (confirmou != true) return false;

  ref.read(inventariosProvider).removerLocalmente(inventario.id);
  ref.read(revisaoProvider.notifier).mudou();
  return true;
}

String _verificacoes(int n) =>
    n == 1 ? '1 verificação' : '${formatarInteiro(n)} verificações';

/// Encerra o inventário, depois de dizer quantos itens ficam como não
/// localizados.
Future<void> encerrarInventario(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final progresso = ref.read(progressoProvider(inventario.id));
  final pendentes = progresso.pendentes;

  final confirmou = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('Encerrar o inventário?'),
      content: Text(
        '${pendentes == 0 ? 'Todos os ${formatarInteiro(progresso.total)} itens foram verificados.' : '${formatarInteiro(pendentes)} ${pendentes == 1 ? 'item ainda não foi verificado e ficará' : 'itens ainda não foram verificados e ficarão'} como não localizados nos relatórios.'}\n\n'
        'O levantamento fica bloqueado neste aparelho e nos outros, depois '
        'que sincronizarem. É possível reabrir.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(contexto, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(contexto, true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Encerrar'),
        ),
      ],
    ),
  );
  if (confirmou != true) return;

  ref.read(inventariosProvider).encerrar(inventario.id);
  ref.read(revisaoProvider.notifier).mudou();
}

/// Reabre um inventário encerrado.
Future<void> reabrirInventario(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('Reabrir o inventário?'),
      content: const Text(
        'O levantamento volta a ser permitido neste aparelho e nos outros, '
        'depois que sincronizarem. A reabertura fica registrada no histórico, '
        'como o encerramento.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(contexto, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(contexto, true),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: const Text('Reabrir'),
        ),
      ],
    ),
  );
  if (confirmou != true) return;

  ref.read(inventariosProvider).reabrir(inventario.id);
  ref.read(revisaoProvider.notifier).mudou();
}

/// Nome e ano de um inventário: para criar, editar ou duplicar.
///
/// Devolve o que foi preenchido, ou `null` se a pessoa desistiu.
class DialogoInventario extends StatefulWidget {
  final String titulo;
  final String rotuloConfirmar;
  final String? nomeInicial;
  final int? anoInicial;

  /// Explicação acima dos campos, quando a ação pede uma.
  final String? explicacao;

  const DialogoInventario({
    super.key,
    required this.titulo,
    required this.rotuloConfirmar,
    this.nomeInicial,
    this.anoInicial,
    this.explicacao,
  });

  @override
  State<DialogoInventario> createState() => _DialogoInventarioState();
}

class _DialogoInventarioState extends State<DialogoInventario> {
  final _formulario = GlobalKey<FormState>();
  late final _nome = TextEditingController(text: widget.nomeInicial ?? '');
  late final _ano = TextEditingController(
    text: '${widget.anoInicial ?? DateTime.now().year}',
  );

  @override
  void dispose() {
    _nome.dispose();
    _ano.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: Form(
        key: _formulario,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.explicacao != null) ...[
              Text(widget.explicacao!),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _nome,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Campus Picos — Biblioteca',
                // Nome + ano não são chave única: a mesma unidade pode ter
                // vários processos no mesmo ano.
                helperText: 'Texto livre. Pode repetir no mesmo ano.',
                helperMaxLines: 2,
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe um nome' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ano,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Ano'),
              validator: (v) {
                final ano = int.tryParse(v ?? '');
                if (ano == null || ano < 1990 || ano > 2100) {
                  return 'Ano inválido';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!_formulario.currentState!.validate()) return;
            Navigator.pop(context, (
              nome: _nome.text.trim(),
              ano: int.parse(_ano.text),
            ));
          },
          style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          child: Text(widget.rotuloConfirmar),
        ),
      ],
    );
  }
}
