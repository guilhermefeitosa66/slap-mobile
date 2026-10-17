import 'patrimonio.dart';
import 'valores.dart';

/// Campo em que o inventário encontrou valor diferente do cadastro do SUAP.
///
/// Sala, responsável e estado de conservação: os campos do levantamento que
/// também vêm na planilha do SUAP. Situação de uso não tem valor anterior com
/// que comparar — o SUAP não tem esse campo.
enum CampoDivergente {
  sala('Sala'),
  responsavel('Responsável'),
  conservacao('Estado de conservação');

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
/// O estado de conservação só diverge quando o SUAP tem estado para o item:
/// sem valor anterior, o levantado é informação nova, e inventar uma
/// divergência aí encheria o relatório de linhas em que a coluna "valor SUAP"
/// viria vazia. Situação de uso fica de fora pelo mesmo motivo — o SUAP não a
/// registra. O que precisa de providência nesses campos sai pela marca de
/// atenção de [Patrimonio.exigeAtencao], que não depende de base.
List<Divergencia> divergenciasDe(Patrimonio p) {
  if (!p.verificado || p.ignorado) return const [];

  final divergencias = <Divergencia>[];

  if (!mesmoTexto(p.salaOriginal, p.salaEfetiva)) {
    divergencias.add(
      Divergencia(CampoDivergente.sala, p.salaOriginal, p.salaEfetiva),
    );
  }

  if (!mesmoTexto(p.responsavelOriginal, p.responsavelEfetivo)) {
    divergencias.add(
      Divergencia(
        CampoDivergente.responsavel,
        p.responsavelOriginal,
        p.responsavelEfetivo,
      ),
    );
  }

  final original = p.conservacaoOriginal;
  if (original != null && p.conservacaoEfetiva != original) {
    divergencias.add(
      Divergencia(
        CampoDivergente.conservacao,
        original.rotulo,
        p.conservacaoEfetiva?.rotulo,
      ),
    );
  }

  return divergencias;
}

/// Classifica o item em um dos três grupos do resultado final.
Classificacao classificar(Patrimonio p) {
  if (p.ignorado) return Classificacao.ignorado;
  if (!p.verificado) return Classificacao.naoLocalizado;
  return divergenciasDe(p).isEmpty
      ? Classificacao.ok
      : Classificacao.divergente;
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

/// Números de acompanhamento de uma sala durante o levantamento.
///
/// É o que responde "quanto falta aqui?", a pergunta de quem está dentro do
/// ambiente — o progresso do inventário inteiro quase não se move numa sala e
/// não ajuda a decidir quando sair dela.
class ProgressoSala {
  /// Itens que a planilha do SUAP aponta para esta sala, sem os de ED
  /// excluído. É a estimativa do que procurar no ambiente.
  final int total;

  /// Desses, quantos já foram verificados — inclusive os encontrados em outra
  /// sala, que também não precisam mais ser procurados aqui.
  final int verificados;

  /// Itens registrados nesta sala que a planilha aponta para outra.
  ///
  /// Fora do denominador por definição: ninguém os procuraria aqui. Contam à
  /// parte porque, numa sala que recebeu muita coisa, são a única prova na
  /// tela de que as leituras entraram.
  final int deOutrasSalas;

  const ProgressoSala({
    required this.total,
    required this.verificados,
    required this.deOutrasSalas,
  });

  static const ProgressoSala vazio = ProgressoSala(
    total: 0,
    verificados: 0,
    deOutrasSalas: 0,
  );

  /// Sala que não consta da planilha: não há denominador, e mostrar `0/0`
  /// diria que o trabalho ali está terminado antes de começar.
  bool get semBase => total == 0;

  int get pendentes => total - verificados;
}
