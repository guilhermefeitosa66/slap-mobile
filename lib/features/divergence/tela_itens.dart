import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import '../../domain/divergencia.dart';
import '../../domain/filtro_itens.dart';
import '../../domain/patrimonio.dart';
import '../../domain/valores.dart';
import '../survey/campo_com_sugestoes.dart';

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

  late Classificacao? _classificacao = widget.classificacao;
  FiltroItens _filtro = FiltroItens.nenhum;
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
      classificacao: _classificacao,
      filtro: _filtro,
      busca: _busca.text,
      limite: quantidade,
    );
    final total = repo.contar(
      inventarioId: widget.inventarioId,
      classificacao: _classificacao,
      filtro: _filtro,
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
          classificacao: _classificacao,
          filtro: _filtro,
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
    _classificacao = c;
    _recarregar();
    if (_rolagem.hasClients) _rolagem.jumpTo(0);
  }

  /// Aplica o filtro escolhido e volta ao topo: a posição da rolagem anterior
  /// não diz nada sobre a lista nova.
  void _aplicar(FiltroItens filtro) {
    _filtro = filtro;
    _recarregar();
    if (_rolagem.hasClients) _rolagem.jumpTo(0);
  }

  /// Abre a folha de filtros com os valores que existem neste inventário.
  ///
  /// As listas saem do banco na hora de abrir — são consultas de valores
  /// distintos, não a lista de itens —, e não ficam guardadas: uma
  /// sincronização pode trazer salas e pessoas que não existiam aqui.
  Future<void> _abrirFiltros() async {
    final repo = ref.read(patrimoniosProvider);
    final escolhido = await showModalBottomSheet<FiltroItens>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _FolhaFiltros(
        inicial: _filtro,
        classificacao: _classificacao,
        valores: {
          CampoFiltro.sala: repo.salasOriginais(widget.inventarioId),
          CampoFiltro.salaAtual: repo.salasAtuais(widget.inventarioId),
          CampoFiltro.responsavel: repo.responsaveisOriginais(
            widget.inventarioId,
          ),
          CampoFiltro.responsavelAtual: repo.responsaveisAtuais(
            widget.inventarioId,
          ),
          CampoFiltro.verificadoPor: repo.verificadores(widget.inventarioId),
        },
      ),
    );
    if (escolhido != null && mounted) _aplicar(escolhido);
  }

  /// Por que a lista está vazia — nunca "o inventário está vazio" quando há
  /// filtro ou busca valendo.
  String get _mensagemVazia {
    if (!_filtro.algumAtivo && _busca.text.trim().isEmpty) {
      return 'Nenhum patrimônio neste filtro.';
    }
    if (_classificacao == Classificacao.naoLocalizado &&
        _filtro.exigeVerificado) {
      return 'Nenhum patrimônio combina. Estado de conservação, situação de '
          'uso e quem verificou só existem em item encontrado — e estes são '
          'justamente os que não foram.';
    }
    return 'Nenhum patrimônio combina com o que está filtrado.';
  }

  @override
  Widget build(BuildContext context) {
    // Operação nova — local ou vinda de outro aparelho — recarrega o que
    // está na tela, sem perder a posição.
    ref.listen(revisaoProvider, (_, _) => _recarregar(manterQuantidade: true));

    final ativos = _filtro.quantidade;

    return Scaffold(
      appBar: AppBar(
        title: Text(_classificacao?.rotulo ?? 'Patrimônios'),
        actions: [
          IconButton(
            onPressed: _abrirFiltros,
            // O número entra no rótulo falado: o distintivo é visual, e o
            // leitor de tela não o enxerga.
            tooltip: switch (ativos) {
              0 => 'Filtrar',
              1 => 'Filtros (1 ativo)',
              _ => 'Filtros ($ativos ativos)',
            },
            icon: Badge(
              isLabelVisible: ativos > 0,
              label: Text('$ativos'),
              child: const Icon(Icons.filter_list),
            ),
          ),
        ],
      ),
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
                  ativo: _classificacao == null,
                  aoTocar: () => _filtrar(null),
                ),
                for (final c in Classificacao.values)
                  _Filtro(
                    rotulo: c.rotulo,
                    ativo: _classificacao == c,
                    cor: CoresResultado.of(context).de(c).texto,
                    aoTocar: () => _filtrar(c),
                  ),
              ],
            ),
          ),
          // Uma ficha por filtro ativo, logo abaixo da busca: sem elas, uma
          // lista curta parece inventário pequeno. Em Wrap, e não em fila
          // rolável, para caberem com a fonte do sistema ampliada.
          if (_filtro.algumAtivo)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final MapEntry(key: campo, value: valor)
                      in _filtro.ativos.entries)
                    _FichaFiltro(
                      rotulo: '${campo.rotulo}: $valor',
                      dica: 'Remover o filtro ${campo.rotulo}',
                      aoTocar: () => _aplicar(_filtro.sem(campo)),
                    ),
                  if (ativos > 1)
                    _FichaFiltro(
                      rotulo: 'Limpar filtros',
                      dica: 'Limpar todos os filtros',
                      aoTocar: () => _aplicar(FiltroItens.nenhum),
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
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_mensagemVazia, textAlign: TextAlign.center),
                          if (_filtro.algumAtivo) ...[
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: () => _aplicar(FiltroItens.nenhum),
                              icon: const Icon(Icons.filter_list_off),
                              label: const Text('Limpar filtros'),
                            ),
                          ],
                        ],
                      ),
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

