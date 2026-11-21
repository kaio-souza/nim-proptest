**Idiomas:** [English](../../GENERATORS.md) · Português (BR) · [Español](../es/GENERATORS.md) · [中文](../zh-CN/GENERATORS.md)

> Tradução de [GENERATORS.md](../../GENERATORS.md). Em caso de divergência, vale a versão em inglês.

# Escrevendo geradores

A maioria das propriedades não precisa de código de gerador: os tipos são gerados a partir da sua definição. Este guia mostra o que é automático, quando escrever um gerador e a única regra que todo gerador precisa seguir. Todos os trechos estão em [`examples/generators.nim`](../../../examples/generators.nim), compilado e executado no CI. Design: [ADR-0013](../../decisions/0013-derived-generators.md).

## 1. Nada a escrever

`forAll(x in T)` funciona para:

| `T` | Gerado | Reduz em direção a |
|---|---|---|
| inteiros, `range`, floats, `bool`, `char`, enums | o domínio inteiro, casos de borda com frequência | 0, `false`, o primeiro valor |
| `string`, `seq`, `array`, `set`, tuplas, `Option` | elemento a elemento | mais curtos, elementos mais simples, `none` |
| `Table`, `OrderedTable`, `HashSet` | entradas a partir dos seus tipos | menos entradas, mais simples |
| **objetos** | campo a campo, **campos privados incluídos** | todos os campos no mais simples |
| **case objects** | um ramo, depois seus campos | o primeiro ramo |
| **tipos `distinct`** | a partir do tipo base | o valor mais simples do tipo base |
| **objetos `ref`** | `nil` ou um novo objeto | `nil` |
| **tipos recursivos** | árvores limitadas por `maxDepth` (padrão 5) | a menor árvore |

```nim
type
  Currency = enum usd, eur, brl
  Payment = object
    id: int64
    amount: int
    currency: Currency
    note: string
  EventKind = enum paid, refunded, cancelled
  Event = object
    at: int
    case kind: EventKind
    of paid: payment: Payment
    of refunded: refundOf: int64
    of cancelled: reason: string
  Expr = ref object
    case op: char
    of '+', '*': lhs, rhs: Expr
    else: value: int

forAll(p in Payment, e in Event, x in Expr): ...
```

Tipos de outros módulos funcionam sem exportar seus campos. Um campo cujo tipo não tem gerador (um `proc`, um `ptr`, um lock) interrompe a compilação com uma mensagem que nomeia o campo. Um case object cujo discriminante é um tipo `range` não pode ser derivado com o Nim 2.2.4, e a mensagem do compilador diz isso: use um enum, ou escreva `arbitrary`.

Dados recursivos são limitados durante a exploração: campos `ref` são `nil` com mais frequência quanto mais fundo estão, e coleções aninhadas ficam mais curtas, então as árvores continuam pequenas (`initSettings(maxDepth = ...)` muda o limite). O shrinking não é afetado.

## 2. Quando campos aleatórios formam objetos inválidos: escreva `arbitrary`

A derivação preenche cada campo de forma independente. Quando os campos precisam concordar (um início antes de um fim, um total igual à soma das linhas, um ID que existe numa lista), escreva `arbitrary` para o tipo. Ele sempre tem prioridade sobre a derivação, e toda propriedade que usa o tipo passa a usá-lo.

```nim
type DateRange = object
  first, last: int            # invariant: first <= last

proc arbitrary(src: ChoiceSource; t: typedesc[DateRange]): DateRange =
  let first = src.drawInt(0, 36_500)
  let length = src.drawInt(0, 365)
  DateRange(first: first, last: first + length)
```

**Construa valores válidos; não filtre os inválidos.** `filter` e `assume` jogam casos fora. Acima de uma pequena taxa de rejeição a execução fica lenta, e então para com uma mensagem sugerindo isto. Sortear `length` em vez de `last` torna todo valor válido.

## 3. A única regra: uma escolha menor deve significar um valor mais simples

Os geradores nunca veem números aleatórios, só **escolhas**: inteiros sem sinal sorteados da fonte de escolhas. O shrinking torna as escolhas registradas menores e mais curtas, e então as repete ([ADR-0001](../../decisions/0001-integrated-shrinking-on-choice-sequences.md)). Para isso dar valores mais simples, a escolha 0 precisa ser o valor mais simples, e escolhas menores, valores mais simples. Toda primitiva de sorteio já segue a regra:

| Primitiva | A escolha 0 dá |
|---|---|
| `drawInt(lo, hi)` | o valor de `lo .. hi` mais próximo de 0 |
| `drawBool()` | `false` |
| `drawIndex(n)` | 0: ponha a alternativa mais simples primeiro |
| `drawFloat`, `drawFloatRange` | 0.0 |
| `initMany` + `more` | nenhum elemento a mais |
| `drawRune()` | `'a'` |

Então a regra se resume a duas escolhas suas:

- **Ponha a alternativa mais simples primeiro**: `elements([common, rare])`, `frequency([(9, usual), (1, unusual)])`, um enum cujo primeiro valor é o padrão.
- **Sorteie o que torna o valor válido**, como `length` acima, em vez de sortear livremente e consertar depois: um "conserto" pode transformar uma escolha menor num valor maior.

