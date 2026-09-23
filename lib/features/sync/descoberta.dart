import 'dart:async';
import 'dart:developer' as developer;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nsd/nsd.dart' as nsd;

import 'cliente.dart';
import 'multicast.dart';
import 'protocolo.dart';

/// Encontra os outros aparelhos na rede local.
///
/// Duas vias em paralelo, porque nenhuma é confiável sozinha:
///
/// 1. **mDNS / DNS-SD**, pelo `NsdManager` no Android e `NetService` no iOS.
///    É o mecanismo padrão, e funciona bem em rede cabeada e Wi-Fi doméstico.
/// 2. **Beacon UDP multicast**, porque o mDNS falha com frequência em rede de
///    celular e em vários pontos de acesso corporativos — justamente o cenário
///    de um inventário em campus.
///
/// Nenhuma das duas atravessa isolamento de cliente ("AP isolation"): quando a
/// rede separa os aparelhos entre si, não há solução em software. Nesse caso a
/// lista fica vazia e cabe à interface orientar o uso de um hotspot próprio.
///
/// O beacon depende da [TravaMulticast] no Android: ela é adquirida ao iniciar
/// e liberada ao parar — e também logo no início, se nenhuma via subir.
class Descoberta {
  final String dispositivoId;
  final String? Function() usuarioNome;

  /// Porta do servidor local, anunciada aos outros.
  final int porta;

  /// Vias ligadas. Permite testar o beacon sozinho, com o mDNS desligado, sem
  /// mexer no código (ver [ViaDescoberta.configuradas]).
  final Set<ViaDescoberta> vias;

  final TravaMulticast _trava;
  bool _travaAdquirida = false;

  Descoberta({
    required this.dispositivoId,
    required this.usuarioNome,
    required this.porta,
    Set<ViaDescoberta>? vias,
    TravaMulticast? trava,
  }) : vias = vias ?? ViaDescoberta.configuradas(),
       _trava = trava ?? TravaMulticast.doSistema();

  final _pares = <String, Par>{};
  final _mudancas = StreamController<List<Par>>.broadcast();

  nsd.Registration? _registro;
  nsd.Discovery? _busca;
  RawDatagramSocket? _socket;
  Timer? _pulso;

  /// Pares conhecidos agora.
  List<Par> get pares => _pares.values.toList();

  /// Emite a lista sempre que ela muda.
  Stream<List<Par>> get mudancas => _mudancas.stream;

  /// Falhas de descoberta que valem mostrar ao usuário.
  final List<String> avisos = [];

  bool get ativa => _busca != null || _socket != null;

  /// A trava de multicast está segura agora.
  bool get travaAdquirida => _travaAdquirida;

  Future<void> iniciar() async {
    if (vias.contains(ViaDescoberta.beacon)) await _adquirirTrava();

    try {
      // As duas vias sobem de forma independente: o mDNS falhar não pode
      // impedir o beacon de funcionar, e é exatamente na rede em que um falha
      // que o outro salva a sincronização.
      await Future.wait([
        if (vias.contains(ViaDescoberta.mdns)) _iniciarMdns(),
        if (vias.contains(ViaDescoberta.beacon)) _iniciarBeacon(),
      ]);
    } finally {
      // Descoberta que não subiu não vai ser parada por ninguém: a trava
      // não pode ficar presa esperando.
      if (!ativa) await _liberarTrava();
    }
  }

  Future<void> _adquirirTrava() async {
    final falha = await _trava.adquirir();
    if (falha == null) {
      _travaAdquirida = true;
      return;
    }

    // Registrado em vez de engolido: sem a trava o beacon não recebe nada, e
    // é isso que explica um aparelho que não aparece na lista.
    developer.log(
      'MulticastLock não adquirido: $falha',
      name: 'slap.descoberta',
      level: 900,
    );
    avisos.add(
      'O Android não liberou a recepção de anúncios na rede ($falha). A busca '
      'continua, mas pode não encontrar todos os aparelhos.',
    );
  }

  Future<void> _liberarTrava() async {
    if (!_travaAdquirida) return;
    _travaAdquirida = false;
    await _trava.liberar();
  }

  Future<void> parar() async {
    try {
      await _pararVias();
    } finally {
      await _liberarTrava();
    }
  }

  Future<void> _pararVias() async {
    _pulso?.cancel();
    _pulso = null;

    _socket?.close();
    _socket = null;

    try {
      if (_busca != null) await nsd.stopDiscovery(_busca!);
      if (_registro != null) await nsd.unregister(_registro!);
    } catch (_) {
      // Encerrar a descoberta é melhor-esforço: se a plataforma já soltou o
      // recurso, insistir só produziria erro sem consequência.
    }
    _busca = null;
    _registro = null;

    _pares.clear();
    _notificar();
  }

  Future<void> dispose() async {
    await parar();
    await _mudancas.close();
  }

  // ------------------------------------------------------------------ mDNS ---

