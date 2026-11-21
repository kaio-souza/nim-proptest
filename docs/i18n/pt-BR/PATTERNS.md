**Idiomas:** [English](../../PATTERNS.md) · Português (BR) · [Español](../es/PATTERNS.md) · [中文](../zh-CN/PATTERNS.md)

> Tradução de [PATTERNS.md](../../PATTERNS.md). Em caso de divergência, vale a versão em inglês.

# Livro de padrões de propriedades

A parte difícil dos testes baseados em propriedades raramente é a biblioteca. É decidir **o que verificar** quando você não consegue escrever a saída esperada para uma entrada aleatória. Estes padrões cobrem a maioria das propriedades reais. Cada um tem uma versão que passa em [`examples/patterns.nim`](../../../examples/patterns.nim), compilado e executado no CI.

## Ida e volta (round trip)

Se uma função desfaz a outra, compô-las devolve a entrada. Use para serialização, parsing, codificação, compressão e conversões.

```nim
forAll(xs in seq[int]):
  check decode(encode(xs)) == xs
```

Pega perda de precisão, bugs de escape e entradas vazias ou de borda (`@[]`, `low(int)`) que exemplos escritos à mão deixam passar.

## Oráculo (implementação de referência)

Compare o código com uma versão mais lenta e obviamente correta: uma função otimizada contra um loop ingênuo, uma implementação nova contra a antiga, um cache contra o cálculo direto.

```nim
forAll(xs in seq[int]):
  check fastSum(xs) == oracleSum(xs)
```

Um teste stateful é esse mesmo padrão aplicado a uma sequência de operações: o modelo é o oráculo ([STATEFUL.md](STATEFUL.md)).

## Invariante

Quando a saída exata é desconhecida, algumas de suas propriedades não são: uma ordenação mantém o comprimento e ordena os elementos; uma árvore balanceada continua balanceada; um total continua não negativo.

```nim
forAll(xs in seq[int]):
  let s = xs.sorted
  check s.len == xs.len
  for i in 1 ..< s.len: check s[i - 1] <= s[i]
```

## Idempotência

Aplicar a operação duas vezes é o mesmo que aplicá-la uma vez: normalizar, remover duplicatas, formatar, ligar uma flag, um `PUT` HTTP.

```nim
forAll(xs in seq[int]):
  check dedupe(dedupe(xs)) == dedupe(xs)
```

## Relação metamórfica

Você não sabe `f(x)`, mas sabe como ele muda quando `x` muda de um jeito conhecido. Acrescentar um elemento o soma à soma, embaralhar não muda um conjunto, escalar a entrada escala uma saída linear.

```nim
forAll(xs in seqs(ints(-1000, 1000)), k in ints(-1000, 1000)):
  check oracleSum(xs & @[k]) == oracleSum(xs) + k
```

Limite os valores quando a relação pode estourar: um overflow é um achado real, mas não é aquele de que esta propriedade trata.

## Nunca quebra

A propriedade mais fraca e muitas vezes a mais produtiva: para qualquer entrada, o código ou retorna ou lança o erro que documenta. `Defect`s (índice fora dos limites, overflow, acesso a nil) e exceções inesperadas são falhas.

```nim
forAll(s in string):
  try: discard parseJson(s)
  except JsonParsingError, ValueError: discard
```

## Fronteiras

Os bugs moram onde o domínio muda: a última tentativa, um timeout de exatamente 1000 ms, uma capacidade de 3. Os geradores de inteiros já tentam `0`, `1`, `-1` e os limites do tipo. Para as suas próprias fronteiras:

- **As constantes são mineradas automaticamente.** Literais inteiros e valores `const` usados na propriedade, e literais inteiros em qualquer lugar do arquivo de teste, são propostos como `v - 1`, `v` e `v + 1` durante a exploração ([ADR-0012](../../decisions/0012-bug-finding-power.md)). `initSettings(mineConstants = false)` desliga isso.
- **Diga explicitamente** com `ints(lo, hi, near = [...])` quando a fronteira vem de outro lugar (outro módulo, um arquivo de configuração):

```nim
forAll(attempt in ints(0, 100, near = [maxRetries])):
  if attempt < maxRetries: check backoffMs(attempt) >= 100
  else: check backoffMs(attempt) == -1
```

Nenhum dos dois muda o shrinking: o contraexemplo relatado continua sendo o mais simples.

## Cobertura: garanta que os casos interessantes aconteçam

Uma propriedade que passa não diz nada sobre entradas que nunca foram geradas. `classify` mostra a distribuição; `cover` transforma um requisito numa verificação:

```nim
forAll(initSettings(cases = 300), xs in seq[int]):
  cover(5.0, xs.len == 0, "empty")
  cover(20.0, xs.len >= 10, "ten or more")
  check ...
```

```
Property 'patterns.nim:69' passed 300 cases.
  Statistics (300 cases):
     14.0%  empty  (cover: 5.0% required)
     61.0%  ten or more  (cover: 20.0% required)
```

`cover` só faz a propriedade falhar quando a fração observada está **com confiança** abaixo do requisito (o limite superior de um intervalo de Wilson de 95%). Com casos de menos para ter certeza, imprime um aviso e sugere aumentar `cases`. `label($x.kind)` conta casos por um texto calculado. Numa máquina de estado, `cover` conta sequências, e o relatório também lista quantas vezes cada comando rodou e quantas vezes sua pré-condição o bloqueou.

## Quando é difícil encontrar uma propriedade

- Comece com **nunca quebra**, depois acrescente **ida e volta** e **invariantes**: eles não precisam de valores esperados.
- Se você tem duas implementações, ou uma versão antiga e uma nova, use **oráculo**.
- Se o sistema tem estado (um cache, uma fila, uma conexão, um circuit breaker), use uma **máquina de estado**.
- Se a propriedade só vale para algumas entradas, gere essas entradas diretamente. `assume` e `filter` descartam casos, e descartes demais param a execução com uma mensagem dizendo isso.
