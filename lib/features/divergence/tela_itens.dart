import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../domain/divergencia.dart';
import '../../domain/patrimonio.dart';

/// Lista de patrimônios, filtrada por grupo do resultado.
class TelaItens extends ConsumerStatefulWidget {
  final String inventarioId;
  final Classificacao? classificacao;

  const TelaItens({super.key, required this.inventarioId, this.classificacao});

  @override
  ConsumerState<TelaItens> createState() => _TelaItensState();
}

class _TelaItensState extends ConsumerState<TelaItens> {
  late Classificacao? _filtro = widget.classificacao;
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(revisaoProvider);

    final itens = ref
        .read(patrimoniosProvider)
        .listar(
          inventarioId: widget.inventarioId,
          classificacao: _filtro,
          busca: _busca.text,
          limite: 500,
        );

    return Scaffold(
      appBar: AppBar(title: Text(_filtro?.rotulo ?? 'Patrimônios')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _busca,
              decoration: InputDecoration(
                hintText: 'Buscar por tombo, código ou descrição',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busca.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_busca.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _Filtro(
                  rotulo: 'Todos',
                  ativo: _filtro == null,
                  aoTocar: () => setState(() => _filtro = null),
                ),
                for (final c in Classificacao.values)
                  _Filtro(
                    rotulo: c.rotulo,
                    ativo: _filtro == c,
                    cor: CoresResultado.de(c),
                    aoTocar: () => setState(() => _filtro = c),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: itens.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Nenhum patrimônio neste filtro.'),
                    ),
                  )
                : ListView.separated(
                    itemCount: itens.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _LinhaPatrimonio(
                      patrimonio: itens[i],
                      aoTocar: () => _abrirDetalhe(itens[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _abrirDetalhe(Patrimonio p) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DetalhePatrimonio(patrimonioId: p.id),
    );
  }
}

class _Filtro extends StatelessWidget {
  final String rotulo;
  final bool ativo;
  final Color? cor;
  final VoidCallback aoTocar;

  const _Filtro({
    required this.rotulo,
    required this.ativo,
    required this.aoTocar,
    this.cor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(rotulo),
        selected: ativo,
        onSelected: (_) => aoTocar(),
        avatar: cor == null
            ? null
            : CircleAvatar(backgroundColor: cor, radius: 6),
      ),
    );
  }
}

class _LinhaPatrimonio extends StatelessWidget {
  final Patrimonio patrimonio;
  final VoidCallback aoTocar;

  const _LinhaPatrimonio({required this.patrimonio, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final classificacao = classificar(patrimonio);
    final divergencias = divergenciasDe(patrimonio);

    return ListTile(
      leading: Icon(
        CoresResultado.icone(classificacao),
        color: CoresResultado.de(classificacao),
      ),
      title: Text(
        patrimonio.descricao ?? 'Sem descrição',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tombo ${patrimonio.tombo} · ${patrimonio.salaEfetiva ?? "sem sala"}',
          ),
          if (divergencias.isNotEmpty)
            Text(
              divergencias.map((d) => d.campo.rotulo).join(', '),
              style: const TextStyle(
                color: CoresResultado.alerta,
                fontSize: 12,
              ),
            ),
        ],
      ),
      trailing: patrimonio.exigeAtencao
          ? Tooltip(
              message: 'Requer providência',
              child: Icon(
                Icons.priority_high,
                color: Theme.of(context).colorScheme.error,
              ),
            )
          : null,
      isThreeLine: divergencias.isNotEmpty,
      onTap: aoTocar,
    );
  }
}

/// Ficha completa de um patrimônio, com o que veio do SUAP, o que foi
/// encontrado e o histórico de alterações.
class DetalhePatrimonio extends ConsumerWidget {
  final String patrimonioId;

  const DetalhePatrimonio({super.key, required this.patrimonioId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(revisaoProvider);

    final p = ref.read(patrimoniosProvider).porId(patrimonioId);
    if (p == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('Patrimônio não encontrado.'),
      );
    }

    final classificacao = classificar(p);
    final divergencias = divergenciasDe(p);
    final historico = ref.read(operacoesProvider).historicoDe(p.id);
    final formato = DateFormat('dd/MM/yyyy HH:mm');

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controlador) => ListView(
        controller: controlador,
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Icon(
                CoresResultado.icone(classificacao),
                color: CoresResultado.de(classificacao),
              ),
              const SizedBox(width: 8),
              Text(
                classificacao.rotulo,
                style: TextStyle(
                  color: CoresResultado.de(classificacao),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            p.descricao ?? 'Sem descrição',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),

          _Campo('Tombo', p.tombo),
          _Campo('Código de barras', p.codigoBarras ?? '—'),
          _Campo('Elemento de despesa', p.ed ?? '—'),
          _Campo('Valor', p.valor ?? '—'),

          if (divergencias.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Divergências',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final d in divergencias)
              Card(
                color: CoresResultado.alerta.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.campo.rotulo,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('SUAP: ${d.valorSuap ?? "(vazio)"}'),
                      Text('Encontrado: ${d.valorEncontrado ?? "(vazio)"}'),
                    ],
                  ),
                ),
              ),
          ],

          const SizedBox(height: 16),
          Text('Situação', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Campo('Sala (SUAP)', p.salaOriginal ?? '—'),
          _Campo('Sala encontrada', p.salaAtual ?? 'não alterada'),
          _Campo('Responsável (SUAP)', p.responsavelOriginal ?? '—'),
          _Campo(
            'Responsável encontrado',
            p.responsavelAtual ?? 'não alterado',
          ),
          _Campo('Estado', p.conservacao?.rotulo ?? '—'),
          _Campo('Situação de uso', p.situacao?.rotulo ?? '—'),

          if (p.verificado) ...[
            const SizedBox(height: 8),
            _Campo(
              'Verificado por',
              '${p.verificadoPor ?? "—"}'
                  '${p.verificadoPorMatricula == null ? '' : ' (${p.verificadoPorMatricula})'}',
            ),
            _Campo(
              'Verificado em',
              p.verificadoEm == null ? '—' : formato.format(p.verificadoEm!),
            ),
          ],

          if (historico.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Histórico de alterações',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Toda alteração fica registrada, com autor e aparelho.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            for (final op in historico.take(30))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history, size: 18),
                title: Text('${op.campo} → ${op.valor ?? "(vazio)"}'),
                subtitle: Text(
                  '${op.usuarioNome ?? "desconhecido"} · '
                  '${formato.format(op.hlc.momento)}',
                ),
              ),
          ],

          const SizedBox(height: 24),
          if (p.verificado)
            OutlinedButton.icon(
              onPressed: () => _desfazer(context, ref, p),
              icon: const Icon(Icons.undo),
              label: const Text('Desfazer verificação'),
            ),
        ],
      ),
    );
  }

  void _desfazer(BuildContext context, WidgetRef ref, Patrimonio p) {
    final identidade = ref.read(identidadeProvider);
    ref
        .read(patrimoniosProvider)
        .desfazerVerificacao(
          patrimonio: p,
          usuarioNome: identidade.nome,
          usuarioMatricula: identidade.matricula,
        );
    ref.read(revisaoProvider.notifier).mudou();
    Navigator.of(context).pop();
  }
}

class _Campo extends StatelessWidget {
  final String rotulo;
  final String valor;

  const _Campo(this.rotulo, this.valor);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(rotulo, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(valor)),
        ],
      ),
    );
  }
}
