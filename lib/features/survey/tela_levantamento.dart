import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import '../../data/banco.dart';
import '../../core/sons.dart';
import '../../data/repos/patrimonios.dart';
import '../../data/schema.dart';
import '../../domain/patrimonio.dart';
import 'configuracao_sheet.dart';
import 'estado_levantamento.dart';
import 'linha_leitura.dart';
import 'manter_tela_ligada.dart';
import 'tela_camera.dart';

/// A tela do levantamento.
///
/// É o caminho quente do aplicativo e a razão de várias decisões de
/// arquitetura. O objetivo é o mínimo de interação por patrimônio: com um
/// leitor externo, o ciclo completo — ler, localizar, aplicar a configuração,
/// gravar e dar retorno sonoro — acontece sem nenhum toque na tela.
class TelaLevantamento extends ConsumerStatefulWidget {
  final String inventarioId;

  const TelaLevantamento({super.key, required this.inventarioId});

  @override
  ConsumerState<TelaLevantamento> createState() => _TelaLevantamentoState();
}

class _TelaLevantamentoState extends ConsumerState<TelaLevantamento> {
  final _campo = TextEditingController();
  final _foco = FocusNode();

  /// Item encontrado já verificado, aguardando confirmação para sobrescrever.
  ///
  /// O SLAP também não sobrescreve em silêncio, e preservar isso é importante:
  /// a releitura acidental é comum, e sobrescrever sem avisar apagaria a
  /// informação de quem verificou antes.
  Patrimonio? _aguardandoConfirmacao;

  /// Guardado na abertura: no `dispose` o `ref` já não pode ser usado.
  late final Banco _banco;

