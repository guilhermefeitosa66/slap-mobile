import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Versão deste aplicativo, a mesma de `pubspec.yaml`.
///
/// Repetida aqui porque ler o `pubspec.yaml` em tempo de execução exigiria um
/// plugin, com canal de plataforma, só para saber um número que já é conhecido
/// na compilação. Um teste confere que as duas não divergem — é o que torna a
/// repetição segura.
const String versaoApp = '1.2.1';

/// Onde se pergunta qual é a última versão publicada.
///
/// O endpoint de `releases/latest` do GitHub exclui rascunhos e
/// pré-lançamentos: o que ele devolve é uma versão de verdade.
const String enderecoUltimaVersao =
    'https://api.github.com/repos/guilhermefeitosa66/slap-mobile/releases/latest';

/// Para onde o aviso leva: a página explica como instalar, o que o arquivo
/// solto de uma release não faz.
const String enderecoComoAtualizar =
    'https://guilhermefeitosa66.github.io/slap-mobile/';

/// Curto: isto roda na abertura, sem ninguém pedir. Uma consulta que demora
/// não pode ser percebida por quem só quer começar a levantar.
const Duration tempoLimiteVerificacao = Duration(seconds: 8);

/// Uma versão publicada mais nova que a instalada.
class AtualizacaoDisponivel {
  final String versao;
  final String endereco;

  const AtualizacaoDisponivel({required this.versao, required this.endereco});
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

/// Os números de `v1.2.3`, `1.2.3+4`, `SLAP 1.2`: `[1, 2, 3]`.
List<int> _numeros(String bruto) {
  final achado = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(bruto);
  if (achado == null) return const [];
  return [for (final parte in achado.group(1)!.split('.')) int.parse(parte)];
}

/// Pergunta ao GitHub se há versão mais nova.
///
/// **Nunca lança.** Isto roda sozinho a cada abertura: sem rede, com a API
/// fora do ar, com o limite de requisições estourado ou com o formato da
/// resposta mudado, o resultado é "nada a avisar" e o aplicativo abre igual.
/// O levantamento funciona sem internet por projeto, e uma verificação de
/// versão não é motivo para contradizer isso.
class VerificadorAtualizacao {
  /// Como buscar o corpo de uma resposta. Trocável no teste, que não tem — e
  /// não deve ter — rede.
  final Future<String?> Function(Uri endereco) buscar;

  VerificadorAtualizacao({Future<String?> Function(Uri)? buscar})
    : buscar = buscar ?? _buscarPorHttp;

  /// A versão mais nova, se houver. Nulo quando não há, ou quando não deu
  /// para saber — que para quem está abrindo o aplicativo é a mesma coisa.
  Future<AtualizacaoDisponivel?> verificar({
    String versaoAtual = versaoApp,
    String endereco = enderecoUltimaVersao,
  }) async {
    try {
      final corpo = await buscar(Uri.parse(endereco));
      if (corpo == null) return null;

      final json = jsonDecode(corpo);
      if (json is! Map) return null;

      final publicada = (json['tag_name'] ?? json['name'])?.toString();
      if (publicada == null || publicada.isEmpty) return null;
      if (!versaoEhMaisNova(publicada, versaoAtual)) return null;

      return AtualizacaoDisponivel(
        versao: _soONumero(publicada),
        endereco: enderecoComoAtualizar,
      );
    } catch (_) {
      // Qualquer falha é "nada a avisar". Ver o comentário da classe.
      return null;
    }
  }

  /// `v1.2.0`, `SLAP 1.2.0` e `1.2.0+7` viram `1.2.0`: o que a pessoa vê na
  /// tela é o número, sem a convenção de tag em volta dele.
  static String _soONumero(String tag) => _numeros(tag).join('.');
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
