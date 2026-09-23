import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/componentes.dart';
import '../../app/preferencias.dart';
import '../../app/providers.dart';

/// Quem usa este aparelho e como ele se comporta no levantamento.
///
/// Tudo aqui é do aparelho, não do inventário: nada sincroniza.
class TelaAjustes extends ConsumerWidget {
  const TelaAjustes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identidade = ref.watch(identidadeProvider);
    final preferencias = ref.watch(preferenciasProvider);
    final controlador = ref.read(preferenciasProvider.notifier);
    final tema = Theme.of(context);

    Widget secao(String titulo) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(titulo.toUpperCase(), style: tema.textTheme.labelMedium),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          secao('Você'),
          CartaoAgrupado(
            linhas: [
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(identidade.nome ?? 'Sem nome'),
                subtitle: Text(
                  identidade.matricula == null
                      ? 'Sem matrícula'
                      : 'Matrícula ${identidade.matricula}',
                ),
                trailing: const SetaNavegacao(),
                onTap: () => context.push('/identidade?inicial=false'),
              ),
            ],
          ),
          secao('Levantamento'),
          CartaoAgrupado(
            linhas: [
              SwitchListTile(
                secondary: const Icon(Icons.light_mode_outlined),
                title: const Text('Manter a tela ligada'),
                subtitle: const Text(
                  'Durante o levantamento e com a câmera aberta. Nas outras '
                  'telas o bloqueio segue normal.',
                ),
                value: preferencias.manterTelaLigada,
                onChanged: controlador.manterTelaLigada,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_outlined),
                title: const Text('Som a cada leitura'),
                subtitle: const Text(
                  'Um som diferente para registrado, já verificado e não '
                  'localizado.',
                ),
                value: preferencias.sons,
                onChanged: controlador.sons,
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration),
                title: const Text('Vibrar a cada leitura'),
                subtitle: const Text(
                  'Útil em biblioteca e sala de aula, com o som desligado.',
                ),
                value: preferencias.vibracao,
                onChanged: controlador.vibracao,
              ),
            ],
          ),
          secao('Sobre'),
          CartaoAgrupado(
            linhas: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Licenças'),
                subtitle: const Text('Bibliotecas e fontes usadas'),
                trailing: const SetaNavegacao(),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'SLAP Inventário',
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
