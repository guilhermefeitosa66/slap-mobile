import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/componentes.dart';
import '../../app/preferencias.dart';
import '../../app/providers.dart';
import '../../core/atualizacao.dart';
import '../../core/formato.dart';
import '../../data/repos/operacoes.dart';
import 'copia_seguranca_ui.dart';
import 'tela_licencas.dart';

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
          secao('Atualizações'),
          CartaoAgrupado(
            linhas: [
              SwitchListTile(
                secondary: const Icon(Icons.system_update_alt),
                title: const Text('Avisar de versão nova'),
                subtitle: const Text(
                  'Ao abrir, pergunta ao GitHub qual é a última versão. Não '
                  'envia nada do inventário.',
                ),
                value: preferencias.verificarAtualizacao,
                onChanged: controlador.verificarAtualizacao,
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
          secao('Este aparelho'),
          CartaoAgrupado(
            linhas: [
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Apagar tudo deste aparelho'),
                subtitle: const Text(
                  'Todos os inventários. Seu nome, ajustes e a identidade do '
                  'aparelho ficam.',
                ),
                trailing: const SetaNavegacao(),
                onTap: () => _apagarTudo(context, ref),
              ),
              ListTile(
                leading: const Icon(Icons.fingerprint),
                title: const Text('Separar este aparelho de uma cópia'),
                subtitle: const Text(
                  'Quando a sincronização recusa dizendo que outro aparelho '
                  'está usando a identidade deste.',
                ),
                trailing: const SetaNavegacao(),
                onTap: () => _separarDeUmaCopia(context, ref),
              ),
            ],
          ),
          secao('Sobre'),
          CartaoAgrupado(
            linhas: [
              // A versão instalada, à mão: é o que se pergunta a quem relata
              // um problema, e o que se compara com a release publicada.
              const ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Versão do aplicativo'),
                subtitle: Text(versaoApp),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Licenças'),
                subtitle: const Text('Do aplicativo e do que ele usa'),
                trailing: const SetaNavegacao(),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TelaLicencas()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Quantos inventários o aparelho tem e o que se perde apagando todos.
///
/// A soma é por aparelho porque a pergunta é por aparelho: uma contagem por
/// inventário não responde "o que eu perco limpando este celular".
({int inventarios, TrabalhoNaoEntregue perda}) _perdaDoAparelho(WidgetRef ref) {
  final inventarios = ref.read(inventariosProvider).listar();
  final operacoes = ref.read(operacoesProvider);

  return (
    inventarios: inventarios.length,
    perda: inventarios
        .map((i) => operacoes.trabalhoNaoEntregue(i.id))
        .fold(TrabalhoNaoEntregue.nenhum, (a, b) => a + b),
  );
}

/// O trabalho que se perde, em números.
///
/// Verificações quando houver — é o que a pessoa reconhece como o seu dia de
/// trabalho. Quando o que ficou aqui foi só editar, resolver conflito ou
/// desfazer, fala-se em alterações: "0 verificações" não diria nada.
String _trabalho(TrabalhoNaoEntregue perda) {
  if (perda.verificacoes > 0) {
    return perda.verificacoes == 1
        ? '1 verificação'
        : '${formatarInteiro(perda.verificacoes)} verificações';
  }
  return perda.operacoes == 1
      ? '1 alteração'
      : '${formatarInteiro(perda.operacoes)} alterações';
}

/// A frase do aviso em destaque: quantos inventários saem e quanto trabalho
/// vai com eles.
String _frasePerda(int inventarios, TrabalhoNaoEntregue perda) {
  final quantos = inventarios == 1
      ? 'O inventário deste aparelho será apagado'
      : 'Os ${formatarInteiro(inventarios)} inventários deste aparelho serão '
            'apagados';

  if (perda.nada) {
    return '$quantos. Tudo o que foi feito aqui já está em outro aparelho.';
  }

  final um =
      (perda.verificacoes > 0 ? perda.verificacoes : perda.operacoes) == 1;
  final feitas = um ? 'feita' : 'feitas';
  final perdem = um ? 'se perde' : 'se perdem';

  return perda.jaSincronizou
      ? '$quantos, e ${_trabalho(perda)} $feitas aqui ainda não '
            '${um ? 'chegou' : 'chegaram'} a nenhum outro aparelho: $perdem.'
      : '$quantos, e ${_trabalho(perda)} $feitas aqui $perdem para sempre — '
            'este aparelho nunca sincronizou.';
}

enum _EscolhaApagar { exportar, apagar }

/// Limpa o aparelho, dizendo antes o que se perde e oferecendo a cópia.
///
/// Existe como ação própria porque quem queria isto — terminou o levantamento,
/// vai devolver o celular — acabava usando a troca de identidade por engano:
/// ela apaga tudo, mas com outro nome e outro propósito.
Future<void> _apagarTudo(BuildContext context, WidgetRef ref) async {
  while (true) {
    final (:inventarios, :perda) = _perdaDoAparelho(ref);
    if (!context.mounted) return;

    if (inventarios == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não há nenhum inventário neste aparelho.'),
        ),
      );
      return;
    }

    final escolha = await showDialog<_EscolhaApagar>(
      context: context,
      builder: (contexto) {
        final esquema = Theme.of(contexto).colorScheme;
        return AlertDialog(
          title: const Text('Apagar tudo deste aparelho?'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CaixaDeAviso(texto: _frasePerda(inventarios, perda)),
                const SizedBox(height: 16),
                const Text(
                  'Os outros aparelhos não são afetados: cada um tem a sua '
                  'própria cópia, e sincronizar com eles traz o inventário de '
                  'volta.\n\n'
                  'Seu nome, matrícula, ajustes e a identidade deste aparelho '
                  'ficam.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(contexto),
              child: const Text('Cancelar'),
            ),
            // A cópia oferecida no caminho: quem vai limpar o aparelho pode
            // querer o arquivo antes, e aqui é mais provável que aceite do
            // que lembrando depois.
            TextButton(
              onPressed: () => Navigator.pop(contexto, _EscolhaApagar.exportar),
              child: const Text('Exportar cópia'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(contexto, _EscolhaApagar.apagar),
              style: FilledButton.styleFrom(
                backgroundColor: esquema.error,
                foregroundColor: esquema.onError,
                minimumSize: const Size(0, 48),
              ),
              child: Text(perda.nada ? 'Apagar tudo' : 'Apagar mesmo assim'),
            ),
          ],
        );
      },
    );

    if (!context.mounted) return;
    if (escolha == _EscolhaApagar.exportar) {
      await exportarCopia(context, ref);
      // Volta a perguntar, agora com a cópia na mão.
      continue;
    }
    if (escolha != _EscolhaApagar.apagar) return;

    ref.read(inventariosProvider).apagarTudoLocalmente();
    ref.read(revisaoProvider.notifier).mudou();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Inventários apagados deste aparelho.')),
    );
    return;
  }
}

/// Dá a este aparelho uma identidade própria, quando ele e uma cópia sua
/// estão escrevendo com a mesma.
///
/// Chamava-se "gerar nova identidade". Apresentado a um usuário, o nome não
/// comunicou nada — identidade de quê? Aqui se diz o fim, separar este
/// aparelho de uma cópia; o mecanismo fica para o texto.
Future<void> _separarDeUmaCopia(BuildContext context, WidgetRef ref) async {
  final (:inventarios, :perda) = _perdaDoAparelho(ref);
  if (!context.mounted) return;

  final confirmou = await showDialog<bool>(
    context: context,
    builder: (contexto) {
      final esquema = Theme.of(contexto).colorScheme;
      return AlertDialog(
        title: const Text('Separar de uma cópia?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (inventarios > 0) ...[
                CaixaDeAviso(texto: _frasePerda(inventarios, perda)),
                const SizedBox(height: 16),
              ],
              const Text(
                'Use só quando a sincronização recusar dizendo que outro '
                'aparelho está usando a identidade deste — o que acontece '
                'quando os dados do aplicativo são copiados de um celular '
                'para outro.\n\n'
                'Este aparelho passa a ter identidade própria. Depois, entre '
                'de novo em cada inventário pelo QR code: o que os outros '
                'aparelhos têm volta. Seu nome, matrícula e ajustes ficam.',
              ),
              if (!perda.nada) ...[
                const SizedBox(height: 12),
                Text(
                  'Se a sincronização com algum outro aparelho ainda '
                  'funcionar, faça antes: é o que salva esse trabalho.',
                  style: Theme.of(contexto).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
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
            child: Text(inventarios == 0 ? 'Separar' : 'Apagar e separar'),
          ),
        ],
      );
    },
  );
  if (confirmou != true || !context.mounted) return;

  ref.read(inventariosProvider).renovarIdentidade();
  ref.read(revisaoProvider.notifier).mudou();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Identidade própria gerada. Entre nos inventários pelo QR code.',
      ),
    ),
  );
}
