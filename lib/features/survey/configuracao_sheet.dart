import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/tema.dart';
import '../../core/formato.dart';
import '../../data/repos/patrimonios.dart';
import '../../domain/valores.dart';
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
  late String? _responsavel = widget.inicial?.responsavel;

  @override
  void dispose() {
    _sala.dispose();
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

    Navigator.pop(
      context,
      ConfiguracaoLevantamento(
        sala: sala,
        conservacao: _conservacao,
        situacao: _situacao,
        responsavel: _responsavel,
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
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _sala.text),
              optionsBuilder: (valor) {
                final busca = formaComparavel(valor.text);
                if (busca.isEmpty) return widget.salas.take(20);
                return widget.salas
                    .where((s) => formaComparavel(s).contains(busca))
                    .take(20);
              },
              onSelected: (s) => _sala.text = s,
              fieldViewBuilder: (context, controlador, foco, _) {
                controlador.addListener(() => _sala.text = controlador.text);
                return TextField(
                  controller: controlador,
                  focusNode: foco,
                  autofocus: widget.inicial == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Sala onde você está',
                    prefixIcon: Icon(Icons.room_outlined),
                    helperText:
                        'Pode ser um nome novo, que não esteja na planilha.',
                    helperMaxLines: 2,
                  ),
                );
              },
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

            const _Rotulo('Responsável'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              initialValue: _responsavel,
              isExpanded: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_outline),
              ),
              items: [
                // Nulo mantém o responsável que veio do SUAP, que é a regra do
                // SLAP: não informar um novo não esvazia o campo.
                const DropdownMenuItem(
                  value: null,
                  child: Text('Não alterar o responsável'),
                ),
                for (final r in widget.responsaveis)
                  DropdownMenuItem(
                    value: r,
                    child: Text(r, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _responsavel = v),
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
                            Text(
                              descreverDesde(desde),
                              style: TextStyle(
                                fontSize: 12,
                                color: apoio.sobreFaixaSecundario,
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