/// Ficha de um filtro ativo. Tocar remove o filtro que ela mostra.
///
/// O X fica no começo, e não como botão separado de excluir: a ficha inteira
/// é o alvo de toque, com um só nó de semântica, o que evita um alvo de 24 px
/// dentro de outro.
class _FichaFiltro extends StatelessWidget {
  final String rotulo;
  final String dica;
  final VoidCallback aoTocar;

  const _FichaFiltro({
    required this.rotulo,
    required this.dica,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: const Icon(Icons.close, size: 18),
      label: Text(rotulo),
      tooltip: dica,
      onPressed: aoTocar,
    );
  }
}

/// Folha de filtros da lista de itens.
///
/// Devolve o filtro escolhido; sair sem aplicar devolve `null` e nada muda.
class _FolhaFiltros extends StatefulWidget {
  final FiltroItens inicial;

  /// Classificação selecionada na lista. Serve só para avisar quando o que
  /// está sendo escolhido não pode combinar com ela.
  final Classificacao? classificacao;

  /// Valores que existem neste inventário, por campo de texto.
  final Map<CampoFiltro, List<String>> valores;

  const _FolhaFiltros({
    required this.inicial,
    required this.classificacao,
    required this.valores,
  });

  @override
  State<_FolhaFiltros> createState() => _FolhaFiltrosState();
}

class _FolhaFiltrosState extends State<_FolhaFiltros> {
  late String? _sala = widget.inicial.sala;
  late String? _salaAtual = widget.inicial.salaAtual;
  late String? _responsavel = widget.inicial.responsavel;
  late String? _responsavelAtual = widget.inicial.responsavelAtual;
  late EstadoConservacao? _conservacao = widget.inicial.conservacao;
  late SituacaoUso? _situacao = widget.inicial.situacao;
  late String? _verificadoPor = widget.inicial.verificadoPor;

  FiltroItens get _escolhido => FiltroItens(
    sala: _sala,
    salaAtual: _salaAtual,
    responsavel: _responsavel,
    responsavelAtual: _responsavelAtual,
    conservacao: _conservacao,
    situacao: _situacao,
    verificadoPor: _verificadoPor,
  );

