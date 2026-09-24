import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import 'cliente.dart';
import 'descoberta.dart';
import 'protocolo.dart';

/// Entra num inventário criado em outro aparelho.
///
/// Lê o QR code, procura na rede local quem tem aquele inventário e baixa a
/// réplica inicial. A câmera já é permissão do projeto, então o pareamento não
/// acrescenta nenhuma exigência ao usuário.
Future<void> entrarEmInventario(BuildContext context, WidgetRef ref) async {
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const TelaEntrar()));
}

/// O que se sabe do inventário antes de entrar nele.
///
/// As duas origens caem aqui: o QR code, que traz a chave junto, e o link,
/// que traz só a identificação e o aparelho a quem pedir. Daí para a frente o
/// fluxo é um só — inclusive o pedido de entrada, que passa pela origem nos
/// dois casos.
class _Alvo {
  final String inventarioId;
  final String nome;
  final int ano;

  /// Aparelho que compartilhou. Só o link informa.
  final String? dispositivoOrigem;

  const _Alvo({
    required this.inventarioId,
    required this.nome,
    required this.ano,
    this.dispositivoOrigem,
  });

  /// Do QR code. A chave que ele carrega **não** é usada para entrar: quem
  /// autoriza é o aceite, e é dele que a chave vem. O QR continua levando a
  /// chave por compatibilidade com aparelhos que ainda não atualizaram.
  _Alvo.doQr(ConviteInventario c)
    : inventarioId = c.inventarioId,
      nome = c.nome,
      ano = c.ano,
      dispositivoOrigem = null;

  _Alvo.doLink(ConviteLink c)
    : inventarioId = c.inventarioId,
      nome = c.nome,
      ano = c.ano,
      dispositivoOrigem = c.dispositivoOrigem;

  String get titulo => '$nome — $ano';
}

/// Tela de entrada em inventário.
///
/// Sem [link], abre o leitor de QR code; com ele, vai direto ao pedido de
/// entrada — é o que a rota do deep link usa.
class TelaEntrar extends ConsumerStatefulWidget {
  final ConviteLink? link;

  const TelaEntrar({super.key, this.link});

  @override
  ConsumerState<TelaEntrar> createState() => _TelaEntrarState();
}

class _TelaEntrarState extends ConsumerState<TelaEntrar> {
  MobileScannerController? _controlador;

  _Alvo? _alvo;
  String _situacao = '';
  String? _erro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();

