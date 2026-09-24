import 'package:flutter/material.dart';

import '../../domain/valores.dart';

/// Campo de texto livre com sugestões, para sala e responsável.
///
/// O SLAP só deixa escolher um valor que já exista na planilha, o que impede
/// inventariar num ambiente novo, corrigir um nome errado ou atribuir um bem
/// a um servidor recém-chegado — que é justamente quem mais precisa aparecer
/// no levantamento. Aqui o texto é livre e a lista só sugere; o valor final é
/// o que está em [controlador].
///
/// O controlador e o foco são deste campo, não os que o [Autocomplete]
/// criaria por conta própria. Registrar um ouvinte no controlador interno
/// dentro do `fieldViewBuilder` empilhava um ouvinte novo a cada
/// reconstrução; com o controlador vindo de fora, não há ouvinte nenhum a
/// registrar.
class CampoComSugestoes extends StatefulWidget {
  /// Quantas sugestões aparecem de cada vez. A lista de salas de um campus
  /// passa de cem; mostrar todas cobriria a tela sem ajudar a escolher.
  static const maximoSugestoes = 20;

  final TextEditingController controlador;
  final List<String> sugestoes;
  final String rotulo;
  final IconData? icone;
  final String? ajuda;

  /// Rótulo do botão que esvazia o campo, dito pelo leitor de tela. Sem ele,
  /// não há botão.
  final String? rotuloLimpar;

  final bool autofoco;
  final TextCapitalization capitalizacao;

  const CampoComSugestoes({
    super.key,
    required this.controlador,
    required this.sugestoes,
    required this.rotulo,
    this.icone,
    this.ajuda,
    this.rotuloLimpar,
    this.autofoco = false,
    this.capitalizacao = TextCapitalization.words,
  });

  @override
  State<CampoComSugestoes> createState() => _CampoComSugestoesState();
}

class _CampoComSugestoesState extends State<CampoComSugestoes> {
  final _foco = FocusNode();

  @override
  void dispose() {
    _foco.dispose();
    super.dispose();
  }

  /// Sugestões que contêm o texto digitado, sem caixa nem acento: "ti" acha
  /// "Coordenação de TI". Campo vazio mostra as primeiras.
  Iterable<String> _sugerir(TextEditingValue valor) {
    final busca = formaComparavel(valor.text);
    if (busca.isEmpty) {
      return widget.sugestoes.take(CampoComSugestoes.maximoSugestoes);
    }
    return widget.sugestoes
        .where((s) => formaComparavel(s).contains(busca))
        .take(CampoComSugestoes.maximoSugestoes);
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      textEditingController: widget.controlador,
      focusNode: _foco,
      optionsBuilder: _sugerir,
      // Sem `onSubmitted`: concluir no teclado com sugestões abertas
      // trocaria o nome novo digitado pela primeira sugestão da lista.
      fieldViewBuilder: (context, controlador, foco, _) {
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: controlador,
          builder: (context, valor, _) => TextField(
            controller: controlador,
            focusNode: foco,
            autofocus: widget.autofoco,
            textCapitalization: widget.capitalizacao,
            decoration: InputDecoration(
              labelText: widget.rotulo,
              prefixIcon: widget.icone == null ? null : Icon(widget.icone),
              helperText: widget.ajuda,
              helperMaxLines: 3,
              suffixIcon: widget.rotuloLimpar == null || valor.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: widget.rotuloLimpar,
                      icon: const Icon(Icons.clear),
                      onPressed: controlador.clear,
                    ),
            ),
          ),
        );
      },
    );
  }
}
