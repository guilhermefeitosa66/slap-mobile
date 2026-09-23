import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app.dart';
import '../../app/providers.dart';
import '../../core/sons.dart';
import '../../data/repos/patrimonios.dart';
import '../../domain/patrimonio.dart';
import 'configuracao_sheet.dart';
import 'estado_levantamento.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _garantirConfiguracao(),
    );
  }

  @override
  void dispose() {
    _campo.dispose();
    _foco.dispose();
    super.dispose();
  }

  /// Sem sala definida não há o que aplicar às leituras, então a configuração
  /// aparece antes da tela ficar utilizável.
  Future<void> _garantirConfiguracao() async {
    if (ref.read(configuracaoProvider(widget.inventarioId)) != null) {
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

  /// Devolve o foco ao campo depois de cada leitura.
  ///
  /// É o que permite o leitor externo funcionar em fluxo contínuo: o aparelho
  /// se comporta como teclado, e sem o foco de volta a leitura seguinte se
  /// perderia.
  void _devolverFoco() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_foco);
  }

  Future<void> _processar(String codigo) async {
    final texto = codigo.trim();
    _campo.clear();

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
    final config = ref.watch(configuracaoProvider(widget.inventarioId));
    final modo = ref.watch(modoLeituraProvider);
    final historico = ref.watch(historicoProvider(widget.inventarioId));
    final progresso = ref.watch(progressoProvider(widget.inventarioId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Levantamento'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${progresso.verificados}/${progresso.total}',
                style: Theme.of(context).textTheme.titleMedium,
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
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
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
                    style: const TextStyle(fontSize: 22, letterSpacing: 1.5),
                    decoration: InputDecoration(
                      hintText: modo.rotulo,
                      prefixIcon: const Icon(Icons.keyboard),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: () => _processar(_campo.text),
                      ),
                    ),
                    onSubmitted: _processar,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 56,
                  width: 56,
                  child: FilledButton(
                    onPressed: _abrirCamera,
                    style: FilledButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(56, 56),
                    ),
                    child: const Icon(Icons.photo_camera),
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
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => LinhaLeitura(registro: historico[i]),
                  ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: SegmentedButton<ModoLeitura>(
        segments: const [
          ButtonSegment(
            value: ModoLeitura.codigoBarras,
            icon: Icon(Icons.barcode_reader),
            label: Text('Cód. barras'),
          ),
          ButtonSegment(
            value: ModoLeitura.tombo,
            icon: Icon(Icons.tag),
            label: Text('Tombo'),
          ),
        ],
        selected: {modo},
        onSelectionChanged: (s) => aoMudar(s.first),
      ),
    );
  }
}

/// Uma leitura da sessão, com o resultado destacado.
class LinhaLeitura extends StatelessWidget {
  final LeituraRegistrada registro;

  const LinhaLeitura({super.key, required this.registro});

  @override
  Widget build(BuildContext context) {
    final (cor, icone, rotulo) = switch (registro.resultado) {
      ResultadoLeitura.sucesso => (
        CoresResultado.sucesso,
        Icons.check_circle,
        'Registrado',
      ),
      ResultadoLeitura.jaVerificado => (
        CoresResultado.alerta,
        Icons.replay_circle_filled,
        'Já verificado',
      ),
      ResultadoLeitura.naoLocalizado => (
        CoresResultado.erro,
        Icons.error,
        'Não localizado',
      ),
    };

    final p = registro.patrimonio;

    return ListTile(
      dense: true,
      leading: Icon(icone, color: cor),
      title: Text(
        p?.descricao ?? 'Código ${registro.codigoLido}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            p == null
                ? rotulo
                : 'Tombo ${p.tombo} · $rotulo'
                      '${p.verificadoPor == null ? '' : ' por ${p.verificadoPor}'}',
            style: TextStyle(color: cor),
          ),
          if (registro.leitura.achadoNoOutroCampo)
            const Text(
              'Encontrado no outro campo — cadastro inconsistente',
              style: TextStyle(fontSize: 11),
            ),
          if (registro.leitura.temDuplicados)
            Text(
              '${registro.leitura.duplicados} itens com este código',
              style: const TextStyle(fontSize: 11),
            ),
          if (p != null && p.ignorado)
            const Text(
              'Este item está fora do inventário (ED excluído)',
              style: TextStyle(fontSize: 11),
            ),
        ],
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
    return Container(
      width: double.infinity,
      color: CoresResultado.alerta.withValues(alpha: 0.12),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tombo ${patrimonio.tombo} já foi verificado'
            '${patrimonio.verificadoPor == null ? '' : ' por ${patrimonio.verificadoPor}'}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (patrimonio.salaAtual != null)
            Text('Registrado em: ${patrimonio.salaAtual}'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: aoCancelar,
                  child: const Text('Manter'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: aoConfirmar,
                  style: FilledButton.styleFrom(
                    backgroundColor: CoresResultado.alerta,
                    minimumSize: const Size.fromHeight(44),
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
            Icon(
              Icons.barcode_reader,
              size: 56,
              color: Theme.of(context).colorScheme.outline,
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
