import 'patrimonio.dart';
import 'valores.dart';

/// Campo em que o inventário encontrou valor diferente do cadastro do SUAP.
enum CampoDivergente {
  sala('Sala'),
  responsavel('Responsável'),
  conservacao('Estado de conservação'),
  situacao('Situação de uso');

  final String rotulo;
  const CampoDivergente(this.rotulo);
}

/// Uma diferença concreta entre o cadastro e o que foi encontrado.
class Divergencia {
  final CampoDivergente campo;
  final String? valorSuap;
  final String? valorEncontrado;

  const Divergencia(this.campo, this.valorSuap, this.valorEncontrado);
}

/// Resultado final do inventário para um item — os três grupos da
/// especificação, mais os itens que ficaram fora do processo.
enum Classificacao {
  /// Encontrado e igual ao cadastro. Não precisa de alteração no SUAP.
  ok('OK'),

  /// Encontrado, mas com pelo menos um campo diferente do cadastro.
  divergente('Divergente'),

  /// Estava na planilha e não foi encontrado durante o inventário.
  naoLocalizado('Não localizado'),

  /// ED excluído do inventário. Fora dos relatórios e do progresso.
  ignorado('Ignorado');

  final String rotulo;
  const Classificacao(this.rotulo);
}

/// Lista as diferenças entre o cadastro do SUAP e o que foi levantado.
///
/// Só faz sentido para item verificado: um item não encontrado não tem valor
/// levantado com que comparar.
///
/// Estado de conservação e situação de uso só entram quando a planilha
/// importada trouxe o valor de origem. A exportação padrão do SUAP não traz
/// esses campos, e sem valor anterior não existe divergência — existe apenas
/// informação nova. Inventar uma divergência aí encheria o relatório de linhas
/// em que a coluna "valor SUAP" viria vazia, sem nada para conferir.
List<Divergencia> divergenciasDe(Patrimonio p) {
  if (!p.verificado || p.ignorado) return const [];

  final divergencias = <Divergencia>[];

  if (!mesmoTexto(p.salaOriginal, p.salaEfetiva)) {
    divergencias.add(Divergencia(
      CampoDivergente.sala,
      p.salaOriginal,
      p.salaEfetiva,
    ));
  }

  if (!mesmoTexto(p.responsavelOriginal, p.responsavelEfetivo)) {
    divergencias.add(Divergencia(
      CampoDivergente.responsavel,
      p.responsavelOriginal,
      p.responsavelEfetivo,
    ));
  }

  if (p.conservacaoOriginal != null &&
      p.conservacao != null &&
      p.conservacaoOriginal != p.conservacao) {
    divergencias.add(Divergencia(
      CampoDivergente.conservacao,
      p.conservacaoOriginal!.rotulo,
      p.conservacao!.rotulo,
    ));
  }

  if (p.situacaoOriginal != null &&
      p.situacao != null &&
      p.situacaoOriginal != p.situacao) {
    divergencias.add(Divergencia(
      CampoDivergente.situacao,
      p.situacaoOriginal!.rotulo,
      p.situacao!.rotulo,
    ));
  }

  return divergencias;
}

/// Classifica o item em um dos três grupos do resultado final.
Classificacao classificar(Patrimonio p) {
  if (p.ignorado) return Classificacao.ignorado;
  if (!p.verificado) return Classificacao.naoLocalizado;
  return divergenciasDe(p).isEmpty ? Classificacao.ok : Classificacao.divergente;
}

/// Números de acompanhamento de um inventário.
class ProgressoInventario {
  /// Itens que participam do inventário. Não inclui os de ED excluído: contar
  /// material bibliográfico como pendência daria um progresso que nunca chega
  /// a 100%.
  final int total;
  final int verificados;
  final int naoLocalizados;
  final int ok;
  final int divergentes;

  /// Fora do inventário por ED excluído. Exibido à parte, para que ninguém
  /// procure por eles.
  final int ignorados;

  const ProgressoInventario({
    required this.total,
    required this.verificados,
    required this.naoLocalizados,
    required this.ok,
    required this.divergentes,
    required this.ignorados,
  });

  static const ProgressoInventario vazio = ProgressoInventario(
    total: 0,
    verificados: 0,
    naoLocalizados: 0,
    ok: 0,
    divergentes: 0,
    ignorados: 0,
  );

  /// Percentual concluído, de 0 a 100.
  ///
  /// Em ponto flutuante, ao contrário da divisão inteira do SLAP, que mostrava
  /// 99% durante os últimos 1% do trabalho.
  double get percentual => total == 0 ? 0 : (verificados * 100) / total;

  int get pendentes => total - verificados;

  bool get concluido => total > 0 && verificados == total;
}
