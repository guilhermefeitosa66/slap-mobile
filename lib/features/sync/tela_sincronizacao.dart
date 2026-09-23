import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import 'cliente.dart';
import 'compartilhar_inventario.dart';
import 'descoberta.dart';
import 'servidor.dart';

/// Sincronização com os outros aparelhos do inventário.
class TelaSincronizacao extends ConsumerStatefulWidget {
  final String inventarioId;

  const TelaSincronizacao({super.key, required this.inventarioId});

  @override
  ConsumerState<TelaSincronizacao> createState() => _TelaSincronizacaoState();
}

class _TelaSincronizacaoState extends ConsumerState<TelaSincronizacao> {
  Descoberta? _descoberta;
  List<Par> _pares = const [];
  final _sincronizando = <String>{};
  final _resultados = <String, String>{};

  /// Pares recusados por relógio, com a diferença medida. Sai daqui quando
  /// uma sincronização com o par passa.
  final _relogios = <String, RelogioDivergente>{};

  /// Alguém tentou sincronizar com este aparelho e foi recusado por relógio.
  EventoSync? _recusaRecebida;

  StreamSubscription<EventoSync>? _eventos;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _ligar();
  }

  @override
  void dispose() {
    _eventos?.cancel();
    _descoberta?.dispose();
    super.dispose();
  }

  Future<void> _ligar() async {
    final servidor = ref.read(servidorSyncProvider);
    final porta = await servidor.iniciar();

    // O que os outros enviam a este aparelho também precisa aparecer: os
    // números mudam, e uma recusa por relógio tem de ser explicada dos dois
    // lados, não só no aparelho que iniciou.
    _eventos = servidor.eventos
        .where((e) => e.inventarioId == widget.inventarioId)
        .listen(_aoReceber);

    final descoberta = Descoberta(
      dispositivoId: ref.read(bancoProvider).dispositivoId,
      usuarioNome: () => ref.read(identidadeProvider).nome,
      porta: porta,
    );

    descoberta.mudancas.listen((pares) {
      if (mounted) setState(() => _pares = pares);
    });

    await descoberta.iniciar();
    if (!mounted) return;

    setState(() {
      _descoberta = descoberta;
      _pares = descoberta.pares;
      _aviso = descoberta.avisos.isEmpty ? null : descoberta.avisos.join('\n');
    });
  }

  void _aoReceber(EventoSync evento) {
    if (!mounted) return;
    if (evento.recusadoPorRelogio) {
      setState(() => _recusaRecebida = evento);
      return;
    }
    if (evento.recebidas > 0) ref.read(revisaoProvider.notifier).mudou();
    if (_recusaRecebida?.dispositivoRemoto == evento.dispositivoRemoto) {
      setState(() => _recusaRecebida = null);
    }
  }

  String _rotuloDoDispositivo(String dispositivoId) {
    for (final par in _pares) {
      if (par.dispositivoId == dispositivoId) return par.rotulo;
    }
    return 'aparelho ${dispositivoId.substring(0, 6)}';
  }

  Future<void> _sincronizar(Par par) async {
    final inventario = ref.read(inventarioProvider(widget.inventarioId));
    if (inventario == null) return;

    setState(() => _sincronizando.add(par.dispositivoId));

    try {
      final resultado = await ref
          .read(clienteSyncProvider)
          .sincronizar(
            par: par,
            inventarioId: widget.inventarioId,
            chaveSync: inventario.chaveSync,
          );

      ref.read(revisaoProvider.notifier).mudou();

      if (!mounted) return;
      setState(() {
        _relogios.remove(par.dispositivoId);
        _resultados[par.dispositivoId] = resultado.houveTroca
            ? 'Recebidas ${resultado.recebidas}, enviadas ${resultado.enviadas}'
                  '${resultado.conflitos > 0 ? ' · ${resultado.conflitos} conflitos' : ''}'
            : 'Já estava tudo sincronizado';
      });
    } on RelogioDivergente catch (e) {
      if (mounted) {
        setState(() {
          _relogios[par.dispositivoId] = e;
          _resultados[par.dispositivoId] =
              'Relógios diferentes — nada foi trocado';
        });
      }
    } on FalhaSync catch (e) {
      if (mounted) {
        setState(() => _resultados[par.dispositivoId] = e.mensagem);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _resultados[par.dispositivoId] = 'Falhou: $e');
      }
    } finally {
      if (mounted) setState(() => _sincronizando.remove(par.dispositivoId));
    }
  }

  Future<void> _sincronizarTodos() async {
    for (final par in _pares) {
      await _sincronizar(par);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventario = ref.watch(inventarioProvider(widget.inventarioId));
    final conflitos = ref.watch(
      conflitosPendentesProvider(widget.inventarioId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sincronizar'),
        actions: [
          if (inventario != null)
            IconButton(
              tooltip: 'Compartilhar',
              icon: const Icon(Icons.qr_code_2),
              onPressed: () => mostrarQrDoInventario(context, inventario),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 112),
        children: [
          if (conflitos > 0)
            _AvisoConflitos(
              quantidade: conflitos,
              aoTocar: () =>
                  context.push('/inventario/${widget.inventarioId}/conflitos'),
            ),
          if (_recusaRecebida case final recusa?)
            _AvisoRelogio(
              aparelho: _rotuloDoDispositivo(recusa.dispositivoRemoto),
              diferenca: recusa.diferencaRelogio!,
            ),
          if (_aviso != null) _Orientacao(texto: _aviso!),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Aparelhos na rede',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 12),
              if (_descoberta == null)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_pares.isEmpty)
            const _NenhumPar()
          else
            for (final par in _pares) ...[
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  leading: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      par.origem == 'mdns'
                          ? Icons.wifi_tethering
                          : Icons.podcasts,
                      color: Theme.of(context).colorScheme.primary,
                      semanticLabel: par.origem == 'mdns'
                          ? 'Encontrado por mDNS'
                          : 'Encontrado pelo anúncio na rede',
                    ),
                  ),
                  title: Text(
                    par.rotulo,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    _resultados[par.dispositivoId] ?? par.endereco,
                  ),
                  trailing: _sincronizando.contains(par.dispositivoId)
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Sincronizar com ${par.rotulo}',
                          icon: const Icon(Icons.sync),
                          onPressed: () => _sincronizar(par),
                        ),
                  onTap: _sincronizando.contains(par.dispositivoId)
                      ? null
                      : () => _sincronizar(par),
                ),
              ),
              if (_relogios[par.dispositivoId] case final relogio?)
                _AvisoRelogio(
                  aparelho: relogio.aparelho,
                  diferenca: relogio.diferenca,
                ),
            ],
        ],
      ),
      floatingActionButton: _pares.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _sincronizando.isEmpty ? _sincronizarTodos : null,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar todos'),
            ),
    );
  }
}

