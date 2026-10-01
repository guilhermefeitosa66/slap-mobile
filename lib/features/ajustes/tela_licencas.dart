import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app/componentes.dart';
import '../../core/atualizacao.dart';

/// Sob quais termos o SLAP Mobile pode ser usado, copiado e modificado.
///
/// A pergunta que traz alguém aqui é essa, e a tela padrão do Flutter
/// respondia outra: ela lista a licença de cada biblioteca — dezenas de itens
/// — e a do próprio aplicativo aparecia só como uma linha de rodapé no meio
/// delas. A ordem aqui é a inversa: primeiro a do aplicativo, depois, a um
/// toque, a lista de conformidade.
class TelaLicencas extends StatelessWidget {
  const TelaLicencas({super.key});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Licenças')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('SLAP Mobile', style: tema.textTheme.titleMedium),
                  Text('Versão $versaoApp', style: tema.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Text(
                    'Licença Apache 2.0',
                    style: tema.textTheme.titleSmall?.copyWith(
                      color: tema.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Software livre: qualquer pessoa ou instituição pode usar, '
                    'copiar, modificar e redistribuir o aplicativo, inclusive '
                    'para outros campi e outros órgãos, mantendo o aviso de '
                    'direitos autorais e esta licença.',
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const _TextoDaLicenca(),
                      ),
                    ),
                    icon: const Icon(Icons.article_outlined),
                    label: const Text('Ler a licença completa'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'O aplicativo usa software de outras pessoas, cada um com a sua '
            'licença.',
            style: tema.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          CartaoAgrupado(
            linhas: [
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Bibliotecas e fontes usadas'),
                subtitle: const Text('A licença de cada uma'),
                trailing: const SetaNavegacao(),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'SLAP Mobile',
                  applicationVersion: versaoApp,
                  applicationLegalese: 'Apache-2.0',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// O texto integral da licença, do arquivo `LICENSE` do repositório.
///
/// Vai embutido no aplicativo, e não buscado na internet: o levantamento é
/// feito em campus sem sinal, e uma licença que só abre com rede não é uma
/// licença disponível.
class _TextoDaLicenca extends StatelessWidget {
  const _TextoDaLicenca();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Apache License 2.0')),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('LICENSE'),
        builder: (context, instantaneo) {
          if (instantaneo.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Não foi possível abrir o texto da licença neste aparelho. '
                  'Ele está no arquivo LICENSE do repositório do projeto.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!instantaneo.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            // Monoespaçada e sem quebra automática de palavra: o texto vem
            // formatado em colunas, e reflui ilegível com fonte proporcional.
            child: SelectableText(
              instantaneo.data!,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          );
        },
      ),
    );
  }
}
