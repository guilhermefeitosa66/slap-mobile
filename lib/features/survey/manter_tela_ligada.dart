import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/preferencias.dart';
import '../../core/tela_ligada.dart';

/// Mantém a tela ligada enquanto [child] estiver montado.
///
/// Envolve o levantamento e a câmera. Sai da árvore ao sair da tela, e a
/// liberação acontece no `dispose` — sem exceção, qualquer que seja o caminho
/// de saída. Quem desligou a preferência não é atendido.
class ManterTelaLigada extends ConsumerStatefulWidget {
  final Widget child;

  const ManterTelaLigada({super.key, required this.child});

  @override
  ConsumerState<ManterTelaLigada> createState() => _ManterTelaLigadaState();
}

class _ManterTelaLigadaState extends ConsumerState<ManterTelaLigada> {
  bool _pedido = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(preferenciasProvider).manterTelaLigada) {
      _pedido = true;
      unawaited(TelaLigada.instancia.pedir());
    }
  }

  @override
  void dispose() {
    if (_pedido) unawaited(TelaLigada.instancia.liberar());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
