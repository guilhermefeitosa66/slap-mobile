import 'dart:async';

import '../../data/banco.dart';
import 'descoberta.dart';
import 'servidor.dart';

/// Mantém este aparelho visível e atendendo enquanto alguém entra.
///
/// Compartilhar um inventário por QR code ou por link só funciona se, do
/// outro lado, a descoberta achar este aparelho: o link não leva a chave, e
/// quem o recebeu precisa chegar até aqui para pedir entrada. Por isso a
/// folha de compartilhar liga o servidor e o anúncio na rede enquanto está
/// aberta.
///
/// O anúncio continua por alguns minutos depois que a folha fecha, porque a
/// sequência real é "mando o link, guardo o celular, a pessoa abre a
/// mensagem": desligar tudo ao fechar a folha faria o pedido chegar a um
/// aparelho que já não responde. O que não dá para contornar é o Android
/// encerrar o processo em segundo plano — daí o aviso, na folha, de deixar o
/// aplicativo aberto até o outro entrar.
class AnuncioEntrada {
  final ServidorSync servidor;
  final Banco banco;
  final String? Function() usuarioNome;

  /// Quanto o anúncio continua depois do último interessado sair.
  final Duration carencia;

  Descoberta? _descoberta;
  Timer? _desligamento;

  /// Quantas telas dependem do anúncio agora.
  int _interessados = 0;

  AnuncioEntrada({
    required this.servidor,
    required this.banco,
    required this.usuarioNome,
    this.carencia = const Duration(minutes: 5),
  });

  bool get anunciando => _descoberta != null;

  /// Falhas de descoberta que valem mostrar a quem compartilha.
  List<String> get avisos => _descoberta?.avisos ?? const [];

  /// Liga o servidor e o anúncio, se ainda não estiverem ligados.
  Future<void> abrir() async {
    _interessados++;
    _desligamento?.cancel();
    _desligamento = null;
    if (_descoberta != null) return;

    final porta = await servidor.iniciar();
    final descoberta = Descoberta(
      dispositivoId: banco.dispositivoId,
      usuarioNome: usuarioNome,
      porta: porta,
    );
    _descoberta = descoberta;
    await descoberta.iniciar();
  }

  /// Uma tela deixou de precisar do anúncio. O desligamento fica para depois
  /// da carência.
  void fechar() {
    if (_interessados > 0) _interessados--;
    if (_interessados > 0) return;

    _desligamento?.cancel();
    _desligamento = Timer(carencia, parar);
  }

  /// Desliga o anúncio agora. O servidor continua de pé: ele não custa nada
  /// parado, e é o que atende a sincronização de quem já participa.
  Future<void> parar() async {
    _desligamento?.cancel();
    _desligamento = null;
    _interessados = 0;

    final descoberta = _descoberta;
    _descoberta = null;
    await descoberta?.dispose();
  }

  Future<void> dispose() => parar();
}
