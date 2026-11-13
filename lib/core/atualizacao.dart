import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'enderecos.dart';

/// Versão deste aplicativo, a mesma de `pubspec.yaml`.
///
/// Repetida aqui porque ler o `pubspec.yaml` em tempo de execução exigiria um
/// plugin, com canal de plataforma, só para saber um número que já é conhecido
/// na compilação. Um teste confere que as duas não divergem — é o que torna a
/// repetição segura.
const String versaoApp = '1.3.3';

/// Onde se pergunta qual é a última versão publicada, para o APK instalado
/// fora das lojas (baixado do site ou do GitHub).
///
/// O endpoint de `releases/latest` do GitHub exclui rascunhos e
/// pré-lançamentos: o que ele devolve é uma versão de verdade.
const String enderecoUltimaVersao =
    'https://api.github.com/repos/guilhermefeitosa66/slap-mobile/releases/latest';

/// Para onde o aviso leva: a página explica como instalar, o que o arquivo
/// solto de uma release não faz.
const String enderecoComoAtualizar = enderecoSite;

/// Curto: isto roda na abertura, sem ninguém pedir. Uma consulta que demora
/// não pode ser percebida por quem só quer começar a levantar.
const Duration tempoLimiteVerificacao = Duration(seconds: 8);

/// De onde veio a instalação. Decide a quem perguntar pela versão nova: quem
/// instalou pela loja atualiza pela loja, e quem instalou o APK baixado do
/// site atualiza pelo site.
enum OrigemInstalacao { googlePlay, appStore, foraDasLojas }

/// Pacote Android, o mesmo da ficha da Play.
const String pacoteAndroid = 'io.github.guilhermefeitosa66.slap_mobile';

/// Bundle id do iOS, o mesmo do App Store Connect.
const String bundleIos = 'io.github.guilhermefeitosa66.slapMobile';

/// Ficha do aplicativo no app da Play Store.
const String enderecoPlayMarket = 'market://details?id=$pacoteAndroid';

/// Ficha do aplicativo na Play, no navegador: reserva de quando o app da Play
/// não abre o endereço `market://`.
const String enderecoPlay =
    'https://play.google.com/store/apps/details?id=$pacoteAndroid';

/// Página do aplicativo na App Store, quando a consulta não traz o endereço.
const String enderecoAppStore = 'https://apps.apple.com/br/app/id6828446378';

/// Consulta pública da Apple (iTunes Lookup) pela versão publicada na loja.
const String enderecoLookupApple =
    'https://itunes.apple.com/lookup?bundleId=$bundleIos&country=br';

/// Uma versão publicada mais nova que a instalada.
class AtualizacaoDisponivel {
  /// O número da versão nova. Nulo quando a loja não diz qual é: a Play só
  /// informa que há atualização.
  final String? versao;

  /// Para onde o aviso leva: a ficha da loja, ou a página do site que
  /// explica como instalar o APK.
  final String endereco;

  final OrigemInstalacao origem;

  const AtualizacaoDisponivel({
    required this.versao,
    required this.endereco,
    this.origem = OrigemInstalacao.foraDasLojas,
  });
}

/// O resultado de uma consulta que respondeu: [nova] nula quer dizer "em dia".
class ConsultaVersao {
  final AtualizacaoDisponivel? nova;

  const ConsultaVersao(this.nova);
}

/// A origem da instalação a partir do pacote instalador do Android.
OrigemInstalacao origemPeloInstalador(String? instalador) =>
    instalador == 'com.android.vending'
    ? OrigemInstalacao.googlePlay
    : OrigemInstalacao.foraDasLojas;

/// A origem desta instalação. No iPhone só há a App Store (ou o TestFlight,
/// que é dela); no Android, quem instalou diz.
Future<OrigemInstalacao> origemDaInstalacao() async {
  if (Platform.isIOS) return OrigemInstalacao.appStore;
  if (!Platform.isAndroid) return OrigemInstalacao.foraDasLojas;
  final info = await PackageInfo.fromPlatform();
  return origemPeloInstalador(info.installerStore);
}

