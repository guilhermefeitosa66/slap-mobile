import 'package:flutter_test/flutter_test.dart';
import 'package:slap_mobile/data/repos/inventarios.dart';
import 'package:slap_mobile/domain/patrimonio.dart';
import 'package:slap_mobile/domain/valores.dart';
import 'package:slap_mobile/features/reports/relatorios.dart';

/// O que vai para quem atualiza o SUAP.
void main() {
  final inventario = Inventario(
    id: 'i',
    nome: 'Campus',
    ano: 2026,
    criadoEm: DateTime(2026),
    dispositivoOrigem: 'd',
    chaveSync: 'k',
  );

  const itens = [
    // OK: mesma sala, estado do SUAP mantido.
    Patrimonio(
      id: '1',
      inventarioId: 'i',
      tombo: '23254',
      codigoBarras: '-19281',
      descricao: 'ESTABILIZADOR',
      salaOriginal: 'Biblioteca',
      conservacaoOriginal: EstadoConservacao.bom,
      verificado: true,
    ),
    // Divergente no estado.
    Patrimonio(
      id: '2',
      inventarioId: 'i',
      tombo: '65789',
      codigoBarras: '23254',
      descricao: 'MONITOR',
      salaOriginal: 'Biblioteca',
      conservacaoOriginal: EstadoConservacao.bom,
      verificado: true,
      conservacao: EstadoConservacao.antieconomico,
    ),
    // Não localizado.
    Patrimonio(
      id: '3',
      inventarioId: 'i',
      tombo: '61816',
      codigoBarras: '19281',
      descricao: 'MESA',
      conservacaoOriginal: EstadoConservacao.ocioso,
    ),
  ];

  Relatorio gerar(TipoRelatorio tipo) => GeradorRelatorios.gerar(
    tipo: tipo,
    inventario: inventario,
    patrimonios: itens,
  );

  test('toda linha tem uma célula por coluna do cabeçalho', () {
    // Até a versão 1.2.4 o cabeçalho ainda tinha "Ordem", que tinha saído
    // das linhas: cada valor caía na coluna ao lado.
    for (final tipo in TipoRelatorio.values) {
      final r = gerar(tipo);
      expect(r.linhas, isNotEmpty, reason: tipo.titulo);
      for (final linha in r.linhas) {
        expect(linha.length, r.cabecalho.length, reason: tipo.titulo);
      }
      expect(r.cabecalho, isNot(contains('Ordem')), reason: tipo.titulo);
    }
  });

  test('o número vem com o sinal do SUAP, ao lado do tombo', () {
    final r = gerar(TipoRelatorio.completo);
    final tombo = r.cabecalho.indexOf('Tombo');
    final numero = r.cabecalho.indexOf('Número');
    final linha = r.linhas.firstWhere((l) => l[tombo] == '23254');
    expect(linha[numero], '-19281');
  });

  test('a divergência de estado sai com os rótulos do SUAP', () {
    final r = gerar(TipoRelatorio.divergencias);
    final linha = r.linhas.single;
    String celula(String coluna) => linha[r.cabecalho.indexOf(coluna)];
    expect(celula('Tombo'), '65789');
    expect(celula('Campo'), 'Estado de conservação');
    expect(celula('Valor no SUAP'), 'Bom');
    expect(celula('Valor encontrado'), 'Antieconômico');
    expect(celula('Requer atenção'), 'Sim');
  });

  test('não localizados levam o estado que o SUAP registra', () {
    final r = gerar(TipoRelatorio.naoLocalizados);
    expect(r.linhas.single[r.cabecalho.indexOf('Estado (SUAP)')], 'Ocioso');
  });
}
