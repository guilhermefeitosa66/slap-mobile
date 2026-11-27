import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/componentes.dart';
import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import '../../data/copia_seguranca.dart';
import '../../data/repos/inventarios.dart';
import '../../domain/valores.dart';
import '../ajustes/copia_seguranca_ui.dart';

/// Troca de dados por arquivo, para a equipe que nunca está na mesma rede.
///
/// O arquivo é o mesmo `.slapcopia` da cópia de segurança, com um inventário
/// só, e receber é restaurar: as operações entram pelo mesmo caminho da troca
/// pela rede, com a detecção de conflito intacta, e nada é apagado. Quem não
/// tem o inventário recebe tudo (é o equivalente a entrar pelo QR code); quem
/// já tem recebe só o que falta. Cada arquivo leva tudo o que o aparelho
/// sabia, inclusive o que veio de outros, então a ordem não importa.
///
/// O arquivo leva a chave do inventário, como o QR code, e não passa pelo
/// pedido de entrada: quem o tiver entra. Por isso o aviso ao enviar.

/// Rótulos, os mesmos nas telas, no manual e nos testes.
const rotuloEnviarPorArquivo = 'Enviar por arquivo';
const rotuloEnviarArquivo = 'Enviar arquivo';
const rotuloReceberArquivo = 'Receber arquivo';

/// Rota da tela que recebe um arquivo. O caminho do arquivo vai em `extra`.
const rotaReceber = '/receber';

/// Tipo declarado ao compartilhar. Genérico de propósito: o WhatsApp e o
/// e-mail trocam tipos que não conhecem por este, e é por ele que o sistema
/// oferece o SLAP em "Abrir com".
const tipoDoArquivo = 'application/octet-stream';

/// O nome diz de quem é e de quando: quem junta os arquivos da equipe
/// reconhece cada um na conversa.
String nomeDoArquivo(Inventario inventario, String? autor, DateTime quando) =>
    '${['slap', _soLetras(inventario.titulo), if (autor != null && autor.trim().isNotEmpty) _soLetras(autor), DateFormat('yyyyMMdd-HHmm').format(quando)].join('-')}.${CopiaDeSeguranca.extensao}';

/// A mensagem que vai junto do arquivo: o arquivo chega solto numa conversa,
/// e quem recebe precisa saber o que fazer com ele.
String textoDoArquivo(Inventario inventario, String? autor) =>
    'Dados do inventário ${inventario.titulo} no SLAP Mobile'
    '${autor == null || autor.trim().isEmpty ? '' : ', de ${autor.trim()}'}.'
    '\n\nPara receber, abra este arquivo com o SLAP Mobile, ou no aplicativo '
    'use "$rotuloReceberArquivo". Nada é apagado: o que chega se junta ao que '
    'já está no aparelho.\n\nO arquivo dá acesso ao inventário: não '
    'encaminhe a quem não participa.';

/// Gera o arquivo do inventário e abre a folha de compartilhamento do
/// sistema (WhatsApp, e-mail, Drive...).
Future<void> enviarInventarioPorArquivo(
  BuildContext context,
  WidgetRef ref,
  Inventario inventario,
) async {
  final mensageiro = ScaffoldMessenger.of(context);
  final banco = ref.read(bancoProvider);
  final autor = ref.read(identidadeProvider).nome;

  final fechar = mostrarAndamento(context, 'Preparando o arquivo…');
  final String caminho;
  try {
    final bytes = await gerarCopia(banco, inventarioId: inventario.id);
    final pasta = await getTemporaryDirectory();
    caminho =
        '${pasta.path}/${nomeDoArquivo(inventario, autor, DateTime.now())}';
    await File(caminho).writeAsBytes(bytes);
  } catch (e) {
    fechar();
    mensageiro.showSnackBar(
      SnackBar(content: Text('Não foi possível gerar o arquivo: $e')),
    );
    return;
  }
  fechar();

  try {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(caminho, mimeType: tipoDoArquivo)],
        subject: 'SLAP Mobile: ${inventario.titulo}',
        text: textoDoArquivo(inventario, autor),
      ),
    );
  } finally {
    // A folha já entregou o arquivo (o share_plus guarda a cópia dele); este
    // não serve mais, e a cada envio sobraria um na pasta temporária.
    final arquivo = File(caminho);
    if (arquivo.existsSync()) await arquivo.delete();
  }
}