/// Pergunta à Play, pela API de atualizações no app, se há versão nova.
/// Só responde para aplicativo instalado pela Play.
Future<bool?> _consultarPlay() async {
  final info = await InAppUpdate.checkForUpdate();
  return info.updateAvailability == UpdateAvailability.updateAvailable;
}

/// Verdadeiro quando [candidata] é estritamente mais nova que [atual].
///
/// Compara número a número, e não texto: `1.10.0` é mais novo que `1.9.0`, o
/// que a comparação alfabética diria ao contrário. Completa com zeros, de modo
/// que `1.2` e `1.2.0` são a mesma versão. Qualquer coisa que não tenha número
/// nenhum não é comparável, e a resposta é não.
bool versaoEhMaisNova(String candidata, String atual) {
  final nova = _numeros(candidata);
  final velha = _numeros(atual);
  if (nova.isEmpty || velha.isEmpty) return false;

  final tamanho = nova.length > velha.length ? nova.length : velha.length;
  for (var i = 0; i < tamanho; i++) {
    final a = i < nova.length ? nova[i] : 0;
    final b = i < velha.length ? velha[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

/// A versão como se mostra na tela: `v1.2.0`, `SLAP 1.2.0` e `1.2.0+7` viram
/// `1.2.0`. O que a pessoa vê é o número, sem a convenção de tag em volta.
String versaoLegivel(String bruto) => _numeros(bruto).join('.');

/// Os números de `v1.2.3`, `1.2.3+4`, `SLAP 1.2`: `[1, 2, 3]`.
List<int> _numeros(String bruto) {
  final achado = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(bruto);
  if (achado == null) return const [];
  return [for (final parte in achado.group(1)!.split('.')) int.parse(parte)];
}

/// Pergunta se há versão mais nova, a quem distribuiu esta instalação: a
/// Google Play, a App Store ou, para o APK baixado do site, o GitHub.
///
/// **Nunca lança.** Isto roda sozinho a cada abertura: sem rede, com a loja
/// ou a API fora do ar, com o limite de requisições estourado ou com o formato
/// da resposta mudado, o resultado é "nada a avisar" e o aplicativo abre
/// igual. O levantamento funciona sem internet por projeto, e uma verificação
/// de versão não é motivo para contradizer isso.
class VerificadorAtualizacao {
  /// Como buscar o corpo de uma resposta. Trocável no teste, que não tem — e
  /// não deve ter — rede.
  final Future<String?> Function(Uri endereco) buscar;

  /// De onde veio a instalação. Por padrão, fora das lojas: é o que os testes
  /// usam; o aplicativo usa [VerificadorAtualizacao.doAparelho].
  final Future<OrigemInstalacao> Function() origem;

  /// Se a Play tem atualização: verdadeiro, falso, ou nulo quando não deu
  /// para saber.
  final Future<bool?> Function() consultarPlay;

  VerificadorAtualizacao({
    Future<String?> Function(Uri)? buscar,
    Future<OrigemInstalacao> Function()? origem,
    Future<bool?> Function()? consultarPlay,
  }) : buscar = buscar ?? _buscarPorHttp,
       origem = origem ?? (() async => OrigemInstalacao.foraDasLojas),
       consultarPlay = consultarPlay ?? (() async => null);

  /// O verificador de verdade, que descobre a origem da instalação e fala
  /// com a loja.
  factory VerificadorAtualizacao.doAparelho() => VerificadorAtualizacao(
    origem: origemDaInstalacao,
    consultarPlay: _consultarPlay,
  );

  /// A versão mais nova, se houver. Nulo quando não há, ou quando não deu
  /// para saber — que para quem está abrindo o aplicativo é a mesma coisa.
  Future<AtualizacaoDisponivel?> verificar({
    String versaoAtual = versaoApp,
  }) async => (await consultar(versaoAtual: versaoAtual))?.nova;

  /// Consulta a origem da instalação. Nulo quando **não deu para saber**.
  ///
  /// Os dois casos que [verificar] junta — estar em dia e não ter conseguido
  /// perguntar — são diferentes na tela: um permite dizer "atualizado", o
  /// outro não permite dizer nada.
  Future<ConsultaVersao?> consultar({String versaoAtual = versaoApp}) async {
    try {
      final de = await origem().timeout(tempoLimiteVerificacao);
      switch (de) {
        case OrigemInstalacao.googlePlay:
          final ha = await consultarPlay().timeout(tempoLimiteVerificacao);
          if (ha == null) return null;
          return ConsultaVersao(
            ha
                ? AtualizacaoDisponivel(
                    versao: null,
                    endereco: enderecoPlay,
                    origem: de,
                  )
                : null,
          );
        case OrigemInstalacao.appStore:
          final publicada = await ultimaNaAppStore();
          if (publicada == null) return null;
          return ConsultaVersao(
            versaoEhMaisNova(publicada.versao, versaoAtual)
                ? AtualizacaoDisponivel(
                    versao: versaoLegivel(publicada.versao),
                    endereco: publicada.endereco,
                    origem: de,
                  )
                : null,
          );
        case OrigemInstalacao.foraDasLojas:
          final publicada = await ultimaPublicada();
          if (publicada == null) return null;
          return ConsultaVersao(
            versaoEhMaisNova(publicada, versaoAtual)
                ? AtualizacaoDisponivel(
                    versao: versaoLegivel(publicada),
                    endereco: enderecoComoAtualizar,
                  )
                : null,
          );
      }
    } catch (_) {
      // Qualquer falha é "não deu para saber". Ver o comentário da classe.
      return null;
    }
  }

  /// A versão publicada na App Store e o endereço da página, pela consulta
  /// pública da Apple. Nulo quando não deu para saber.
  Future<({String versao, String endereco})?> ultimaNaAppStore() async {
    try {
      final corpo = await buscar(Uri.parse(enderecoLookupApple));
      if (corpo == null) return null;

      final json = jsonDecode(corpo);
      if (json is! Map) return null;
      final resultados = json['results'];
      if (resultados is! List || resultados.isEmpty) return null;
      final app = resultados.first;
      if (app is! Map) return null;

      final versao = app['version']?.toString();
      if (versao == null || _numeros(versao).isEmpty) return null;
      final pagina = app['trackViewUrl']?.toString();
      return (
        versao: versao,
        endereco: pagina == null || pagina.isEmpty ? enderecoAppStore : pagina,
      );
    } catch (_) {
      return null;
    }
  }

  /// A última versão publicada no GitHub, como ele a nomeia. Nulo quando
  /// **não deu para saber**.
  Future<String?> ultimaPublicada({
    String endereco = enderecoUltimaVersao,
  }) async {
    try {
      final corpo = await buscar(Uri.parse(endereco));
      if (corpo == null) return null;

      final json = jsonDecode(corpo);
      if (json is! Map) return null;

      final publicada = (json['tag_name'] ?? json['name'])?.toString();
      if (publicada == null || publicada.isEmpty) return null;
      // Sem número não há o que comparar: vale como não ter conseguido saber.
      return _numeros(publicada).isEmpty ? null : publicada;
    } catch (_) {
      // Qualquer falha é "não deu para saber". Ver o comentário da classe.
      return null;
    }
  }
}

Future<String?> _buscarPorHttp(Uri endereco) async {
  final cliente = HttpClient()..connectionTimeout = tempoLimiteVerificacao;
  try {
    final req = await cliente.getUrl(endereco);
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    // O GitHub recusa requisição sem identificação.
    req.headers.set(HttpHeaders.userAgentHeader, 'SLAP Mobile');

    final resposta = await req.close().timeout(tempoLimiteVerificacao);
    if (resposta.statusCode != HttpStatus.ok) return null;
    return await utf8.decoder.bind(resposta).join();
  } finally {
    cliente.close(force: true);
  }
}
