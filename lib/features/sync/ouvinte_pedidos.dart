import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/repos/inventarios.dart';
import 'protocolo.dart';

/// Mostra o pedido de entrada por cima de qualquer tela.
///
/// O pedido chega quando chega: quem compartilhou pode estar no meio de um
/// levantamento, com a câmera aberta, ou na lista de inventários. Por isso o
/// aviso não é uma rota nem um `showDialog` de alguma tela — é uma camada
/// acima do `Navigator`, montada no `builder` do `MaterialApp.router`.
/// Assim ele aparece sobre qualquer rota, inclusive sobre outro diálogo, e
/// não depende de qual tela está aberta.
///
/// Só quem está com o aparelho autoriza a entrada: enquanto não houver um
/// "Aceitar", o outro lado não recebe a chave do inventário.
class OuvintePedidos extends ConsumerStatefulWidget {
  final Widget child;

  const OuvintePedidos({super.key, required this.child});

  @override
  ConsumerState<OuvintePedidos> createState() => _OuvintePedidosState();
}

class _OuvintePedidosState extends ConsumerState<OuvintePedidos> {
  StreamSubscription<PedidoEntrada>? _inscricao;

  /// Pedidos à espera de resposta, na ordem em que chegaram. Dois aparelhos
  /// pedindo ao mesmo tempo, num levantamento que começa, é caso comum.
  final _fila = <PedidoEntrada>[];

  /// Um prazo por pedido, e não um para a fila: cada um caduca na hora dele.
  final _prazos = <String, Timer>{};

  @override
  void initState() {
    super.initState();

    final servidor = ref.read(servidorSyncProvider);
    // Pedido que já estava pendurado quando esta camada montou: sem isto,
    // recriar a árvore (mudança de tema, por exemplo) engoliria o pedido.
    for (final pendente in servidor.pedidosPendentes) {
      _enfileirar(pendente);
    }
    _inscricao = servidor.pedidos.listen((pedido) {
      if (mounted) setState(() => _enfileirar(pedido));
    });
  }

  @override
  void dispose() {
    for (final prazo in _prazos.values) {
      prazo.cancel();
    }
    _inscricao?.cancel();
    super.dispose();
  }

  /// Põe o pedido na fila com o prazo dele.
  ///
  /// O servidor responde "expirou" sozinho, mas o diálogo continuaria na tela
  /// prometendo uma decisão que já não vale — e a pessoa tocaria em "Aceitar"
  /// sem efeito nenhum.
  void _enfileirar(PedidoEntrada pedido) {
    _fila.add(pedido);
    _prazos[pedido.token] = Timer(
      ref.read(servidorSyncProvider).validadePedido,
      () {
        if (mounted) setState(() => _tirar(pedido));
      },
    );
  }

  void _tirar(PedidoEntrada pedido) {
    _fila.remove(pedido);
    _prazos.remove(pedido.token)?.cancel();
  }

  void _responder(PedidoEntrada pedido, {required bool aceitar}) {
    ref
        .read(servidorSyncProvider)
        .responderPedido(pedido.token, aceitar: aceitar);
    setState(() => _tirar(pedido));
  }

  @override
  Widget build(BuildContext context) {
    final pedido = _fila.isEmpty ? null : _fila.first;

    return Stack(
      textDirection: TextDirection.ltr,
      // `expand`, e não o padrão: sem tamanho apertado, a árvore do aplicativo
      // — que é o primeiro filho — encolheria para o menor tamanho possível.
      fit: StackFit.expand,
      children: [
        widget.child,
        if (pedido != null)
          _AvisoPedido(
            pedido: pedido,
            inventario: ref
                .read(inventariosProvider)
                .porId(pedido.inventarioId),
            aoResponder: (aceitar) => _responder(pedido, aceitar: aceitar),
          ),
      ],
    );
  }
}

/// O diálogo de aceite, desenhado à mão porque não vive num `Navigator`.
class _AvisoPedido extends StatelessWidget {
  final PedidoEntrada pedido;
  final Inventario? inventario;
  final void Function(bool aceitar) aoResponder;

  const _AvisoPedido({
    required this.pedido,
    required this.inventario,
    required this.aoResponder,
  });

  @override
  Widget build(BuildContext context) {
    final titulo = inventario?.titulo ?? 'um inventário deste aparelho';
    final matricula = pedido.matricula?.trim();

    return Positioned.fill(
      child: Stack(
        children: [
          // Barreira não dispensável: entrar num inventário é decisão
          // explícita, e tocar fora não é nem "sim" nem "não".
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: AlertDialog(
              icon: const Icon(Icons.person_add_alt),
              title: const Text('Pedido de entrada'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${pedido.rotulo} quer entrar em $titulo.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (matricula != null && matricula.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Matrícula $matricula',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(
                    'Aceitando, o aparelho recebe a chave do inventário e '
                    'passa a sincronizar com este. Recuse se não reconhecer '
                    'quem está pedindo.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => aoResponder(false),
                  child: const Text('Recusar'),
                ),
                FilledButton(
                  onPressed: () => aoResponder(true),
                  child: const Text('Aceitar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