  Future<void> _iniciarMdns() async {
    try {
      _registro = await nsd.register(
        nsd.Service(
          name: 'SLAP ${dispositivoId.substring(0, 6)}',
          type: tipoServico,
          port: porta,
          txt: {
            'disp': _bytes(dispositivoId),
            'user': _bytes(usuarioNome() ?? ''),
          },
        ),
      );

      final busca = await nsd.startDiscovery(tipoServico, autoResolve: true);
      busca.addServiceListener((servico, status) {
        if (status == nsd.ServiceStatus.found) {
          _registrarDeMdns(servico);
        } else {
          final id = _texto(servico.txt?['disp']);
          if (id != null) _remover(id);
        }
      });
      _busca = busca;
    } catch (e) {
      avisos.add(
        'Descoberta automática indisponível nesta rede ($e). '
        'A busca continua pelo outro método.',
      );
    }
  }

  void _registrarDeMdns(nsd.Service servico) {
    final id = _texto(servico.txt?['disp']);
    final host = servico.addresses?.firstOrNull?.address ?? servico.host;

    if (id == null ||
        id == dispositivoId ||
        host == null ||
        servico.port == null) {
      return;
    }

    _adicionar(
      Par(
        dispositivoId: id,
        usuarioNome: _texto(servico.txt?['user']),
        host: host,
        porta: servico.port!,
        origem: 'mdns',
      ),
    );
  }

  // ---------------------------------------------------------------- beacon ---

  Future<void> _iniciarBeacon() async {
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        portaMulticast,
        reuseAddress: true,
        reusePort: false,
      );
      socket.joinMulticast(InternetAddress(enderecoMulticast));
      // Um salto basta: os aparelhos estão no mesmo segmento, e não há razão
      // para o anúncio atravessar roteador.
      socket.multicastHops = 1;
      _socket = socket;

      socket.listen((evento) {
        if (evento != RawSocketEvent.read) return;
        final pacote = socket.receive();
        if (pacote != null) _registrarDeBeacon(pacote);
      });

      _anunciar();
      _pulso = Timer.periodic(const Duration(seconds: 3), (_) => _anunciar());
    } catch (e) {
      avisos.add(
        'Não foi possível anunciar na rede local ($e). '
        'Verifique se o Wi-Fi está conectado.',
      );
    }
  }

  void _anunciar() {
    final socket = _socket;
    if (socket == null) return;

    final anuncio = utf8.encode(
      jsonEncode({
        'v': versaoProtocolo,
        'disp': dispositivoId,
        'user': usuarioNome(),
        'porta': porta,
      }),
    );

    try {
      socket.send(anuncio, InternetAddress(enderecoMulticast), portaMulticast);
    } catch (_) {
      // Rede caiu entre um pulso e outro. O próximo tenta de novo.
    }
  }

  void _registrarDeBeacon(Datagram pacote) {
    try {
      final j = jsonDecode(utf8.decode(pacote.data)) as Map<String, dynamic>;
      final id = j['disp'] as String?;
      final portaRemota = (j['porta'] as num?)?.toInt();

      // Aparelho de outra versão aparece na lista mesmo assim: esconder faria
      // a pessoa procurar defeito na rede, e a sincronização explica.
      if (id == null || id == dispositivoId || portaRemota == null) return;

      _adicionar(
        Par(
          dispositivoId: id,
          usuarioNome: j['user'] as String?,
          host: pacote.address.address,
          porta: portaRemota,
          origem: 'beacon',
        ),
      );
    } catch (_) {
      // Pacote de outro aplicativo no mesmo endereço multicast.
    }
  }

  // ----------------------------------------------------------------- comum ---

  void _adicionar(Par par) {
    final anterior = _pares[par.dispositivoId];
    // O mDNS resolve o nome do host, o beacon traz o IP de quem enviou.
    // Trocar a entrada a cada anúncio faria a lista piscar na tela.
    if (anterior != null &&
        anterior.host == par.host &&
        anterior.porta == par.porta &&
        anterior.usuarioNome == par.usuarioNome) {
      return;
    }

    _pares[par.dispositivoId] = par;
    _notificar();
  }

  void _remover(String dispositivoId) {
    if (_pares.remove(dispositivoId) != null) _notificar();
  }

  void _notificar() {
    if (!_mudancas.isClosed) _mudancas.add(pares);
  }

  static Uint8List _bytes(String texto) =>
      Uint8List.fromList(utf8.encode(texto));

  static String? _texto(Uint8List? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final texto = utf8.decode(bytes);
      return texto.isEmpty ? null : texto;
    } catch (_) {
      return null;
    }
  }
}

/// As duas formas de encontrar aparelhos.
enum ViaDescoberta {
  mdns,
  beacon;

  /// Vias escolhidas na compilação, todas por padrão.
  ///
  /// Para conferir que o beacon funciona sozinho — o plano B das redes em que
  /// o mDNS não passa —, gere o APK com o mDNS desligado:
  ///
  ///     flutter build apk --dart-define=SLAP_DESCOBERTA=beacon
  static Set<ViaDescoberta> configuradas() {
    const texto = String.fromEnvironment(
      'SLAP_DESCOBERTA',
      defaultValue: 'mdns,beacon',
    );
    final escolhidas = {
      for (final nome in texto.split(','))
        for (final via in values)
          if (via.name == nome.trim()) via,
    };
    return escolhidas.isEmpty ? values.toSet() : escolhidas;
  }
}

extension _PrimeiroOuNulo<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
