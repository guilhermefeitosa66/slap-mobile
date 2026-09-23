import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
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
  /// Itens por página. Uma tela de celular mostra uns dez; cem dão folga para
  /// rolar rápido sem esperar a próxima página.
  static const _tamanhoPagina = 100;

  /// Espera depois da última tecla antes de buscar: digitar "cadeira" faz uma
  /// consulta, não sete.
  static const _esperaBusca = Duration(milliseconds: 250);

  late Classificacao? _filtro = widget.classificacao;
  final _busca = TextEditingController();
  final _rolagem = ScrollController();
  Timer? _atraso;

  final _itens = <Patrimonio>[];
  int _total = 0;
  bool _fim = false;

  @override
  void initState() {
    super.initState();
    _rolagem.addListener(_aoRolar);
    _carregar(manterQuantidade: false);
  }

  @override
  void dispose() {
    _atraso?.cancel();
    _rolagem.dispose();
    _busca.dispose();
    super.dispose();
  }

  /// Volta à primeira página, com o filtro e a busca atuais.
  ///
  /// [manterQuantidade] recarrega o que já estava na tela — é o caso de uma
  /// alteração chegando, em que a lista não deve pular de volta ao topo.
  void _recarregar({bool manterQuantidade = false}) =>
      setState(() => _carregar(manterQuantidade: manterQuantidade));

  void _carregar({required bool manterQuantidade}) {
    final quantidade = manterQuantidade && _itens.length > _tamanhoPagina
        ? _itens.length
        : _tamanhoPagina;
    final repo = ref.read(patrimoniosProvider);
    final pagina = repo.listar(
      inventarioId: widget.inventarioId,
      classificacao: _filtro,
      busca: _busca.text,
      limite: quantidade,
    );
    final total = repo.contar(
      inventarioId: widget.inventarioId,
      classificacao: _filtro,
      busca: _busca.text,
    );
    _itens
      ..clear()
      ..addAll(pagina);
    _total = total;
    _fim = pagina.length >= total;
  }

  void _proximaPagina() {
    if (_fim) return;
    final pagina = ref
        .read(patrimoniosProvider)
        .listar(
          inventarioId: widget.inventarioId,
          classificacao: _filtro,
          busca: _busca.text,
          limite: _tamanhoPagina,
          deslocamento: _itens.length,
        );
    setState(() {
      _itens.addAll(pagina);
      _fim = pagina.length < _tamanhoPagina || _itens.length >= _total;
    });
  }

  void _aoRolar() {
    // A próxima página vem antes do fim, para a rolagem não bater no chão.
    final posicao = _rolagem.position;
    if (posicao.pixels > posicao.maxScrollExtent - 800) _proximaPagina();
  }

  void _aoDigitar(String _) {
    _atraso?.cancel();
    _atraso = Timer(_esperaBusca, () {
      if (mounted) _recarregar();
    });
    setState(() {}); // o botão de limpar aparece e some
  }

  void _filtrar(Classificacao? c) {
    _filtro = c;
    _recarregar();
    if (_rolagem.hasClients) _rolagem.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    // Operação nova — local ou vinda de outro aparelho — recarrega o que
    // está na tela, sem perder a posição.
    ref.listen(revisaoProvider, (_, _) => _recarregar(manterQuantidade: true));

    return Scaffold(
      appBar: AppBar(title: Text(_filtro?.rotulo ?? 'Patrimônios')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _busca,
              decoration: InputDecoration(
                hintText: 'Buscar por tombo, código ou descrição',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busca.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpar a busca',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busca.clear();
                          _recarregar();
                        },
                      ),
              ),
              onChanged: _aoDigitar,
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _Filtro(
                  rotulo: 'Todos',
                  ativo: _filtro == null,
                  aoTocar: () => _filtrar(null),
                ),
                for (final c in Classificacao.values)
                  _Filtro(
                    rotulo: c.rotulo,
                    ativo: _filtro == c,
                    cor: CoresResultado.of(context).de(c).texto,
                    aoTocar: () => _filtrar(c),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _total == 1
                      ? '1 patrimônio'
                      : '${formatarInteiro(_total)} patrimônios',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _itens.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('Nenhum patrimônio neste filtro.'),
                    ),
                  )
                : ListView.separated(
                    controller: _rolagem,
                    itemCount: _itens.length + (_fim ? 0 : 1),
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 50),
                    itemBuilder: (_, i) {
                      if (i >= _itens.length) {
                        // Chegou ao fim do que foi carregado sem o ouvinte de
                        // rolagem disparar (lista curta que não rola).
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => mounted ? _proximaPagina() : null,
                        );
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                              ),
                            ),
                          ),
                        );
                      }
                      return _LinhaPatrimonio(
                        patrimonio: _itens[i],
                        aoTocar: () => _abrirDetalhe(_itens[i]),
                      );
                    },
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
    final esquema = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(rotulo),
        selected: ativo,
        showCheckmark: false,
        labelStyle: TextStyle(
          color: ativo ? esquema.onPrimary : esquema.onSurface,
          fontWeight: ativo ? FontWeight.w600 : FontWeight.w500,
        ),
        side: BorderSide(
          color: ativo ? esquema.primary : esquema.outlineVariant,
        ),
        onSelected: (_) => aoTocar(),
        avatar: cor == null
            ? null
            : ExcludeSemantics(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: cor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ativo ? esquema.onPrimary : Colors.transparent,
                    ),
                  ),
                ),
              ),
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
    final tom = CoresResultado.of(context).de(classificacao);
    final tema = Theme.of(context);

    return InkWell(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                CoresResultado.icone(classificacao),
                color: tom.texto,
                size: 22,
                semanticLabel: classificacao.rotulo,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patrimonio.descricao ?? 'Sem descrição',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tema.textTheme.bodyMedium?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tombo ${patrimonio.tombo} · '
                    '${patrimonio.salaEfetiva ?? "sem sala"}',
                    style: tema.textTheme.bodySmall,
                  ),
                  if (divergencias.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        divergencias.map((d) => d.campo.rotulo).join(', '),
                        style: tema.textTheme.bodySmall?.copyWith(
                          color: tom.texto,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (patrimonio.exigeAtencao)
              Tooltip(
                message: 'Requer providência',
                child: Icon(
                  Icons.priority_high,
                  color: tema.colorScheme.error,
                  semanticLabel: 'Requer providência',
                ),
              ),
          ],
        ),
      ),
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
              IconeEmTom(
                icone: CoresResultado.icone(classificacao),
                tom: CoresResultado.of(context).de(classificacao),
                tamanho: 32,
              ),
              const SizedBox(width: 10),
              Text(
                classificacao.rotulo,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: CoresResultado.of(context).de(classificacao).texto,
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
            for (final d in divergencias) _CartaoDivergencia(divergencia: d),
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

class _CartaoDivergencia extends StatelessWidget {
  final Divergencia divergencia;

  const _CartaoDivergencia({required this.divergencia});

  @override
  Widget build(BuildContext context) {
    final tom = CoresResultado.of(context).jaVerificado;
    final estilo = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: tom.texto, fontSize: 13.5);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tom.fundo,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            divergencia.campo.rotulo,
            style: estilo?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 3),
          Text('SUAP: ${divergencia.valorSuap ?? "(vazio)"}', style: estilo),
          Text(
            'Encontrado: ${divergencia.valorEncontrado ?? "(vazio)"}',
            style: estilo,
          ),
        ],
      ),
    );
  }
}
