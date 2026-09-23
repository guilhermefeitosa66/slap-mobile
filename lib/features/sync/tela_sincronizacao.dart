import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import 'cliente.dart';
import 'compartilhar_inventario.dart';
import 'descoberta.dart';

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
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _ligar();
  }

  @override
  void dispose() {
    _descoberta?.dispose();
    super.dispose();
  }

  Future<void> _ligar() async {
    final servidor = ref.read(servidorSyncProvider);
    final porta = await servidor.iniciar();

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
        _resultados[par.dispositivoId] = resultado.houveTroca
            ? 'Recebidas ${resultado.recebidas}, enviadas ${resultado.enviadas}'
                  '${resultado.conflitos > 0 ? ' · ${resultado.conflitos} conflitos' : ''}'
            : 'Já estava tudo sincronizado';
      });
    } on FalhaSync catch (e) {
      if (mounted) {
        setState(() => _resultados[par.dispositivoId] = e.mensagem);
      }
    } catch (e) {
      if (mounted)
        setState(() => _resultados[par.dispositivoId] = 'Falhou: $e');
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
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          if (conflitos > 0)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded),
                title: Text('$conflitos conflitos para conferir'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(
                  '/inventario/${widget.inventarioId}/conflitos',
                ),
              ),
            ),
          if (_aviso != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _aviso!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
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
            for (final par in _pares)
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      par.origem == 'mdns'
                          ? Icons.wifi_tethering
                          : Icons.podcasts,
                    ),
                  ),
                  title: Text(par.rotulo),
                  subtitle: Text(
                    _resultados[par.dispositivoId] ?? par.endereco,
                  ),
                  trailing: _sincronizando.contains(par.dispositivoId)
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          icon: const Icon(Icons.sync),
                          onPressed: () => _sincronizar(par),
                        ),
                  onTap: _sincronizando.contains(par.dispositivoId)
                      ? null
                      : () => _sincronizar(par),
                ),
              ),
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