  void _limpar() => setState(() {
    _sala = null;
    _salaAtual = null;
    _responsavel = null;
    _responsavelAtual = null;
    _conservacao = null;
    _situacao = null;
    _verificadoPor = null;
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final naoLocalizado = widget.classificacao == Classificacao.naoLocalizado;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text('Filtrar', style: tema.textTheme.headlineSmall),
                ),
                IconButton(
                  tooltip: 'Fechar sem aplicar',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              'Os filtros valem junto com a busca e com a classificação '
              'escolhida na lista.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),

            _SeletorValor(
              campo: CampoFiltro.sala,
              ajuda: 'Onde a planilha do SUAP diz que o item está.',
              valor: _sala,
              valores: widget.valores[CampoFiltro.sala]!,
              aoEscolher: (v) => setState(() => _sala = v),
            ),
            _SeletorValor(
              campo: CampoFiltro.salaAtual,
              // A decisão de usar o valor efetivo fica dita aqui, onde
              // importa: senão o filtro pareceria ignorar o que não se mexeu.
              ajuda:
                  'Onde o item está agora: o que o levantamento encontrou '
                  'ou, sem mudança, o da planilha.',
              valor: _salaAtual,
              valores: widget.valores[CampoFiltro.salaAtual]!,
              aoEscolher: (v) => setState(() => _salaAtual = v),
            ),
            _SeletorValor(
              campo: CampoFiltro.responsavel,
              ajuda: 'De quem a planilha do SUAP diz que o item é.',
              valor: _responsavel,
              valores: widget.valores[CampoFiltro.responsavel]!,
              aoEscolher: (v) => setState(() => _responsavel = v),
            ),
            _SeletorValor(
              campo: CampoFiltro.responsavelAtual,
              ajuda:
                  'De quem o item é agora: o responsável do levantamento '
                  'ou, sem mudança, o da planilha.',
              valor: _responsavelAtual,
              valores: widget.valores[CampoFiltro.responsavelAtual]!,
              aoEscolher: (v) => setState(() => _responsavelAtual = v),
            ),
            _SeletorValor(
              campo: CampoFiltro.verificadoPor,
              ajuda: 'Quem registrou a verificação, em qualquer aparelho.',
              valor: _verificadoPor,
              valores: widget.valores[CampoFiltro.verificadoPor]!,
              aoEscolher: (v) => setState(() => _verificadoPor = v),
            ),

            const SizedBox(height: 16),
            Text(
              CampoFiltro.conservacao.rotulo,
              style: tema.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final c in EstadoConservacao.values)
                  FilterChip(
                    label: Text(c.rotulo),
                    selected: _conservacao == c,
                    onSelected: (marcado) =>
                        setState(() => _conservacao = marcado ? c : null),
                  ),
              ],
            ),

            const SizedBox(height: 16),
            Text(CampoFiltro.situacao.rotulo, style: tema.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in SituacaoUso.values)
                  FilterChip(
                    label: Text(s.rotulo),
                    selected: _situacao == s,
                    onSelected: (marcado) =>
                        setState(() => _situacao = marcado ? s : null),
                  ),
              ],
            ),

            const SizedBox(height: 10),
            // Estado, situação e autor da verificação nascem da leitura: o
            // item não localizado não tem nenhum dos três. Dizer isso aqui
            // evita a lista vazia sem explicação.
            Text(
              naoLocalizado
                  ? 'A lista está em "Não localizado". Esses itens não têm '
                        'estado, situação nem quem verificou: filtrar por um '
                        'deles não deixa nenhum item.'
                  : 'Estado, situação e "verificado por" só existem em item '
                        'encontrado: filtrar por eles deixa de fora os não '
                        'localizados.',
              style: tema.textTheme.bodySmall,
            ),

            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, _escolhido),
              icon: const Icon(Icons.check),
              label: const Text('Aplicar'),
            ),
            if (_escolhido.algumAtivo) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _limpar,
                icon: const Icon(Icons.filter_list_off),
                label: const Text('Limpar tudo'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Linha de um filtro de texto: o que está escolhido e o caminho para trocar.
class _SeletorValor extends StatelessWidget {
  final CampoFiltro campo;
  final String ajuda;
  final String? valor;
  final List<String> valores;
  final ValueChanged<String?> aoEscolher;

  const _SeletorValor({
    required this.campo,
    required this.ajuda,
    required this.valor,
    required this.valores,
    required this.aoEscolher,
  });

  Future<void> _escolher(BuildContext context) async {
    final escolha = await showModalBottomSheet<_Escolha>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _ListaDeValores(campo: campo, valores: valores, selecionado: valor),
    );
    if (escolha != null) aoEscolher(escolha.valor);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final semValores = valores.isEmpty;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(campo.rotulo, style: tema.textTheme.labelLarge),
      subtitle: Text(
        valor ?? (semValores ? 'Nenhum valor neste inventário' : ajuda),
        style: valor == null
            ? tema.textTheme.bodySmall
            : tema.textTheme.bodyMedium?.copyWith(
                color: tema.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
      ),
      trailing: valor == null
          ? const Icon(Icons.expand_more)
          : IconButton(
              tooltip: 'Limpar o filtro de ${campo.rotulo}',
              icon: const Icon(Icons.clear),
              onPressed: () => aoEscolher(null),
            ),
      // Sem valor nenhum — ninguém verificou ainda, por exemplo — não há o que
      // escolher, e a linha deixa de ser um botão que não leva a lugar algum.
      onTap: semValores ? null : () => _escolher(context),
    );
  }
}

