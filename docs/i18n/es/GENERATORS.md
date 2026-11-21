**Idiomas:** [English](../../GENERATORS.md) · [Português (BR)](../pt-BR/GENERATORS.md) · Español · [中文](../zh-CN/GENERATORS.md)

> Traducción de [GENERATORS.md](../../GENERATORS.md). En caso de discrepancia, prevalece la versión en inglés.

# Escribir generadores

La mayoría de las propiedades no necesitan código de generador: los tipos se generan a partir de su definición. Esta guía cubre lo que es automático, cuándo escribir un generador y la única regla que todo generador debe seguir. Cada fragmento está en [`examples/generators.nim`](../../../examples/generators.nim), compilado y ejecutado en CI. Diseño: [ADR-0013](../../decisions/0013-derived-generators.md).

## 1. Nada que escribir

`forAll(x in T)` funciona para:

| `T` | Se genera | Se reduce hacia |
|---|---|---|
| enteros, `range`, floats, `bool`, `char`, enums | todo el dominio, casos límite a menudo | 0, `false`, el primer valor |
| `string`, `seq`, `array`, `set`, tuplas, `Option` | elemento a elemento | más cortos, elementos más simples, `none` |
| `Table`, `OrderedTable`, `HashSet` | entradas a partir de sus tipos | menos entradas, más simples |
| **objetos** | campo a campo, **campos privados incluidos** | cada campo en su valor más simple |
| **case objects** | una rama, después sus campos | la primera rama |
| **tipos `distinct`** | a partir de su tipo base | el valor más simple del tipo base |
| **objetos `ref`** | `nil` o un objeto nuevo | `nil` |
| **tipos recursivos** | árboles acotados por `maxDepth` (por defecto 5) | el árbol más pequeño |

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

Los tipos de otros módulos funcionan sin exportar sus campos. Un campo cuyo tipo no tiene generador (un `proc`, un `ptr`, un lock) detiene la compilación con un mensaje que nombra el campo. Un case object cuyo discriminante es un tipo `range` no se puede derivar con Nim 2.2.4, y el mensaje del compilador lo dice: usa un enum, o escribe `arbitrary`.

Los datos recursivos se acotan durante la exploración: los campos `ref` son `nil` más a menudo cuanto más profundos están, y las colecciones anidadas se acortan, así que los árboles se mantienen pequeños (`initSettings(maxDepth = ...)` cambia el límite). La reducción no se ve afectada.

## 2. Cuando campos aleatorios forman objetos inválidos: escribe `arbitrary`

La derivación rellena cada campo de forma independiente. Cuando los campos deben concordar (un inicio antes de un fin, un total igual a la suma de las líneas, un ID que existe en una lista), escribe `arbitrary` para el tipo. Siempre tiene prioridad sobre la derivación, y toda propiedad que use el tipo lo obtiene.

```nim
type DateRange = object
  first, last: int            # invariant: first <= last

proc arbitrary(src: ChoiceSource; t: typedesc[DateRange]): DateRange =
  let first = src.drawInt(0, 36_500)
  let length = src.drawInt(0, 365)
  DateRange(first: first, last: first + length)
```

**Construye valores válidos; no filtres los inválidos.** `filter` y `assume` descartan casos. Por encima de una pequeña tasa de rechazo la ejecución se ralentiza, y después se detiene con un mensaje que sugiere esto. Sortear `length` en lugar de `last` hace válido cada valor.

## 3. La única regla: una elección menor debe significar un valor más simple

Los generadores nunca ven números aleatorios, solo **elecciones**: enteros sin signo sorteados de la fuente de elecciones. La reducción hace las elecciones registradas más pequeñas y más cortas, y después las repite ([ADR-0001](../../decisions/0001-integrated-shrinking-on-choice-sequences.md)). Para que eso dé valores más simples, la elección 0 debe ser el valor más simple, y las elecciones menores, valores más simples. Cada primitiva de sorteo ya cumple la regla:

| Primitiva | La elección 0 da |
|---|---|
| `drawInt(lo, hi)` | el valor de `lo .. hi` más cercano a 0 |
| `drawBool()` | `false` |
| `drawIndex(n)` | 0: pon primero la alternativa más simple |
| `drawFloat`, `drawFloatRange` | 0.0 |
| `initMany` + `more` | ningún elemento más |
| `drawRune()` | `'a'` |

Así que la regla se reduce a dos decisiones tuyas:

- **Pon primero la alternativa más simple**: `elements([common, rare])`, `frequency([(9, usual), (1, unusual)])`, un enum cuyo primer valor es el habitual.
- **Sortea lo que hace válido el valor**, como `length` arriba, en lugar de sortear libremente y arreglarlo después: un "arreglo" puede convertir una elección menor en un valor mayor.

## 4. Valores generadores: combinadores

Cuando el tipo no basta (un rango, un alfabeto, una distribución), pasa un valor generador en lugar de un tipo:

