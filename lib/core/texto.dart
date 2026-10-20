/// Caracteres de controle que o XML 1.0 — e, com ele, o XLSX — não aceita.
///
/// Tab, quebra de linha e retorno de carro ficam: são texto legítimo numa
/// descrição de várias linhas. Os demais aparecem em cadastros antigos do
/// SUAP e chegam ao aparelho pela planilha de carga. Gravados num relatório
/// `.xlsx`, viram `&#x2;` no XML e deixam o arquivo ilegível para o Excel, o
/// LibreOffice e o próprio SUAP, que recusa a planilha inteira.
final _controleInvalido = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]');

/// O `\x02` entre letras ou dígitos está no lugar de um hífen: "TRUE
/// ON\x02LINE", "MODELO HI\x02WALL". No fim de uma linha ou do texto ("COR
/// BEGE\x02") é só sujeira e sai, como os demais.
final _hifenPerdido = RegExp(r'(?<=[0-9A-Za-zÀ-ÿ])\x02(?=[0-9A-Za-zÀ-ÿ])');

/// [texto] sem os caracteres de controle que o XLSX não aceita, com o hífen
/// de volta onde o `\x02` o substituía.
String semCaracteresDeControle(String texto) =>
    texto.replaceAll(_hifenPerdido, '-').replaceAll(_controleInvalido, '');
