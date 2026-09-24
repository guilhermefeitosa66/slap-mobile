import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/atualizacao.dart';
import '../../data/schema.dart';

/// Em que pé está a conferência de versão.
///
/// Três situações, e as três aparecem na tela de um jeito diferente: não se
/// sabe (sem rede, desligado nos ajustes, ou a consulta ainda não voltou), em
/// dia, e há versão nova.
class EstadoAtualizacao {
  /// A versão publicada, quando é mais nova que a instalada.
  final AtualizacaoDisponivel? nova;

  /// A consulta foi feita e respondeu. Sem isto, "em dia" seria afirmação sem
  /// base — e dizer que está tudo certo sem ter conferido é pior que não
  /// dizer nada.
  final bool conferido;

  /// O aviso foi dispensado **nesta sessão**. Não é gravado: fechar e abrir
  /// o aplicativo faz a pergunta de novo, e a faixa volta enquanto a versão
  /// não for instalada. Quem está no meio de um levantamento manda calar e
  /// segue; quem abre o aplicativo de novo, no dia seguinte, é lembrado.
  final bool dispensado;

  const EstadoAtualizacao({
    this.nova,
    this.conferido = false,
    this.dispensado = false,
  });

  /// Conferido, e a versão instalada é a última publicada.
  bool get emDia => conferido && nova == null;

  /// Há o que avisar, e ninguém mandou calar.
  bool get aAvisar => nova != null && !dispensado;
}

/// Conferência de versão, uma vez por sessão.
///
/// Vive num provedor, e não dentro da faixa, porque dois lugares da tela
/// dependem do mesmo resultado: a faixa que avisa e a linha discreta que diz
/// que está tudo em dia. Consultar duas vezes seria duas chamadas de rede
/// para a mesma pergunta.
class ControladorAtualizacao extends Notifier<EstadoAtualizacao> {
  @override
  EstadoAtualizacao build() {
    // Sem `await`: a abertura não espera por rede. O levantamento funciona
    // sem internet por projeto, e uma verificação de versão não é motivo
    // para contradizer isso.
    Future.microtask(_conferir);
    return const EstadoAtualizacao();
  }

  /// Confere de novo, a pedido — o gesto de puxar para atualizar.
  ///
  /// Uma dispensa anterior não sobrevive a isto: quem puxou para atualizar
  /// pediu para saber, e esconder a resposta seria contrariar o gesto.
  Future<void> reconferir() => _conferir();

  Future<void> _conferir() async {
    final banco = ref.read(bancoProvider);
    if (banco.lerConfig(Config.verificarAtualizacao) == '0') return;

    final verificador = ref.read(verificadorAtualizacaoProvider);
    final publicada = await verificador.ultimaPublicada();
    if (!ref.mounted) return;

    // Sem resposta, o estado não muda: nada na tela afirma coisa alguma, e o
    // aplicativo segue. Sem rede é o caso comum em campo.
    if (publicada == null) return;

    state = EstadoAtualizacao(
      nova: versaoEhMaisNova(publicada, versaoApp)
          ? AtualizacaoDisponivel(
              versao: versaoLegivel(publicada),
              endereco: enderecoComoAtualizar,
            )
          : null,
      conferido: true,
    );
  }

  /// "Agora não": a faixa some até o aplicativo ser fechado e aberto de novo.
  void dispensar() {
    if (state.nova == null) return;
    state = EstadoAtualizacao(
      nova: state.nova,
      conferido: state.conferido,
      dispensado: true,
    );
  }
}

final estadoAtualizacaoProvider =
    NotifierProvider<ControladorAtualizacao, EstadoAtualizacao>(
      ControladorAtualizacao.new,
    );
