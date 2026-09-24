import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import '../../data/repos/patrimonios.dart';
import '../../domain/valores.dart';
import 'campo_com_sugestoes.dart';
import 'estado_levantamento.dart';

/// Abre a configuração que será aplicada às próximas leituras.
///
/// Devolve a configuração escolhida, ou `null` se o usuário desistiu.
Future<ConfiguracaoLevantamento?> abrirConfiguracao(
  BuildContext context,
  WidgetRef ref,
  String inventarioId,
) async {
  final repo = ref.read(patrimoniosProvider);

  final escolhida = await showModalBottomSheet<ConfiguracaoLevantamento>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FolhaConfiguracao(
      inicial: ref.read(configuracaoProvider(inventarioId)),
      salas: repo.salas(inventarioId),
      responsaveis: repo.responsaveis(inventarioId),
    ),
  );

  if (escolhida != null) {
    ref.read(configuracoesProvider.notifier).definir(inventarioId, escolhida);
  }
  return escolhida;
}

class _FolhaConfiguracao extends StatefulWidget {
  final ConfiguracaoLevantamento? inicial;
  final List<String> salas;
  final List<String> responsaveis;

  const _FolhaConfiguracao({
    required this.salas,
    required this.responsaveis,
    this.inicial,
  });

  @override
  State<_FolhaConfiguracao> createState() => _FolhaConfiguracaoState();
}

class _FolhaConfiguracaoState extends State<_FolhaConfiguracao> {
  late final TextEditingController _sala = TextEditingController(
    text: widget.inicial?.sala ?? '',
  );
  late EstadoConservacao _conservacao =
      widget.inicial?.conservacao ?? EstadoConservacao.bom;
  late SituacaoUso _situacao = widget.inicial?.situacao ?? SituacaoUso.ativo;
  late final TextEditingController _responsavel = TextEditingController(
    text: widget.inicial?.responsavel ?? '',
  );

  @override
  void dispose() {
    _sala.dispose();
    _responsavel.dispose();
    super.dispose();
  }

  void _confirmar() {
    final sala = _sala.text.trim();
    if (sala.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe a sala onde você está.')),
      );
      return;
    }

    // Responsável em branco é "não alterar": o que veio do SUAP permanece,
    // como no `before_save` do SLAP.
    final responsavel = _responsavel.text.trim();

    Navigator.pop(
      context,
      ConfiguracaoLevantamento(
        sala: sala,
        conservacao: _conservacao,
        situacao: _situacao,
        responsavel: responsavel.isEmpty ? null : responsavel,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Aplicar às próximas leituras',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Estes valores são gravados em cada patrimônio que você ler, '
              'até que você os altere.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),

            // Texto livre com sugestões: o SLAP só permite escolher uma sala
            // que já exista na planilha, o que impede inventariar num ambiente
            // novo ou corrigir um nome errado.
            CampoComSugestoes(
              controlador: _sala,
              sugestoes: widget.salas,
              rotulo: 'Sala onde você está',
              icone: Icons.room_outlined,
              ajuda: 'Pode ser um nome novo, que não esteja na planilha.',
              autofoco: widget.inicial == null,
            ),
            const SizedBox(height: 20),

            const _Rotulo('Estado de conservação'),
            const SizedBox(height: 8),
            SegmentedButton<EstadoConservacao>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: [
                for (final e in EstadoConservacao.values)
                  ButtonSegment(value: e, label: Text(e.rotulo)),
              ],
              selected: {_conservacao},
              onSelectionChanged: (s) => setState(() => _conservacao = s.first),
            ),
            const SizedBox(height: 20),

            const _Rotulo('Situação de uso'),
            const SizedBox(height: 8),
            SegmentedButton<SituacaoUso>(
              showSelectedIcon: false,
              expandedInsets: EdgeInsets.zero,
              segments: [
                for (final s in SituacaoUso.values)
                  ButtonSegment(value: s, label: Text(s.rotulo)),
              ],
              selected: {_situacao},
              onSelectionChanged: (s) => setState(() => _situacao = s.first),
            ),
            const SizedBox(height: 20),

            // Também texto livre: a lista do SUAP é legada, e um servidor
            // novo, que ainda não tem patrimônio na carga, não está nela.
            CampoComSugestoes(
              controlador: _responsavel,
              sugestoes: widget.responsaveis,
              rotulo: 'Responsável',
              icone: Icons.person_outline,
              ajuda:
                  'Em branco, o responsável da planilha é mantido. '
                  'Pode ser um nome novo.',
              rotuloLimpar: 'Limpar o responsável',
            ),
            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _confirmar,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Aplicar e continuar'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Rotulo extends StatelessWidget {
  final String texto;
  const _Rotulo(this.texto);

  @override
  Widget build(BuildContext context) =>
      Text(texto, style: Theme.of(context).textTheme.labelLarge);
}

/// Faixa fixa no topo do levantamento, com a configuração corrente.
///
/// Fica sempre visível porque enganar-se aqui contamina todos os itens lidos
/// em seguida — e a correção depois exige achar quais foram.
class BarraConfiguracao extends StatelessWidget {
  final ConfiguracaoLevantamento config;
  final VoidCallback aoTocar;

  const BarraConfiguracao({
    super.key,
    required this.config,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    final apoio = CoresApoio.of(context);
    final detalhe =
        '${config.conservacao.rotulo} · ${config.situacao.rotulo} · '
        '${config.responsavel ?? 'responsável não alterado'}';

    return Semantics(
      button: true,
      label:
          'Configuração das leituras: sala ${config.sala}, $detalhe. '
          'Toque para alterar.',
      excludeSemantics: true,
      child: Material(
        color: apoio.faixa,
        child: InkWell(
          onTap: aoTocar,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                Icon(Icons.place_outlined, color: apoio.sobreFaixa),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            flex: 3,
                            child: Text(
                              config.sala,
                              style: TextStyle(
                                fontFamily: familiaTitulos,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: apoio.sobreFaixa,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (config.desde case final desde?) ...[
                            const SizedBox(width: 8),
                            // A sala tem prioridade: com fonte grande, o
                            // "desde" encolhe antes dela.
                            Flexible(
                              flex: 2,
                              child: Text(
                                descreverDesde(desde),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: apoio.sobreFaixaSecundario,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        detalhe,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: apoio.sobreFaixaSecundario,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 20,
                  color: apoio.sobreFaixaSecundario,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
