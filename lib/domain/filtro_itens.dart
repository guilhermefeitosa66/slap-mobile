import 'valores.dart';

/// Campo pelo qual a lista de itens pode ser filtrada.
///
/// A ordem é a da folha de filtros e a das fichas que resumem o que está
/// ativo — planilha e levantamento em pares, para que a diferença entre os
/// dois fique visível na hora de escolher.
enum CampoFiltro {
  sala('Sala (planilha)'),
  salaAtual('Sala atual'),
  responsavel('Responsável (planilha)'),
  responsavelAtual('Responsável atual'),
  conservacao('Estado de conservação'),
  situacao('Situação de uso'),
  verificadoPor('Verificado por');

  final String rotulo;
  const CampoFiltro(this.rotulo);

  /// O campo só tem valor em item encontrado no levantamento.
  ///
  /// Estado, situação e autor da verificação nascem da leitura: item não
  /// localizado não tem nenhum dos três. Filtrar por eles é, na prática,
  /// pedir só itens verificados.
  bool get exigeVerificado =>
      this == conservacao || this == situacao || this == verificadoPor;
}

/// O que a lista de itens está mostrando, além da classificação e da busca.
///
/// Campo nulo é "qualquer valor". Os filtros se combinam entre si — todos
/// precisam casar — e com a classificação e a busca da tela.
///
/// **Sala atual e responsável atual usam o valor efetivo**
/// (`COALESCE(sala_atual, sala_original)`, o mesmo de
/// `Patrimonio.salaEfetiva`), e não a coluna crua. O levantamento só grava
/// `sala_atual` quando a sala muda; filtrar pela coluna crua responderia
/// "quais itens mudaram para esta sala", que é quase sempre a pergunta
/// errada. Quem filtra por sala atual quer saber **o que está nesta sala
/// agora**, incluindo o que nunca saiu do lugar.
class FiltroItens {
  /// Nada filtrado.
  static const nenhum = FiltroItens();

  /// `sala_original`: o que a planilha do SUAP diz.
  final String? sala;

  /// Onde o item está agora — o valor efetivo.
  final String? salaAtual;

  /// `responsavel_original`.
  final String? responsavel;

  /// De quem o item é agora — o valor efetivo.
  final String? responsavelAtual;

  final EstadoConservacao? conservacao;
  final SituacaoUso? situacao;

  /// Nome de quem registrou a verificação. Útil depois de sincronizar, para
  /// conferir o que cada pessoa levantou.
  final String? verificadoPor;

  const FiltroItens({
    this.sala,
    this.salaAtual,
    this.responsavel,
    this.responsavelAtual,
    this.conservacao,
    this.situacao,
    this.verificadoPor,
  });

  /// Valor escolhido em [campo], já no texto que vai para a tela.
  String? valorDe(CampoFiltro campo) => switch (campo) {
    CampoFiltro.sala => sala,
    CampoFiltro.salaAtual => salaAtual,
    CampoFiltro.responsavel => responsavel,
    CampoFiltro.responsavelAtual => responsavelAtual,
    CampoFiltro.conservacao => conservacao?.rotulo,
    CampoFiltro.situacao => situacao?.rotulo,
    CampoFiltro.verificadoPor => verificadoPor,
  };

  /// Os campos preenchidos, na ordem de [CampoFiltro].
  Map<CampoFiltro, String> get ativos => {
    for (final campo in CampoFiltro.values) campo: ?valorDe(campo),
  };

  int get quantidade => ativos.length;

  bool get algumAtivo => quantidade > 0;

  /// Verdadeiro quando algum campo escolhido só existe em item verificado.
  ///
  /// É o que permite explicar uma lista vazia em vez de deixá-la parecer
  /// defeito: combinado com "Não localizado", nenhum item pode casar.
  bool get exigeVerificado => ativos.keys.any((c) => c.exigeVerificado);

  /// O mesmo filtro, sem [campo]. É o que a ficha de cada filtro remove.
  FiltroItens sem(CampoFiltro campo) => FiltroItens(
    sala: campo == CampoFiltro.sala ? null : sala,
    salaAtual: campo == CampoFiltro.salaAtual ? null : salaAtual,
    responsavel: campo == CampoFiltro.responsavel ? null : responsavel,
    responsavelAtual: campo == CampoFiltro.responsavelAtual
        ? null
        : responsavelAtual,
    conservacao: campo == CampoFiltro.conservacao ? null : conservacao,
    situacao: campo == CampoFiltro.situacao ? null : situacao,
    verificadoPor: campo == CampoFiltro.verificadoPor ? null : verificadoPor,
  );
}
