import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/componentes.dart';
import '../../app/preferencias.dart';
import '../../app/providers.dart';
import 'copia_seguranca_ui.dart';

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
          secao('Aparência'),
          CartaoAgrupado(
            linhas: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ListTile(
                    leading: Icon(Icons.brightness_6_outlined),
                    title: Text('Tema'),
                    subtitle: Text(
                      '"Sistema" acompanha o modo claro ou escuro do celular.',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SegmentedButton<Tema>(
                      showSelectedIcon: false,
                      expandedInsets: EdgeInsets.zero,
                      segments: [
                        for (final opcao in Tema.values)
                          ButtonSegment(
                            value: opcao,
                            label: Text(opcao.rotulo),
                          ),
                      ],
                      selected: {preferencias.tema},
                      onSelectionChanged: (s) => controlador.tema(s.first),
                    ),
                  ),
                ],
              ),
            ],
          ),
          secao('Cópia de segurança'),
          CartaoAgrupado(
            linhas: [
              ListTile(
                leading: const Icon(Icons.save_alt),
                title: const Text('Exportar cópia'),
                subtitle: const Text(
                  'Todos os inventários deste aparelho, num arquivo que você '
                  'guarda onde quiser.',
                ),
                trailing: const SetaNavegacao(),
                onTap: () => exportarCopia(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('Restaurar de uma cópia'),
                subtitle: const Text(
                  'Traz o que a cópia tem para este aparelho, sem apagar nada.',
                ),
                trailing: const SetaNavegacao(),
                onTap: () => restaurarCopia(context, ref),
              ),
            ],
          ),
          secao('Identidade do aparelho'),
          CartaoAgrupado(
            linhas: [
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Gerar nova identidade'),
                subtitle: const Text(
                  'Só quando a sincronização disser que outro aparelho está '
                  'usando a identidade deste.',
                ),
                trailing: const SetaNavegacao(),
                onTap: () => _renovarIdentidade(context, ref),
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

Future<void> _renovarIdentidade(BuildContext context, WidgetRef ref) async {
  final esquema = Theme.of(context).colorScheme;
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (contexto) => AlertDialog(
      title: const Text('Gerar nova identidade?'),
      content: const Text(
        'Use só quando a sincronização avisar que outro aparelho está usando '
        'a identidade deste — o que acontece quando os dados do aplicativo são '
        'copiados de um celular para outro.\n\n'
        'Todos os inventários deste aparelho serão apagados. Depois, entre de '
        'novo em cada um pelo QR code: o que os outros aparelhos têm volta. O '
        'que foi feito aqui e ainda não chegou a nenhum outro se perde.\n\n'
        'Seu nome, matrícula e ajustes ficam.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(contexto, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(contexto, true),
          style: FilledButton.styleFrom(
            backgroundColor: esquema.error,
            foregroundColor: esquema.onError,
            minimumSize: const Size(0, 48),
          ),
          child: const Text('Gerar e apagar'),
        ),
      ],
    ),
  );
  if (confirmou != true || !context.mounted) return;

  ref.read(inventariosProvider).renovarIdentidade();
  ref.read(revisaoProvider.notifier).mudou();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Identidade nova. Entre nos inventários pelo QR code.'),
    ),
  );
}
