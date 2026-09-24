import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/tema.dart';
import '../../core/atualizacao.dart';
import 'estado_atualizacao.dart';

/// Faixa que avisa quando há versão mais nova publicada.
///
/// Faixa, e não diálogo: o aplicativo é instalado por APK, fora da loja, e
/// nada mais avisaria quem está com uma versão antiga — mas quem está no meio
/// de um levantamento também não pode ser interrompido por uma caixa modal. A
/// faixa espera.
///
/// Em laranja, o tom que o aplicativo usa para "pare e olhe": é um aviso, e
/// não uma informação a mais. Com ícone e texto junto da cor, como manda o
/// resto da interface — cor sozinha não serve a quem tem daltonismo.
///
/// Sem nada a avisar, o widget não ocupa espaço nenhum.
class AvisoAtualizacao extends ConsumerWidget {
  const AvisoAtualizacao({super.key});

  Future<void> _abrir(BuildContext context, AtualizacaoDisponivel nova) async {
    final aberto = await launchUrl(
      Uri.parse(nova.endereco),
      mode: LaunchMode.externalApplication,
    );
    if (!aberto && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Abra ${nova.endereco} no navegador.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estadoAtualizacaoProvider);
    final nova = estado.nova;
    if (!estado.aAvisar || nova == null) return const SizedBox.shrink();

    final tema = Theme.of(context);
    final tom = CoresResultado.of(context).jaVerificado;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Material(
        color: tom.fundo,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.system_update_alt, color: tom.texto),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Versão ${nova.versao} disponível',
                      style: tema.textTheme.titleSmall?.copyWith(
                        color: tom.texto,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Você está na $versaoApp. Instalar por cima mantém os '
                'inventários.',
                style: tema.textTheme.bodySmall?.copyWith(color: tom.texto),
              ),
              const SizedBox(height: 12),
              // Empilhados, e não lado a lado: em tela estreita o rótulo do
              // botão principal quebrava em duas linhas ao dividir a largura
              // com o "Agora não".
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _abrir(context, nova),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  // Diz o que a pessoa quer fazer, e não o que a tela faz. O
                  // toque abre a página que explica como instalar — o arquivo
                  // não baixa sozinho, e o ícone diz isso.
                  label: const Text('Baixar nova versão'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: tom.texto,
                    foregroundColor: tom.fundo,
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      ref.read(estadoAtualizacaoProvider.notifier).dispensar(),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    foregroundColor: tom.texto,
                  ),
                  child: const Text('Agora não'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A versão instalada, no pé da lista de inventários.
///
/// Discreta de propósito: é informação de conferência, não de operação. Só
/// diz "atualizado" depois de ter conferido — afirmar que está tudo em dia
/// sem ter perguntado é pior que não dizer nada.
class VersaoInstalada extends ConsumerWidget {
  const VersaoInstalada({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(estadoAtualizacaoProvider);
    // O estilo da linha de identidade logo acima: discreto pelo tamanho, e
    // não por uma cor apagada — a auditoria de acessibilidade recusa texto
    // pequeno com pouco contraste, e está certa.
    final estilo = Theme.of(context).textTheme.bodySmall;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Versão $versaoApp', style: estilo),
        if (estado.emDia) ...[
          const SizedBox(width: 6),
          Icon(Icons.check_circle_outline, size: 14, color: estilo?.color),
          const SizedBox(width: 3),
          Text('atualizado', style: estilo),
        ],
      ],
    );
  }
}
