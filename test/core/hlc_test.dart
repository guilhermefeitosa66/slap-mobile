import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/core/hlc.dart';

void main() {
  group('Hlc.enviar', () {
    test('acompanha o relógio de parede quando ele avança', () {
      final inicial = Hlc(1000, 5, 'A');
      final proximo = Hlc.enviar(inicial, agora: 2000);

      expect(proximo.millis, 2000);
      expect(proximo.counter, 0, reason: 'contador reinicia quando o tempo anda');
    });

    test('usa o contador lógico quando o relógio não avançou', () {
      // O caso comum no levantamento: várias leituras dentro do mesmo
      // milissegundo.
      final inicial = Hlc(1000, 0, 'A');
      final proximo = Hlc.enviar(inicial, agora: 1000);

      expect(proximo.millis, 1000);
      expect(proximo.counter, 1);
    });

    test('nunca anda para trás com relógio do sistema atrasado', () {
      final inicial = Hlc(5000, 0, 'A');
      final proximo = Hlc.enviar(inicial, agora: 3000);

      expect(proximo.millis, 5000);
      expect(proximo.counter, 1);
      expect(proximo > inicial, isTrue);
    });

    test('leituras seguidas são sempre crescentes', () {
      var hlc = Hlc.zero('A');
      final emitidos = <Hlc>[];
      for (var i = 0; i < 500; i++) {
        hlc = Hlc.enviar(hlc, agora: 1000);
        emitidos.add(hlc);
      }
      for (var i = 1; i < emitidos.length; i++) {
        expect(emitidos[i] > emitidos[i - 1], isTrue);
      }
    });
  });

  group('Hlc.receber', () {
    test('puxa o relógio local para frente ao receber operação mais nova', () {
      final local = Hlc(1000, 0, 'A');
      final remoto = Hlc(5000, 3, 'B');

      final resultado = Hlc.receber(local, remoto, agora: 1000);

      expect(resultado.millis, 5000);
      expect(resultado.counter, 4);
      expect(resultado.nodeId, 'A', reason: 'o relógio continua sendo o nosso');
    });

    test('operação posterior a uma recebida é maior que ela', () {
      // É o que faz a ordem causal se propagar mesmo com relógio atrasado.
      final local = Hlc(1000, 0, 'A');
      final remoto = Hlc(9000, 0, 'B');

      final depoisDeReceber = Hlc.receber(local, remoto, agora: 1000);
      final nossaProxima = Hlc.enviar(depoisDeReceber, agora: 1000);

      expect(nossaProxima > remoto, isTrue);
    });

    test('rejeita relógio absurdamente adiantado', () {
      final local = Hlc(1000, 0, 'A');
      final remoto = Hlc(1000 + const Duration(hours: 2).inMilliseconds, 0, 'B');

      expect(
        () => Hlc.receber(local, remoto, agora: 1000),
        throwsA(isA<RelogioForaDeSincronia>()),
      );
    });

    test('aceita desvio pequeno, que é o normal entre celulares', () {
      final local = Hlc(1000, 0, 'A');
      final remoto = Hlc(1000 + const Duration(seconds: 30).inMilliseconds, 0, 'B');

      expect(() => Hlc.receber(local, remoto, agora: 1000), returnsNormally);
    });
  });

  group('codificação', () {
    test('ida e volta preserva o valor', () {
      final original = Hlc(1758649800000, 42, 'dispositivo-abc');
      expect(Hlc.decodificar(original.codificar()), original);
    });

    test('ordem alfabética do texto é a ordem do relógio', () {
      // É o que permite ordenar e filtrar operações em SQL sem decodificar.
      final relogios = [
        Hlc(1000, 0, 'A'),
        Hlc(1000, 1, 'A'),
        Hlc(1000, 1, 'B'),
        Hlc(2000, 0, 'A'),
        Hlc(999999999999999, 0, 'A'),
      ];

      final porObjeto = [...relogios]..sort();
      final porTexto = [...relogios]
        ..sort((a, b) => a.codificar().compareTo(b.codificar()));

      expect(porTexto.map((h) => h.codificar()), porObjeto.map((h) => h.codificar()));
    });

    test('desempata por dispositivo, dando ordem total', () {
      // Sem isto, duas réplicas poderiam escolher vencedores diferentes para o
      // mesmo conflito e nunca convergir.
      final a = Hlc(1000, 0, 'aparelho-a');
      final b = Hlc(1000, 0, 'aparelho-b');

      expect(a < b, isTrue);
      expect(b > a, isTrue);
    });
  });
}