## 4. Valores geradores: combinadores

Quando o tipo não basta (um intervalo, um alfabeto, uma distribuição), passe um valor gerador em vez de um tipo:

```nim
let prices = frequency([(8, ints(1, 10_000)), (1, constant(0)), (1, ints(1_000_000, 10_000_000))])
let usernames = identifiers(maxLen = 12)
let labels = tables(identifiers(8), ints(0, 99), maxLen = 5)

forAll(price in prices, user in usernames, l in labels): ...
```

| Combinador | Valores |
|---|---|
| `ints(lo, hi, near = [...])` | inteiros; `near` lista fronteiras do seu domínio para tentar com frequência |
| `frequency([(w, g), ...])` | um dos geradores, por peso |
| `elements([...])`, `oneOf(...)`, `constant(v)` | escolhas fixas |
| `strings(alphabet, ...)` (por exemplo `strings(alphanumeric, ...)`), `identifiers(...)`, `unicodeStrings(...)` | texto, inclusive UTF-8 válido em todos os planos |
| `seqs`, `tables`, `hashSets`, `optionals` | contêineres de valores gerados |
| `uniqueSeqs(g, ...)`, `sortedSeqs(g, ...)` | sequências de valores distintos, ou em ordem crescente |
| `sized(proc(n: int): Gen[T] = ...)`, `g.resize(n)` | um gerador que depende do tamanho atual, ou um tamanho fixo |
| `g.map(f)`, `g.filter(p)`, `g.flatMap(f)` | transformações (o shrinking passa por elas) |
| `recursive(base, extend, maxDepth)` | árvores: cada nível é `base` ou um nível mais fundo |
| `newGen(proc(src: ChoiceSource): T = ...)` | qualquer coisa, a partir das primitivas de sorteio |

Geradores recursivos recebem o gerador do nível de baixo:

```nim
let exprs = recursive(leaf(), proc(inner: Gen[Expr]): Gen[Expr] =
  newGen(proc(src: ChoiceSource): Expr =
    let times = src.drawBool()           # false ('+') is the simpler one
    let (l, r) = (inner.generate(src), inner.generate(src))
    if times: Expr(op: '*', lhs: l, rhs: r) else: Expr(op: '+', lhs: l, rhs: r)))
```

### Coleções distintas e ordenadas

Dois formatos aparecem com frequência suficiente para terem seus próprios geradores. Ambos reduzem como `seqs` e mantêm seu formato durante o shrinking:

```nim
forAll(ids in uniqueSeqs(ints(1, 10_000), maxLen = 20)):   # no duplicates
  check buildIndex(ids).len == ids.len

forAll(xs in sortedSeqs(ints(), minLen = 1)):              # ascending
  check lowerBound(xs, xs[0]) == 0                        # std/algorithm
```

`uniqueSeqs` sorteia de novo quando um valor repete um anterior, até `maxTries` (100) vezes por elemento, e então descarta o caso como um `filter`. Com poucos valores distintos (`uniqueSeqs(bools(), minLen = 3)`) a propriedade desiste e diz isso. `sortedSeqs` ordena depois de gerar, então nunca descarta. Prefira-os a `assume(xs.isSorted)`, que [desiste](TROUBLESHOOTING.md#gave-up-after-n-passing-cases).

### O tamanho: `sized` e `resize`

O tamanho cresce de 0 no primeiro caso até `maxSize` no último. Coleções e inteiros nativos já o seguem; `sized` o entrega ao seu próprio gerador, e `resize` o fixa para um gerador:

```nim
# A square matrix whose side follows the size.
let matrices = sized(proc(n: int): Gen[seq[seq[int]]] =
  let side = max(1, n div 10)
  seqs(seqs(ints(0, 9), side, side), side, side))

# Short lists, whatever the size of the case.
let shortLists = gen(seq[int]).resize(3)
```

O tamanho que `sized` vê é registrado com o caso, então o shrinking e a repetição veem o mesmo tamanho (o shrinking pode diminuí-lo, o que torna os valores mais simples). Use-o como limite superior ou escala, como acima.

## 5. Fixando casos conhecidos

`example(...)` roda valores fixos antes de qualquer caso aleatório, um por variável. Use para uma regressão que nunca pode voltar, ou um caso que a especificação nomeia:

```nim
forAll(user in usernames, example("root"), example("a")):
  check user.len >= 1
```

As falhas também são salvas em `.proptest/db/` e repetidas primeiro nas próximas execuções, até passarem três vezes seguidas ([ADR-0014](../../decisions/0014-failure-database-and-examples.md)).

## 6. Imprimindo valores

Os relatórios imprimem as entradas com `$` quando ele existe, e os relatórios stateful imprimem os argumentos dos comandos como código Nim (`showCode`): objetos como `Payment(id: 0, amount: 0, ...)`, tabelas como `{1: "a"}.toTable`, valores `ref` com `nil` onde estão vazios. Se o `$` de um tipo não é legível ou seu construtor não é visível onde o relatório será colado, sobrecarregue `show` ou `showCode` para ele.