/// O que a lista de valores devolveu. `null` dentro dela é "qualquer valor" —
/// o que distingue limpar o filtro de fechar sem escolher.
class _Escolha {
  final String? valor;
  const _Escolha(this.valor);
}

/// Lista de valores conhecidos de um campo, com busca.
///
/// A lista de salas de um campus passa de cem nomes e a de responsáveis
/// acompanha o quadro de servidores: sem busca, escolher vira rolagem.
class _ListaDeValores extends StatefulWidget {
  final CampoFiltro campo;
  final List<String> valores;
  final String? selecionado;

  const _ListaDeValores({
    required this.campo,
    required this.valores,
    required this.selecionado,
  });

  @override
  State<_ListaDeValores> createState() => _ListaDeValoresState();
}

class _ListaDeValoresState extends State<_ListaDeValores> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    // Sem caixa nem acento, como o resto do sistema: "audi" acha "Auditório".
    final procurado = formaComparavel(_busca.text);
    final visiveis = procurado.isEmpty
        ? widget.valores
        : [
            for (final v in widget.valores)
              if (formaComparavel(v).contains(procurado)) v,
          ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controlador) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.campo.rotulo,
                    style: tema.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar sem escolher',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              controller: _busca,
              decoration: const InputDecoration(
                hintText: 'Buscar na lista',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: visiveis.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Nenhum valor combina com a busca.',
                        style: tema.textTheme.bodyMedium,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: controlador,
                    padding: EdgeInsets.only(
                      bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                    ),
                    // A primeira linha limpa o filtro, e por isso só aparece
                    // quando a busca não escondeu o resto da lista.
                    itemCount: visiveis.length + (procurado.isEmpty ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (procurado.isEmpty && i == 0) {
                        return _LinhaValor(
                          texto: 'Qualquer',
                          escolhido: widget.selecionado == null,
                          aoTocar: () =>
                              Navigator.pop(context, const _Escolha(null)),
                        );
                      }
                      final valor = visiveis[i - (procurado.isEmpty ? 1 : 0)];
                      return _LinhaValor(
                        texto: valor,
                        escolhido: mesmoTexto(valor, widget.selecionado),
                        aoTocar: () => Navigator.pop(context, _Escolha(valor)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LinhaValor extends StatelessWidget {
  final String texto;
  final bool escolhido;
  final VoidCallback aoTocar;

  const _LinhaValor({
    required this.texto,
    required this.escolhido,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(texto),
      selected: escolhido,
      trailing: escolhido
          ? const Icon(Icons.check, semanticLabel: 'escolhido')
          : null,
      onTap: aoTocar,
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

/// Ficha completa de um patrimônio, em três seções: o status, o que veio da
/// planilha do SUAP e o que o levantamento encontrou — editável ali mesmo.
/// Depois delas, o histórico de alterações e o desfazer.
class DetalhePatrimonio extends ConsumerStatefulWidget {
  final String patrimonioId;

  const DetalhePatrimonio({super.key, required this.patrimonioId});

  @override
  ConsumerState<DetalhePatrimonio> createState() => _DetalhePatrimonioState();
}

class _DetalhePatrimonioState extends ConsumerState<DetalhePatrimonio> {
  /// Campos em edição. Só existe enquanto a seção "Levantamento" está aberta
  /// para alteração.
  _EdicaoLevantamento? _edicao;

  @override
  void dispose() {
    _edicao?.dispose();
    super.dispose();
  }

  bool _encerrado(Patrimonio p) =>
      ref.read(inventarioProvider(p.inventarioId))?.encerrado ?? false;

  void _editar(Patrimonio p) {
    final repo = ref.read(patrimoniosProvider);
    setState(() {
      _edicao = _EdicaoLevantamento(
        p,
        salas: repo.salas(p.inventarioId),
        responsaveis: repo.responsaveis(p.inventarioId),
      );
    });
  }

  void _fecharEdicao() {
    final antiga = _edicao;
    setState(() => _edicao = null);
    // Os campos ainda estão na tela até o próximo quadro.
    WidgetsBinding.instance.addPostFrameCallback((_) => antiga?.dispose());
  }

  /// Grava o que mudou, pelo log de operações — nunca direto na tabela: a
  /// alteração precisa chegar aos outros aparelhos e sobreviver à
  /// materialização.
  ///
  /// Abrir o detalhe e salvar já é a ação explícita que a regra "item já
  /// verificado nunca é sobrescrito em silêncio" exige; não há segunda
  /// confirmação.
  void _salvar(Patrimonio p) {
    final edicao = _edicao;
    if (edicao == null) return;

    // Outro aparelho pode ter encerrado o inventário com o painel aberto.
    if (_encerrado(p)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Inventário encerrado: nada foi alterado.'),
        ),
      );
      _fecharEdicao();
      return;
    }

    final identidade = ref.read(identidadeProvider);
    ref
        .read(patrimoniosProvider)
        .alterarLevantamento(
          patrimonio: p,
          sala: edicao.sala.text,
          responsavel: edicao.responsavel.text,
          conservacao: edicao.conservacao,
          situacao: edicao.situacao,
          usuarioNome: identidade.nome,
          usuarioMatricula: identidade.matricula,
        );
    ref.read(revisaoProvider.notifier).mudou();
    _fecharEdicao();
  }

  void _desfazer(Patrimonio p) {
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

  @override
  Widget build(BuildContext context) {
    ref.watch(revisaoProvider);

    final p = ref.read(patrimoniosProvider).porId(widget.patrimonioId);
    if (p == null) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text('Patrimônio não encontrado.'),
      );
    }

    final classificacao = classificar(p);
    final tom = CoresResultado.of(context).de(classificacao);
    final historico = ref.read(operacoesProvider).historicoDe(p.id);
    final formato = DateFormat('dd/MM/yyyy HH:mm');
    final encerrado =
        ref.watch(inventarioProvider(p.inventarioId))?.encerrado ?? false;
    final esteAparelho = ref.read(bancoProvider).dispositivoId;
    final tema = Theme.of(context);
    final edicao = _edicao;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (context, controlador) => ListView(
        controller: controlador,
        // O teclado da edição cobre a parte de baixo da folha; o recuo deixa
        // rolar até o que ficou embaixo dele.
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        children: [
          // 1. Status.
          Row(
            children: [
              IconeEmTom(
                icone: CoresResultado.icone(classificacao),
                tom: tom,
                tamanho: 32,
              ),
              const SizedBox(width: 10),
              // Com a fonte do sistema grande, o rótulo quebra em vez de
              // empurrar o ícone para fora da tela.
              Expanded(
                child: Text(
                  classificacao.rotulo,
                  style: tema.textTheme.titleSmall?.copyWith(color: tom.texto),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            p.descricao ?? 'Sem descrição',
            style: tema.textTheme.titleLarge,
          ),

          // 2. O que veio da importação, e não muda.
          const SizedBox(height: 20),
          const _TituloSecao('Dados da planilha (SUAP)'),
          _Campo('Tombo', p.tombo),
          _Campo('Código de barras', p.codigoBarras ?? '—'),
          _Campo('Elemento de despesa', p.ed ?? '—'),
          _Campo('Valor', p.valor ?? '—'),
          _Campo('Sala', p.salaOriginal ?? '—'),
          _Campo('Responsável', p.responsavelOriginal ?? '—'),

          // 3. O que o inventário produz.
          const SizedBox(height: 20),
          const _TituloSecao('Levantamento'),
          // Fora da edição, os valores vêm antes de quem os registrou. Com o
          // formulário aberto a ordem se inverte, para que Cancelar e Salvar
          // fechem a seção em vez de ficarem no meio dela.
          if (edicao == null)
            if (!p.verificado)
              Text(
                'Ainda não encontrado no levantamento.',
                style: tema.textTheme.bodySmall,
              )
            else ...[
              _CampoComTom(
                rotulo: 'Sala atual',
                valor: p.salaAtual ?? 'não alterada',
                igual: mesmoTexto(p.salaOriginal, p.salaEfetiva),
              ),
              _CampoComTom(
                rotulo: 'Responsável atual',
                valor: p.responsavelAtual ?? 'não alterado',
                igual: mesmoTexto(p.responsavelOriginal, p.responsavelEfetivo),
              ),
              _Campo('Estado de conservação', p.conservacao?.rotulo ?? '—'),
              _Campo('Situação de uso', p.situacao?.rotulo ?? '—'),
            ],

          // Quem encontrou o item. Não se edita: vem da identidade de quem
          // gravou a verificação. Fica visível durante a edição porque é o que
          // diz de quem é o levantamento que está prestes a ser alterado.
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
            // Depois da sincronização, é o que diz se fui eu ou outra pessoa.
            _Campo('Aparelho', switch (p.verificadoPorDispositivo) {
              null => '—',
              final d when d == esteAparelho => 'Este aparelho',
              _ => 'Outro aparelho',
            }),
          ],

          if (edicao != null) ...[
            _FormularioLevantamento(
              edicao: edicao,
              verificacaoManual: !p.verificado,
              aoCancelar: _fecharEdicao,
              aoSalvar: () => _salvar(p),
            ),
          ] else ...[
            const SizedBox(height: 12),
            if (encerrado)
              Text(
                'Inventário encerrado: o levantamento não muda mais.',
                style: tema.textTheme.bodySmall,
              )
            else
              // Item de ED excluído também se edita: o leitor já o registra,
              // avisando que está fora do inventário, e bloquear só aqui seria
              // mais uma regra para o usuário descobrir sozinho.
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _editar(p),
                  icon: Icon(
                    p.verificado
                        ? Icons.edit_outlined
                        : Icons.fact_check_outlined,
                  ),
                  // Editar um item não localizado é verificá-lo sem leitor.
                  label: Text(
                    p.verificado
                        ? 'Editar levantamento'
                        : 'Verificar manualmente',
                  ),
                ),
              ),
          ],

          // Com o formulário aberto, o painel termina em Cancelar e Salvar:
          // nem o histórico nem o desfazer disputam a atenção ali — e
          // "Desfazer verificação" logo abaixo de "Salvar" é vizinhança
          // perigosa para um toque apressado.
          if (edicao == null && historico.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _TituloSecao('Histórico de alterações'),
            Text(
              'Toda alteração fica registrada, com autor e aparelho.',
              style: tema.textTheme.bodySmall,
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
          // Encerrado, o levantamento não muda mais — nem para desfazer.
          if (edicao == null && p.verificado && !encerrado)
            OutlinedButton.icon(
              onPressed: () => _desfazer(p),
              icon: const Icon(Icons.undo),
              label: const Text('Desfazer verificação'),
            ),
        ],
      ),
    );
  }
}

/// O que está sendo editado na seção "Levantamento".
///
/// Sala e responsável mostram só o que o levantamento gravou: em branco, o
/// valor da planilha permanece — e salvar sem mexer em nada não gera
/// operação. Estado e situação sem valor partem do padrão das leituras.
class _EdicaoLevantamento {
  final TextEditingController sala;
  final TextEditingController responsavel;
  EstadoConservacao conservacao;
  SituacaoUso situacao;
  final List<String> salas;
  final List<String> responsaveis;

  _EdicaoLevantamento(
    Patrimonio p, {
    required this.salas,
    required this.responsaveis,
  }) : sala = TextEditingController(text: p.salaAtual ?? ''),
       responsavel = TextEditingController(text: p.responsavelAtual ?? ''),
       conservacao = p.conservacao ?? EstadoConservacao.bom,
       situacao = p.situacao ?? SituacaoUso.ativo;

  void dispose() {
    sala.dispose();
    responsavel.dispose();
  }
}

/// Os quatro campos do levantamento, para alterar ali mesmo.
class _FormularioLevantamento extends StatefulWidget {
  final _EdicaoLevantamento edicao;

  /// O item ainda não foi encontrado: salvar é verificá-lo manualmente.
  final bool verificacaoManual;
  final VoidCallback aoCancelar;
  final VoidCallback aoSalvar;

  const _FormularioLevantamento({
    required this.edicao,
    required this.verificacaoManual,
    required this.aoCancelar,
    required this.aoSalvar,
  });

  @override
  State<_FormularioLevantamento> createState() =>
      _FormularioLevantamentoState();
}

class _FormularioLevantamentoState extends State<_FormularioLevantamento> {
  @override
  Widget build(BuildContext context) {
    final e = widget.edicao;
    final tema = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        CampoComSugestoes(
          controlador: e.sala,
          sugestoes: e.salas,
          rotulo: 'Sala atual',
          icone: Icons.room_outlined,
          ajuda: 'Em branco, a sala da planilha é mantida.',
          rotuloLimpar: 'Limpar a sala',
        ),
        const SizedBox(height: 16),
        CampoComSugestoes(
          controlador: e.responsavel,
          sugestoes: e.responsaveis,
          rotulo: 'Responsável atual',
          icone: Icons.person_outline,
          ajuda:
              'Em branco, o responsável da planilha é mantido. '
              'Pode ser um nome novo.',
          rotuloLimpar: 'Limpar o responsável',
        ),
        const SizedBox(height: 16),
        Text('Estado de conservação', style: tema.textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<EstadoConservacao>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: [
            for (final c in EstadoConservacao.values)
              ButtonSegment(value: c, label: Text(c.rotulo)),
          ],
          selected: {e.conservacao},
          onSelectionChanged: (s) => setState(() => e.conservacao = s.first),
        ),
        const SizedBox(height: 16),
        Text('Situação de uso', style: tema.textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<SituacaoUso>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: [
            for (final s in SituacaoUso.values)
              ButtonSegment(value: s, label: Text(s.rotulo)),
          ],
          selected: {e.situacao},
          onSelectionChanged: (s) => setState(() => e.situacao = s.first),
        ),
        if (widget.verificacaoManual) ...[
          const SizedBox(height: 12),
          Text(
            'Ao salvar, o item fica verificado por você, sem leitura de código.',
            style: tema.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: widget.aoCancelar,
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: widget.aoSalvar,
                icon: const Icon(Icons.check),
                label: const Text('Salvar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TituloSecao extends StatelessWidget {
  final String texto;

  const _TituloSecao(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(texto, style: Theme.of(context).textTheme.titleMedium),
    );
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

/// Linha do levantamento no tom do resultado: verde quando o valor confere
/// com a planilha (ou não foi alterado), laranja quando diverge.
///
/// Sempre com ícone e rótulo falado, como o resto do app: cor sozinha não
/// serve a quem tem daltonismo nem a quem usa leitor de tela.
class _CampoComTom extends StatelessWidget {
  final String rotulo;
  final String valor;

  /// Igual ao que veio da planilha.
  final bool igual;

  const _CampoComTom({
    required this.rotulo,
    required this.valor,
    required this.igual,
  });

  @override
  Widget build(BuildContext context) {
    final cores = CoresResultado.of(context);
    final tom = igual ? cores.registrado : cores.jaVerificado;
    final tema = Theme.of(context);

    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(rotulo, style: tema.textTheme.bodySmall),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: tom.fundo,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        igual ? Icons.check_circle_outline : Icons.swap_horiz,
                        size: 16,
                        color: tom.texto,
                        semanticLabel: igual
                            ? 'igual à planilha'
                            : 'diferente da planilha',
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          valor,
                          style: tema.textTheme.bodyMedium?.copyWith(
                            color: tom.texto,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