/// Escolhe um arquivo pelo seletor do sistema e abre a tela de recebimento.
Future<void> escolherArquivoParaReceber(BuildContext context) async {
  final escolhido = await FilePicker.pickFile(
    dialogTitle: 'Escolha o arquivo do SLAP',
  );
  if (escolhido == null || !context.mounted) return;

  // O SQLite precisa de um arquivo; o seletor entrega bytes.
  final pasta = await getTemporaryDirectory();
  final temporario = File(
    '${pasta.path}/recebido-${DateTime.now().microsecondsSinceEpoch}.db',
  );
  await temporario.writeAsBytes(await escolhido.readAsBytes());
  if (!context.mounted) return;
  await context.push(rotaReceber, extra: temporario.path);
}

/// Arquivos abertos de fora do aplicativo ("Abrir com" no WhatsApp, no
/// gerenciador de arquivos, no Mail).
///
/// O lado nativo copia o arquivo para a pasta temporária do aplicativo e
/// entrega o caminho: por [pendente], quando o aplicativo foi aberto pelo
/// arquivo, ou pelo método `recebido`, quando já estava aberto.
class ArquivosRecebidos {
  static const canal = MethodChannel('slap/recebidos');

  final _chegadas = StreamController<String>.broadcast();

  Stream<String> get chegadas => _chegadas.stream;

  ArquivosRecebidos() {
    canal.setMethodCallHandler((chamada) async {
      if (chamada.method == 'recebido' && chamada.arguments is String) {
        _chegadas.add(chamada.arguments as String);
      }
    });
  }

  /// O arquivo que abriu o aplicativo, se foi isso. Entregue uma vez só.
  Future<String?> pendente() async {
    try {
      return await canal.invokeMethod<String>('pendente');
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('arquivo recebido não lido: $e');
      return null;
    }
  }
}

/// Mostra o que o arquivo traz e, confirmado, junta ao que está no aparelho.
class TelaReceberArquivo extends ConsumerStatefulWidget {
  /// Arquivo temporário, criado pelo aplicativo: apagado ao sair da tela.
  final String? caminho;

  const TelaReceberArquivo({super.key, required this.caminho});

  @override
  ConsumerState<TelaReceberArquivo> createState() => _TelaReceberArquivoState();
}

class _TelaReceberArquivoState extends ConsumerState<TelaReceberArquivo> {
  ResumoCopia? _resumo;
  String? _erro;
  bool _recebendo = false;
  ResultadoRestauracao? _resultado;

  @override
  void initState() {
    super.initState();
    final caminho = widget.caminho;
    if (caminho == null || !File(caminho).existsSync()) {
      _erro = 'O arquivo não chegou ao aplicativo. Tente abrir de novo.';
      return;
    }
    try {
      _resumo = CopiaDeSeguranca.ler(
        caminho,
        comparadoCom: ref.read(bancoProvider),
      );
      if (_resumo!.inventarios.isEmpty) {
        _erro = 'O arquivo não traz nenhum inventário.';
      }
    } on CopiaInvalida catch (e) {
      _erro = e.mensagem;
    } catch (_) {
      _erro =
          'Este arquivo não é do SLAP Mobile. Peça a quem mandou para usar '
          '"$rotuloEnviarPorArquivo", no compartilhar do inventário.';
    }
  }

  @override
  void dispose() {
    final caminho = widget.caminho;
    if (caminho != null) {
      final arquivo = File(caminho);
      if (arquivo.existsSync()) {
        try {
          arquivo.deleteSync();
        } catch (_) {}
      }
    }
    super.dispose();
  }

  Future<void> _receber() async {
    setState(() => _recebendo = true);
    try {
      final resultado = await aplicarCopia(
        ref.read(bancoProvider),
        widget.caminho!,
      );
      ref.read(revisaoProvider.notifier).mudou();
      if (mounted) setState(() => _resultado = resultado);
    } catch (e) {
      if (mounted) {
        setState(() => _erro = '$e\n\nNada foi alterado neste aparelho.');
      }
    } finally {
      if (mounted) setState(() => _recebendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(rotuloReceberArquivo)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_erro != null)
            _Erro(texto: _erro!)
          else if (_resultado != null)
            _Recebido(resumo: _resumo!, resultado: _resultado!)
          else
            _Previa(
              resumo: _resumo!,
              recebendo: _recebendo,
              aoReceber: _receber,
            ),
        ],
      ),
    );
  }
}

