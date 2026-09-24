import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/atualizacao.dart';
import '../../data/schema.dart';

/// Faixa que avisa quando há versão mais nova publicada.
///
/// Faixa, e não diálogo: o aplicativo é instalado por APK, fora da loja, e
/// nada mais avisaria quem está com uma versão antiga — mas quem está no meio
/// de um levantamento também não pode ser interrompido por uma caixa modal. A
/// faixa espera.
///
/// Enquanto a consulta não responde, e sempre que ela não tem o que dizer, o
/// widget não ocupa espaço nenhum.
class AvisoAtualizacao extends ConsumerStatefulWidget {
  const AvisoAtualizacao({super.key});

  @override
  ConsumerState<AvisoAtualizacao> createState() => _AvisoAtualizacaoState();
}

class _AvisoAtualizacaoState extends ConsumerState<AvisoAtualizacao> {
  AtualizacaoDisponivel? _nova;

  @override
  void initState() {
    super.initState();
    // Depois do primeiro quadro: a abertura não espera por rede. O
    // levantamento funciona sem internet por projeto, e uma verificação de
    // versão não é motivo para contradizer isso.
    WidgetsBinding.instance.addPostFrameCallback((_) => _verificar());
  }

  Future<void> _verificar() async {
    final banco = ref.read(bancoProvider);
    if (banco.lerConfig(Config.verificarAtualizacao) == '0') return;

    final nova = await ref.read(verificadorAtualizacaoProvider).verificar();
    if (nova == null || !mounted) return;

    // Quem já dispensou o aviso desta versão não o vê de novo a cada
    // abertura; a versão seguinte volta a avisar.
    if (banco.lerConfig(Config.atualizacaoDispensada) == nova.versao) return;

    setState(() => _nova = nova);
  }

  void _dispensar() {
    final nova = _nova;
    if (nova == null) return;
    ref
        .read(bancoProvider)
        .gravarConfig(Config.atualizacaoDispensada, nova.versao);
    setState(() => _nova = null);
  }

  Future<void> _abrir() async {
    final nova = _nova;
    if (nova == null) return;
    final aberto = await launchUrl(
      Uri.parse(nova.endereco),
      mode: LaunchMode.externalApplication,
    );
    if (!aberto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Abra ${nova.endereco} no navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final nova = _nova;
    if (nova == null) return const SizedBox.shrink();

    final tema = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: tema.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Row(
            children: [
              Icon(
                Icons.system_update_alt,
                color: tema.colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Versão ${nova.versao} disponível',
                      style: tema.textTheme.titleSmall?.copyWith(
                        color: tema.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      'Você está na $versaoApp. Instalar por cima mantém os '
                      'inventários.',
                      style: tema.textTheme.bodySmall?.copyWith(
                        color: tema.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: _abrir,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('Ver como'),
                  ),
                  TextButton(
                    onPressed: _dispensar,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: tema.colorScheme.onPrimaryContainer,
                    ),
                    child: const Text('Agora não'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