  @override
  void initState() {
    super.initState();
    // Se o Android encerrar o aplicativo com o levantamento aberto — com a
    // câmera, em aparelho com pouca memória, é comum —, ele reabre aqui.
    _banco = ref.read(bancoProvider)
      ..gravarConfig(Config.levantamentoAberto, widget.inventarioId);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _garantirConfiguracao(),
    );
  }

  @override
  void dispose() {
    // Saída normal: da próxima vez o aplicativo abre na lista.
    _banco.apagarConfig(Config.levantamentoAberto);
    _campo.dispose();
    _foco.dispose();
    super.dispose();
  }

  /// Sem sala definida não há o que aplicar às leituras, então a configuração
  /// aparece antes da tela ficar utilizável.
  ///
  /// Com sala definida, mas sem leitura há horas, a sala é confirmada antes:
  /// quem volta no dia seguinte provavelmente está em outro lugar.
  Future<void> _garantirConfiguracao() async {
    // Encerrado, a tela só explica o bloqueio: não há sala a configurar.
    if (_encerrado) return;

    final atual = ref.read(configuracaoProvider(widget.inventarioId));
    if (atual != null) {
      final ultima = ref
          .read(operacoesProvider)
          .ultimaEscritaLocal(widget.inventarioId);
      if (precisaConfirmarSala(
        config: atual,
        ultimaLeitura: ultima,
        agora: DateTime.now(),
      )) {
        await _confirmarSala(atual, ultima);
      }
      _devolverFoco();
      return;
    }

    final config = await abrirConfiguracao(context, ref, widget.inventarioId);
    if (!mounted) return;

    if (config == null) {
      Navigator.of(context).pop();
      return;
    }
    _devolverFoco();
  }

  Future<void> _confirmarSala(
    ConfiguracaoLevantamento config,
    DateTime? ultima,
  ) async {
    final referencia = ultima ?? config.desde;
    final continuar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (contexto) => AlertDialog(
        title: Text('Ainda em ${config.sala}?'),
        content: Text(
          '${referencia == null ? 'Faz tempo que nada é lido neste aparelho.' : 'A última leitura neste aparelho foi ${descreverMomento(referencia)}.'} '
          'Confirme a sala antes de continuar: a sala errada vai para todos '
          'os itens lidos em seguida.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(contexto, false),
            child: const Text('Mudar de sala'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(contexto, true),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            child: Text('Continuar em ${config.sala}'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (continuar == true) {
      ref.read(configuracoesProvider.notifier).reconfirmar(widget.inventarioId);
    } else {
      await abrirConfiguracao(context, ref, widget.inventarioId);
    }
  }

  /// Devolve o foco ao campo depois de cada leitura.
  ///
  /// É o que permite o leitor externo funcionar em fluxo contínuo: o aparelho
  /// se comporta como teclado, e sem o foco de volta a leitura seguinte se
  /// perderia.
  void _devolverFoco() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_foco);
  }

  /// O inventário foi encerrado — aqui ou em outro aparelho, chegando por
  /// sincronização com a tela aberta.
  bool get _encerrado =>
      ref.read(inventarioProvider(widget.inventarioId))?.encerrado ?? false;

  Future<void> _processar(String codigo) async {
    final texto = codigo.trim();
    _campo.clear();
    if (_encerrado) return;

    if (texto.isEmpty) {
      _devolverFoco();
      return;
    }

    final config = ref.read(configuracaoProvider(widget.inventarioId));
    if (config == null) {
      await _garantirConfiguracao();
      return;
    }

    final repo = ref.read(patrimoniosProvider);
    final modo = ref.read(modoLeituraProvider);

    final leitura = repo.procurar(
      inventarioId: widget.inventarioId,
      codigo: texto,
      modo: modo,
    );

    switch (leitura.resultado) {
      case ResultadoLeitura.naoLocalizado:
        await ref.read(sonsProvider).tocar(Som.naoLocalizado);
        _registrar(LeituraRegistrada(leitura: leitura, codigoLido: texto));

      case ResultadoLeitura.jaVerificado:
        await ref.read(sonsProvider).tocar(Som.jaVerificado);
        setState(() => _aguardandoConfirmacao = leitura.patrimonio);
        _registrar(LeituraRegistrada(leitura: leitura, codigoLido: texto));

      case ResultadoLeitura.sucesso:
        final depois = _gravar(leitura.patrimonio!, config);
        await ref.read(sonsProvider).tocar(Som.sucesso);
        _registrar(
          LeituraRegistrada(
            leitura: leitura,
            codigoLido: texto,
            depois: depois,
          ),
        );
    }

    _devolverFoco();
  }

  Patrimonio _gravar(Patrimonio patrimonio, ConfiguracaoLevantamento config) {
    final identidade = ref.read(identidadeProvider);
    final atualizado = ref
        .read(patrimoniosProvider)
        .registrarVerificacao(
          patrimonio: patrimonio,
          config: config,
          usuarioNome: identidade.nome,
          usuarioMatricula: identidade.matricula,
        );
    ref.read(revisaoProvider.notifier).mudou();
    return atualizado;
  }

  void _registrar(LeituraRegistrada leitura) {
    ref
        .read(historicosProvider.notifier)
        .registrar(widget.inventarioId, leitura);
    if (leitura.resultado != ResultadoLeitura.jaVerificado) {
      setState(() => _aguardandoConfirmacao = null);
    }
  }

  Future<void> _confirmarSobrescrita() async {
    final patrimonio = _aguardandoConfirmacao;
    final config = ref.read(configuracaoProvider(widget.inventarioId));
    if (patrimonio == null || config == null) return;

    final depois = _gravar(patrimonio, config);
    await ref.read(sonsProvider).tocar(Som.sucesso);

    setState(() => _aguardandoConfirmacao = null);
    ref
        .read(historicosProvider.notifier)
        .registrar(
          widget.inventarioId,

          LeituraRegistrada(
            leitura: Leitura(
              resultado: ResultadoLeitura.sucesso,
              patrimonio: patrimonio,
            ),
            codigoLido: patrimonio.tombo,
            depois: depois,
          ),
        );
    _devolverFoco();
  }

  Future<void> _abrirCamera() async {
    final config = ref.read(configuracaoProvider(widget.inventarioId));
    if (config == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TelaCamera(inventarioId: widget.inventarioId),
      ),
    );
    if (mounted) _devolverFoco();
  }

  @override
  Widget build(BuildContext context) {
    final inventario = ref.watch(inventarioProvider(widget.inventarioId));
    if (inventario?.encerrado ?? false) {
      return const LevantamentoEncerrado();
    }

    final config = ref.watch(configuracaoProvider(widget.inventarioId));
    final modo = ref.watch(modoLeituraProvider);
    final historico = ref.watch(historicoProvider(widget.inventarioId));
    final progresso = ref.watch(progressoProvider(widget.inventarioId));

    return ManterTelaLigada(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Levantamento'),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Semantics(
                  label:
                      '${progresso.verificados} de ${progresso.total} verificados',
                  excludeSemantics: true,
                  child: Text.rich(
                    TextSpan(
                      text: formatarInteiro(progresso.verificados),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      children: [
                        TextSpan(
                          text: '/${formatarInteiro(progresso.total)}',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            if (config != null)
              BarraConfiguracao(
                config: config,
                aoTocar: () async {
                  await abrirConfiguracao(context, ref, widget.inventarioId);
                  _devolverFoco();
                },
              ),
            _SeletorModo(
              modo: modo,
              aoMudar: (novo) {
                ref.read(modoLeituraProvider.notifier).definir(novo);
                _devolverFoco();
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _campo,
                      focusNode: _foco,
                      autofocus: true,
                      // O teclado numérico cobre a digitação manual de tombo, e
                      // o leitor externo entra como teclado de qualquer forma.
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.go,
                      style: estiloCodigo(
                        context,
                        tamanho: 22,
                      ).copyWith(letterSpacing: 0.9),
                      decoration: InputDecoration(
                        hintText: modo.rotulo,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Theme.of(context).colorScheme.primary,
                            width: 2,
                          ),
                        ),
                        suffixIcon: IconButton(
                          tooltip: 'Procurar',
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: () => _processar(_campo.text),
                        ),
                      ),
                      onSubmitted: _processar,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 56,
                    width: 56,
                    child: Tooltip(
                      message: 'Abrir câmera',
                      child: FilledButton(
                        onPressed: _abrirCamera,
                        style: FilledButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(56, 56),
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          size: 26,
                          semanticLabel: 'Abrir câmera',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_aguardandoConfirmacao != null)
              _ConfirmarSobrescrita(
                patrimonio: _aguardandoConfirmacao!,
                aoConfirmar: _confirmarSobrescrita,
                aoCancelar: () {
                  setState(() => _aguardandoConfirmacao = null);
                  _devolverFoco();
                },
              ),
            const Divider(height: 1),
            Expanded(
              child: historico.isEmpty
                  ? const _Instrucoes()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: historico.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 50),
                      itemBuilder: (_, i) =>
                          LinhaLeitura(registro: historico[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeletorModo extends StatelessWidget {
  final ModoLeitura modo;
  final ValueChanged<ModoLeitura> aoMudar;

  const _SeletorModo({required this.modo, required this.aoMudar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ModoLeitura>(
          showSelectedIcon: false,
          expandedInsets: EdgeInsets.zero,
          segments: const [
            ButtonSegment(
              value: ModoLeitura.codigoBarras,
              icon: IconeCodigoBarras(tamanho: 18),
              label: Text('Cód. barras'),
            ),
            ButtonSegment(
              value: ModoLeitura.tombo,
              icon: Icon(Icons.tag, size: 18),
              label: Text('Tombo'),
            ),
          ],
          selected: {modo},
          onSelectionChanged: (s) => aoMudar(s.first),
        ),
      ),
    );
  }
}

class _ConfirmarSobrescrita extends StatelessWidget {
  final Patrimonio patrimonio;
  final VoidCallback aoConfirmar;
  final VoidCallback aoCancelar;

  const _ConfirmarSobrescrita({
    required this.patrimonio,
    required this.aoConfirmar,
    required this.aoCancelar,
  });

  @override
  Widget build(BuildContext context) {
    final tom = CoresResultado.of(context).jaVerificado;
    final tema = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tom.fundo,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tombo ${patrimonio.tombo} já foi verificado'
            '${patrimonio.verificadoPor == null ? '' : ' por ${patrimonio.verificadoPor}'}',
            style: tema.textTheme.titleSmall?.copyWith(
              color: tom.texto,
              fontSize: 14,
            ),
          ),
          if (patrimonio.salaAtual != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Registrado em: ${patrimonio.salaAtual}',
                style: tema.textTheme.bodyMedium?.copyWith(
                  color: tom.texto,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: aoCancelar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tom.texto,
                    side: BorderSide(
                      color: tom.texto.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                  ),
                  child: const Text('Manter'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: aoConfirmar,
                  style: FilledButton.styleFrom(
                    backgroundColor: tom.texto,
                    foregroundColor: tom.fundo,
                    minimumSize: const Size.fromHeight(alvoMinimo),
                  ),
                  child: const Text('Regravar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Instrucoes extends StatelessWidget {
  const _Instrucoes();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconeCodigoBarras(
              tamanho: 56,
              cor: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            const Text(
              'Leia um patrimônio com o leitor externo, digite o número ou '
              'use a câmera.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'A configuração acima é aplicada automaticamente a cada leitura.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Atalho de teclado físico para reabrir a configuração sem sair do campo.
class AtalhoConfiguracao extends Intent {
  const AtalhoConfiguracao();
}

final atalhosLevantamento = <ShortcutActivator, Intent>{
  LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
      const AtalhoConfiguracao(),
};

/// O inventário está encerrado: nada a ler, e o porquê.
///
/// Usado pelo levantamento e pela câmera. Sai da árvore o campo de leitura e
/// a câmera, e com eles o pedido de tela ligada.
class LevantamentoEncerrado extends StatelessWidget {
  const LevantamentoEncerrado({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Levantamento')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 56,
                color: tema.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'Inventário encerrado',
                style: tema.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Nenhuma leitura é gravada enquanto ele estiver encerrado. '
                'Para continuar o levantamento, reabra o inventário no painel.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Voltar ao painel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