String _deQuem(ResumoCopia resumo) => [
  if (resumo.autor != null && resumo.autor!.trim().isNotEmpty)
    'de ${resumo.autor!.trim()}',
  if (resumo.criadaEm != null) descreverMomento(resumo.criadaEm!),
].join(', ');

class _Previa extends StatelessWidget {
  final ResumoCopia resumo;
  final bool recebendo;
  final VoidCallback aoReceber;

  const _Previa({
    required this.resumo,
    required this.recebendo,
    required this.aoReceber,
  });

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final deQuem = _deQuem(resumo);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          deQuem.isEmpty ? 'Arquivo do SLAP Mobile' : 'Arquivo $deQuem',
          style: tema.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final inv in resumo.inventarios)
          Card(
            child: ListTile(
              leading: Icon(
                inv.jaExiste ? Icons.merge_type : Icons.add_circle_outline,
                color: tema.colorScheme.primary,
              ),
              title: Text('${inv.nome} — ${inv.ano}'),
              subtitle: Text(
                '${formatarInteiro(inv.itens)} '
                '${inv.itens == 1 ? 'item' : 'itens'} · '
                '${inv.jaExiste ? 'já está neste aparelho: entra só o que falta' : 'novo neste aparelho'}',
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          'Nada é apagado: o que o arquivo traz e este aparelho não tem entra, '
          'e o resto fica como está. Se você e quem mandou mudaram o mesmo '
          'item, o aplicativo avisa o conflito para você decidir.',
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: recebendo ? null : aoReceber,
          icon: recebendo
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_done),
          label: Text(recebendo ? 'Recebendo…' : 'Receber'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
        ),
      ],
    );
  }
}

class _Recebido extends StatelessWidget {
  final ResumoCopia resumo;
  final ResultadoRestauracao resultado;

  const _Recebido({required this.resumo, required this.resultado});

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final unico = resumo.inventarios.length == 1
        ? resumo.inventarios.single
        : null;
    final alteracoes = resultado.operacoes;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: tema.colorScheme.primary,
        ),
        const SizedBox(height: 12),
        Text(
          'Dados recebidos',
          style: tema.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        for (final inv in resumo.inventarios)
          Text(
            '• ${inv.nome} — ${inv.ano}: '
            '${inv.jaExiste ? 'atualizado' : 'novo neste aparelho'}',
          ),
        const SizedBox(height: 8),
        Text(
          alteracoes == 0
              ? 'Nada de novo: este aparelho já tinha tudo o que o arquivo traz.'
              : '${formatarInteiro(alteracoes)} '
                    '${alteracoes == 1 ? 'alteração recebida' : 'alterações recebidas'}.',
        ),
        if (resultado.conflitos > 0) ...[
          const SizedBox(height: 16),
          CaixaDeAviso(
            texto:
                '${resultado.conflitos} '
                '${resultado.conflitos == 1 ? 'conflito' : 'conflitos'} para '
                'conferir: o mesmo item mudado aqui e no outro aparelho.',
            tom: CoresResultado.of(context).jaVerificado,
          ),
          if (unico != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.go('/inventario/${unico.id}/conflitos'),
              child: const Text('Ver conflitos'),
            ),
          ],
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () =>
              context.go(unico == null ? '/' : '/inventario/${unico.id}'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
          child: Text(unico == null ? 'Ver inventários' : 'Abrir o inventário'),
        ),
      ],
    );
  }
}

class _Erro extends StatelessWidget {
  final String texto;

  const _Erro({required this.texto});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaixaDeAviso(texto: texto),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          child: const Text('Voltar'),
        ),
      ],
    );
  }
}

/// Cartão "Sem rede em comum?", na tela de troca de dados.
class CartaoTrocaPorArquivo extends ConsumerWidget {
  final Inventario inventario;

  const CartaoTrocaPorArquivo({super.key, required this.inventario});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sem rede em comum?', style: tema.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Mande o que você levantou num arquivo, por WhatsApp ou e-mail, e '
              'receba o dos colegas. O que chega se junta ao que já está aqui.',
              style: tema.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      enviarInventarioPorArquivo(context, ref, inventario),
                  icon: const Icon(Icons.ios_share),
                  label: const Text(rotuloEnviarArquivo),
                ),
                OutlinedButton.icon(
                  onPressed: () => escolherArquivoParaReceber(context),
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text(rotuloReceberArquivo),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _soLetras(String texto) => formaComparavel(
  texto,
).replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