class _AvisoConflitos extends StatelessWidget {
  final int quantidade;
  final VoidCallback aoTocar;

  const _AvisoConflitos({required this.quantidade, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final tom = CoresResultado.of(context).naoLocalizado;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: tom.fundo,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: tom.texto),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '$quantidade ${quantidade == 1 ? 'conflito' : 'conflitos'} '
                    'para conferir',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: tom.texto,
                      fontSize: 14,
                    ),
                  ),
                ),
                SetaNavegacao(cor: tom.texto),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Quadro de orientação, mais discreto que um cartão: não é ação, é contexto.
class _Orientacao extends StatelessWidget {
  final String texto;

  const _Orientacao({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CoresApoio.of(context).aviso,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// Relógios longe demais: qual aparelho, de quanto, e o que fazer.
///
/// Mostra as duas horas lado a lado. Não há como o aplicativo saber qual das
/// duas está certa — mas quem está com os aparelhos na mão sabe, olhando para
/// um relógio qualquer.
class _AvisoRelogio extends StatelessWidget {
  final String aparelho;
  final Duration diferenca;

  const _AvisoRelogio({required this.aparelho, required this.diferenca});

  @override
  Widget build(BuildContext context) {
    final tom = CoresResultado.of(context).naoLocalizado;
    final tema = Theme.of(context);
    final estilo = tema.textTheme.bodyMedium?.copyWith(color: tom.texto);
    final agora = DateTime.now();
    final hora = DateFormat('HH:mm');
    final data = DateFormat('dd/MM');
    final outro = agora.add(diferenca);
    final mesmoDia = DateUtils.isSameDay(agora, outro);
    String marca(DateTime t) =>
        mesmoDia ? hora.format(t) : '${data.format(t)} ${hora.format(t)}';

    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 2, bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tom.fundo,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: tom.texto, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Relógios fora de sincronia',
                    style: tema.textTheme.titleSmall?.copyWith(
                      color: tom.texto,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'O relógio de $aparelho está '
              '${descreverDuracao(diferenca.abs())} '
              '${diferenca.isNegative ? 'atrasado' : 'adiantado'} em relação '
              'a este aparelho. Nada foi trocado com ele.',
              style: estilo,
            ),
            const SizedBox(height: 8),
            Text('Este aparelho: ${marca(agora)}', style: estilo),
            Text('O outro: ${marca(outro)}', style: estilo),
            const SizedBox(height: 8),
            Text(
              'Nos dois aparelhos, abra Configurações → Sistema → Data e hora '
              'e ative a data e a hora automáticas. Depois, sincronize de novo.',
              style: estilo?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _NenhumPar extends StatelessWidget {
  const _NenhumPar();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.wifi_find,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            const Text(
              'Nenhum aparelho encontrado ainda.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Todos precisam estar na mesma rede Wi-Fi, com o aplicativo '
              'aberto nesta tela.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              // Isolamento de cliente é comum em rede institucional e não tem
              // solução em software: vale avisar em vez de deixar o usuário
              // procurando um defeito no aplicativo.
              'Algumas redes institucionais impedem que os aparelhos se vejam. '
              'Se a busca não achar ninguém, use o ponto de acesso de um dos '
              'celulares e conecte os demais a ele.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