```nim
let prices = frequency([(8, ints(1, 10_000)), (1, constant(0)), (1, ints(1_000_000, 10_000_000))])
let usernames = identifiers(maxLen = 12)
let labels = tables(identifiers(8), ints(0, 99), maxLen = 5)

forAll(price in prices, user in usernames, l in labels): ...
```

| Combinador | Valores |
|---|---|
| `ints(lo, hi, near = [...])` | enteros; `near` lista fronteras de tu dominio para probarlas a menudo |
| `frequency([(w, g), ...])` | uno de los generadores, por peso |
| `elements([...])`, `oneOf(...)`, `constant(v)` | elecciones fijas |
| `strings(alphabet, ...)` (por ejemplo `strings(alphanumeric, ...)`), `identifiers(...)`, `unicodeStrings(...)` | texto, incluido UTF-8 válido en todos los planos |
| `seqs`, `tables`, `hashSets`, `optionals` | contenedores de valores generados |
| `uniqueSeqs(g, ...)`, `sortedSeqs(g, ...)` | secuencias de valores distintos, o en orden ascendente |
| `sized(proc(n: int): Gen[T] = ...)`, `g.resize(n)` | un generador que depende del tamaño actual, o un tamaño fijo |
| `g.map(f)`, `g.filter(p)`, `g.flatMap(f)` | transformaciones (la reducción pasa a través de ellas) |
| `recursive(base, extend, maxDepth)` | árboles: cada nivel es `base` o un nivel más profundo |
| `newGen(proc(src: ChoiceSource): T = ...)` | cualquier cosa, a partir de las primitivas de sorteo |

Los generadores recursivos reciben el generador del nivel inferior:

```nim
let exprs = recursive(leaf(), proc(inner: Gen[Expr]): Gen[Expr] =
  newGen(proc(src: ChoiceSource): Expr =
    let times = src.drawBool()           # false ('+') is the simpler one
    let (l, r) = (inner.generate(src), inner.generate(src))
    if times: Expr(op: '*', lhs: l, rhs: r) else: Expr(op: '+', lhs: l, rhs: r)))
```

### Colecciones de valores distintos y ordenadas

Dos formas aparecen con tanta frecuencia que tienen sus propios generadores. Ambas se reducen como `seqs` y conservan su forma durante la reducción:

```nim
forAll(ids in uniqueSeqs(ints(1, 10_000), maxLen = 20)):   # no duplicates
  check buildIndex(ids).len == ids.len

forAll(xs in sortedSeqs(ints(), minLen = 1)):              # ascending
  check lowerBound(xs, xs[0]) == 0                        # std/algorithm
```

`uniqueSeqs` vuelve a sortear cuando un valor repite uno anterior, hasta `maxTries` (100) veces por elemento, y después descarta el caso como un `filter`. Con pocos valores distintos (`uniqueSeqs(bools(), minLen = 3)`) la propiedad se rinde y lo dice. `sortedSeqs` ordena después de generar, así que nunca descarta. Prefiérelos a `assume(xs.isSorted)`, que [se rinde](TROUBLESHOOTING.md#gave-up-after-n-passing-cases).

### El tamaño: `sized` y `resize`

El tamaño crece de 0 en el primer caso a `maxSize` en el último. Las colecciones y los enteros nativos ya lo siguen; `sized` se lo da a tu propio generador, y `resize` lo fija para un generador:

```nim
# A square matrix whose side follows the size.
let matrices = sized(proc(n: int): Gen[seq[seq[int]]] =
  let side = max(1, n div 10)
  seqs(seqs(ints(0, 9), side, side), side, side))

# Short lists, whatever the size of the case.
let shortLists = gen(seq[int]).resize(3)
```

El tamaño que ve `sized` se registra con el caso, así que la reducción y la repetición ven el mismo tamaño (la reducción puede bajarlo, lo que hace los valores más simples). Úsalo como cota superior o como escala, como arriba.

## 5. Fijar casos conocidos

`example(...)` ejecuta valores fijos antes de cualquier caso aleatorio, uno por variable. Úsalo para una regresión que nunca debe volver, o un caso que nombra la especificación:

```nim
forAll(user in usernames, example("root"), example("a")):
  check user.len >= 1
```

Los fallos también se guardan en `.proptest/db/` y se repiten primero en las siguientes ejecuciones, hasta que pasan tres veces seguidas ([ADR-0014](../../decisions/0014-failure-database-and-examples.md)).

## 6. Imprimir valores

Los informes imprimen las entradas con `$` cuando existe, y los informes con estado imprimen los argumentos de los comandos como código Nim (`showCode`): objetos como `Payment(id: 0, amount: 0, ...)`, tablas como `{1: "a"}.toTable`, valores `ref` con `nil` donde están vacíos. Si el `$` de un tipo no es legible o su constructor no es visible donde se pegará el informe, sobrecarga `show` o `showCode` para él.