    final link = widget.link;
    if (link == null) {
      _controlador = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
      );
      return;
    }

    _alvo = _Alvo.doLink(link);
    _ocupado = true;
    // Depois do primeiro quadro: o `initState` não pode mexer no navegador
    // nem mostrar mensagem, e o pedido de entrada faz as duas coisas.
    WidgetsBinding.instance.addPostFrameCallback((_) => _entrar(_alvo!));
  }

  @override
  void dispose() {
    _controlador?.dispose();
    super.dispose();
  }

  Future<void> _aoLer(BarcodeCapture captura) async {
    if (_ocupado || _alvo != null) return;

    for (final codigo in captura.barcodes) {
      final texto = codigo.rawValue;
      if (texto == null) continue;

      // O QR do aplicativo, e também o link: quem recebeu o convite por
      // mensagem pode mostrar o link na tela, e ler dele é o mesmo caminho.
      final convite = ConviteInventario.decodificar(texto);
      final link = ConviteLink.decodificar(texto);
      final alvo = convite != null
          ? _Alvo.doQr(convite)
          : link != null
          ? _Alvo.doLink(link)
          : null;
      // QR de outro aplicativo: ignorar em silêncio, porque apontar a câmera
      // para qualquer código é o caso comum.
      if (alvo == null) continue;

      setState(() {
        _alvo = alvo;
        _ocupado = true;
      });
      await _entrar(alvo);
      return;
    }
  }

  Future<void> _entrar(_Alvo alvo) async {
    final inventarios = ref.read(inventariosProvider);

    if (inventarios.porId(alvo.inventarioId) != null) {
      _falhar('Este inventário já está neste aparelho.');
      return;
    }

    _andando('Procurando aparelhos na rede local…');

    final servidor = ref.read(servidorSyncProvider);
    final porta = await servidor.iniciar();

    final descoberta = Descoberta(
      dispositivoId: ref.read(bancoProvider).dispositivoId,
      usuarioNome: () => ref.read(identidadeProvider).nome,
      porta: porta,
    );

    try {
      await descoberta.iniciar();

      // Descoberta na rede não é instantânea: o anúncio precisa circular e ser
      // respondido. Tentar uma vez só falharia quase sempre.
      final encontrados = await _aguardarPares(descoberta);
      final candidatos = _candidatos(encontrados, alvo);
      if (candidatos.isEmpty) {
        _falhar(
          encontrados.isEmpty
              ? 'Nenhum aparelho encontrado na rede.\n\n'
                    'Verifique se os dois estão no mesmo Wi-Fi. Algumas redes '
                    'institucionais isolam os aparelhos entre si — nesse caso, '
                    'use um ponto de acesso compartilhado por um dos '
                    'celulares.'
              : 'O aparelho que compartilhou este inventário não está na '
                    'rede.\n\nPeça para a pessoa abrir o aplicativo e tocar '
                    'em Compartilhar, e confira se os dois estão no mesmo '
                    'Wi-Fi.',
        );
        return;
      }

      final identidade = ref.read(identidadeProvider);
      final cliente = ref.read(clienteSyncProvider);
      Object? ultimaFalha;

      // Vários aparelhos podem ter o inventário; basta um responder. Os que
      // não participam recusam, e isso não é erro.
      for (final par in candidatos) {
        try {
          _andando(
            'Esperando ${par.rotulo} aceitar o seu pedido…\n'
            'O pedido vale um minuto.',
          );

          // O aceite é a autorização, também quando a chave já veio no QR:
          // um só fluxo de entrada, dois jeitos de chegar a ele.
          final chave = await cliente.pedirEntrada(
            par: par,
            inventarioId: alvo.inventarioId,
            usuarioNome: identidade.nome,
            matricula: identidade.matricula,
          );

          await _receber(alvo, par, chave);
          return;
        } on EntradaRecusada catch (e) {
          // Decisão de gente, e não falha de rede: não adianta perguntar ao
          // aparelho seguinte.
          _falhar(e.mensagem);
          return;
        } catch (e) {
          ultimaFalha = e;
        }
      }

      _falhar(
        'Não foi possível entrar pelos ${candidatos.length} aparelhos '
        'encontrados.\n\n$ultimaFalha',
      );
    } catch (e) {
      _falhar('Falha ao entrar no inventário: $e');
    } finally {
      await descoberta.dispose();
    }
  }

  /// Mostra em que pé está a entrada. Só faz sentido com a tela montada: o
  /// pedido leva até um minuto, tempo de sobra para a pessoa desistir e
  /// voltar.
  void _andando(String situacao) {
    if (mounted) setState(() => _situacao = situacao);
  }

  void _falhar(String erro) {
    if (!mounted) return;
    setState(() {
      _erro = erro;
      _ocupado = false;
    });
  }

  /// Baixa a réplica e o levantamento já feito.
  Future<void> _receber(_Alvo alvo, Par par, String chaveSync) async {
    final cliente = ref.read(clienteSyncProvider);
    final inventarios = ref.read(inventariosProvider);

    _andando('Baixando o inventário…');

    final pacote = await cliente.baixarPacote(
      par: par,
      inventarioId: alvo.inventarioId,
      chaveSync: chaveSync,
    );

    inventarios.registrarRecebido(pacote.inventario);
    ref.read(patrimoniosProvider).inserirRecebidos(pacote.patrimonios);
    ref.read(operacoesProvider).reaplicarEdsExcluidos(pacote.inventario.id);

    // O pacote traz só os dados do SUAP. O levantamento feito até aqui vem
    // pelo log, e já com o par à mão: quem começa a ler precisa ver o que os
    // outros já leram — e, se este aparelho já participou antes, recuperar o
    // próprio trabalho antes de continuar.
    _andando('Recebendo o levantamento…');
    try {
      await cliente.sincronizar(
        par: par,
        inventarioId: pacote.inventario.id,
        chaveSync: chaveSync,
      );
    } on FalhaSync {
      // O inventário já está aqui; a tela de sincronização resolve.
    }
    ref.read(revisaoProvider.notifier).mudou();

    if (!mounted) return;
    _sair();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${pacote.inventario.nome}: ${pacote.patrimonios.length} '
          'patrimônios recebidos de ${par.rotulo}',
        ),
      ),
    );
  }

  /// A quem pedir. Com o aparelho de origem no link, só a ele: é quem mostra
  /// o pedido a uma pessoa. Sem ele — QR code —, a qualquer um que responda.
  List<Par> _candidatos(List<Par> encontrados, _Alvo alvo) {
    final origem = alvo.dispositivoOrigem;
    if (origem == null) return encontrados;
    return [
      for (final p in encontrados)
        if (p.dispositivoId == origem) p,
    ];
  }

  /// Sai da tela. Aberta pelo link com o aplicativo fechado, não há para onde
  /// voltar: o destino é a lista de inventários.
  void _sair() {
    final navegador = Navigator.of(context);
    if (navegador.canPop()) {
      navegador.pop();
    } else {
      context.go('/');
    }
  }

  Future<List<Par>> _aguardarPares(Descoberta descoberta) async {
    for (var tentativa = 0; tentativa < 10; tentativa++) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (descoberta.pares.isNotEmpty) return descoberta.pares;
      _andando('Procurando aparelhos na rede local… (${tentativa + 1}/10)');
    }
    return descoberta.pares;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar em um inventário')),
      body: _alvo == null ? _leitor() : _andamento(),
    );
  }

  Widget _leitor() {
    return Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _controlador,
            onDetect: _aoLer,
            errorBuilder: (context, erro) => ColoredBox(
              color: Colors.black,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    erro.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Autorize o acesso à câmera para ler o QR code.'
                        : 'Não foi possível abrir a câmera.',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aponte para o QR code exibido no aparelho que criou o inventário.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _andamento() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _alvo!.nome,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            Text('${_alvo!.ano}'),
            const SizedBox(height: 32),
            if (_erro == null) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(_situacao, textAlign: TextAlign.center),
            ] else ...[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _tentarDeNovo(),
                child: const Text('Tentar de novo'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _tentarDeNovo() {
    final link = widget.link;
    if (link == null) {
      // Volta ao leitor: o QR pode ser de outro inventário.
      setState(() {
        _erro = null;
        _alvo = null;
      });
      return;
    }
    setState(() {
      _erro = null;
      _ocupado = true;
    });
    _entrar(_Alvo.doLink(link));
  }
}

/// A rota que recebe o link de convite.
///
/// O endereço vem do Android como rota inicial (aplicativo fechado) ou pelo
/// `pushRouteInformation` (aplicativo aberto). Link que não é convite não é
/// erro do usuário: a tela diz o que houve e oferece a lista.
class TelaEntrarPorLink extends StatelessWidget {
  final Uri endereco;

  const TelaEntrarPorLink({super.key, required this.endereco});

  @override
  Widget build(BuildContext context) {
    final convite = ConviteLink.deUri(endereco);
    if (convite == null) return const _LinkInvalido();
    return TelaEntrar(link: convite);
  }
}

class _LinkInvalido extends StatelessWidget {
  const _LinkInvalido();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar em um inventário')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.link_off,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              const Text(
                'Este link não é um convite de inventário, ou veio '
                'incompleto.\n\nPeça um link novo a quem compartilhou.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Ver meus inventários'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
