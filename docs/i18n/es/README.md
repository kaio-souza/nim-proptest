**Idiomas:** [English](../../../README.md) · [Português (BR)](../pt-BR/README.md) · Español · [中文](../zh-CN/README.md)

> Traducción del [README en inglés](../../../README.md). En caso de discrepancia, prevalece la versión en inglés.

# proptest

Una **biblioteca de pruebas basadas en propiedades para el lenguaje [Nim](https://nim-lang.org)**, distribuida como paquete Nimble. Enuncia una regla, deja que la biblioteca genere las entradas y obtén la entrada **más pequeña** que la rompe.

> Propiedades sobre tipos nativos y **tus propios objetos sin código de generador**, y pruebas con estado (basadas en modelos), con reducción (shrinking) automática, fallos que se repiten primero en la siguiente ejecución, estadísticas de cobertura y exploración que busca valores frontera. Versión 1.0: la API y los valores generados para una semilla siguen la [política de estabilidad](STABILITY.md). Consulta las [funcionalidades](#features).

## Instalación

```sh
nimble install https://github.com/kaio-souza/nim-proptest
```

O desde un clon: `nimble install` (o `nimble develop` para trabajar en él). Requiere Nim >= 2.2.4; sin dependencias fuera de la biblioteca estándar.

## Inicio rápido

```nim
import proptest, std/[unittest, algorithm]

suite "sorting":
  test "sort is idempotent":
    forAll(xs in seq[int]):
      check xs.sorted.sorted == xs.sorted

  test "custom generators shrink for free":
    let evens = ints(0, 10_000).filter(proc(x: int): bool = x mod 2 == 0)
    forAll(n in evens):
      check n < 100
```

La segunda propiedad es incorrecta, y el informe muestra el contraejemplo **mínimo** (100, no un número par grande cualquiera) y cómo repetirlo:

```
[FAILED] custom generators shrink for free
  Property 'quickstart.nim:20' falsified at case 8 (50 cases passed, 0 discarded).
  Counterexample (1 choices, 9 shrink executions):
    n = 100
  Error: [PropertyFailed] check failed: n < 100
      n was 100
  Location: quickstart.nim:21
  Replay: PROPTEST_SEED=17542877672211577899 ./quickstart
```

Versiones ejecutables: [`examples/quickstart.nim`](../../../examples/quickstart.nim) (con bugs plantados), [`examples/tour.nim`](../../../examples/tour.nim) (todas las funcionalidades de abajo), [`examples/generators.nim`](../../../examples/generators.nim) (la guía de generadores), [`examples/patterns.nim`](../../../examples/patterns.nim) (el recetario de patrones) y [`examples/stateful.nim`](../../../examples/stateful.nim) (el tutorial con estado); compiladas y ejecutadas en CI.

## Escribir propiedades

### Variables: `name in source`

Cada variable es un **tipo** (el generador se infiere) o un **valor generador**:

```nim
forAll(xs in seq[int], s in string, flag in bool): ...     # types
forAll(n in ints(0, 100), word in strings("abc", 1, 5)): ... # generator values
```

Las fuentes se evalúan una vez por propiedad. `forAll(x: int)` no puede funcionar: Nim interpreta una llamada cuyos argumentos parecen todos `name: value` como un constructor de objeto, antes de que se ejecute ninguna macro.

### Aserciones

Dentro de `forAll`, `check` y `require` se reescriben para que un caso que falla se capture en silencio y solo se informe del fallo final ya reducido (una vez). `doAssert`, cualquier excepción lanzada y los `Defect` (errores de índice, desbordamientos...) también cuentan como fallos.

### Descartar casos: `assume`

```nim
forAll(a in ints(-1000, 1000), b in ints(-1000, 1000)):
  assume(b != 0)
  check a mod b == a - (a div b) * b
```

Demasiados casos descartados detienen la ejecución con un informe de "gave up". Es preferible generar valores válidos directamente que usar `assume` y `filter`.

### Ajustes

Pasa un valor `initSettings(...)` entre los argumentos. La mayoría de las propiedades no necesitan ninguno. Las tablas de abajo son un resumen; [CONFIGURATION.md](CONFIGURATION.md) tiene recetas (CI, ejecuciones nocturnas, repetición, propiedades lentas), lo que cuesta cada ajuste y qué ajustes deben coincidir para que una semilla se repita.

```nim
forAll(initSettings(cases = 500, maxShrinks = 5_000), x in int8): ...
```

| Ajuste | Por defecto | Significado |
|---|---|---|
| `cases` | 100 | Casos a ejecutar |
| `maxSteps` | 50 | Pruebas con estado: comandos por secuencia |
| `maxDepth` | 5 | Anidamiento de datos recursivos durante la exploración |
| `maxShrinks` | 2000 | Presupuesto de ejecuciones para reducir cada fallo |
| `maxSize` | 100 | Tamaño alcanzado en el último caso (acota la longitud típica de las colecciones) |
| `maxDiscardRatio` | 10 | Se rinde tras `cases × ratio` casos descartados |
| `maxFailures` | 3 | Fallos distintos informados por propiedad |
| `maxChoices` | 8192 | Elecciones aleatorias por caso; los casos más grandes se descartan |
| `deadline` | 0 (desactivado) | Límite por caso en ms: los casos más lentos fallan y se reducen |
| `timeBudget` | 0 (ninguno) | Límite de tiempo de la exploración en ms; se detiene de forma controlada y lo indica |
| `shrinkTimeBudget` | 0 (ninguno) | Límite de tiempo de la reducción por fallo en ms; conserva el mejor hasta entonces |
| `edgeBias` | 0.25 | Proporción de propuestas de casos límite (límites, 0, 1, floats especiales, colecciones vacías y de un elemento) |
| `mineConstants` | true | Constantes enteras de la propiedad y del archivo de pruebas como pistas de frontera |
| `swarm` | true | Pruebas con estado: la mitad de las secuencias omite algunos comandos |
| `verbosity` | `vNormal` | `vQuiet`, `vNormal`, `vVerbose` (cada caso, cada estadística), `vDebug` (pasos de reducción) |
| `suppress` | `{}` | Health checks que omitir: `hcLargeData`, `hcFewDistinct`, `hcSlowGeneration` |
| `hangTimeout` | 0 (desactivado) | Watchdog: un caso que tarda más (ms) se informa y se guarda, y el programa termina con código 1 |
| `report` | `PROPTEST_REPORT` | Archivo JSON Lines al que se añade cada resultado; vacío: ninguno |
| `seed` | aleatoria | Fija la semilla de la ejecución |
| `name` | `file:line` | Nombre de la propiedad; de él deriva su propia semilla |

| Variable de entorno | Efecto |
|---|---|
| `PROPTEST_SEED` | Repite una ejecución (se imprime en cada informe de fallo) |
| `PROPTEST_CASES` | `cases` por defecto, por ejemplo más en CI que en local |
| `PROPTEST_MAX_SHRINKS` | `maxShrinks` por defecto |
| `PROPTEST_DB` | Directorio de los archivos locales: semilla de la ejecución, base de fallos (por defecto `.proptest`), u `off` |
| `PROPTEST_DEADLINE` | `deadline` por defecto en ms (por ejemplo, defínelo en CI) |
| `PROPTEST_TIME_BUDGET` | `timeBudget` por defecto en ms |
| `PROPTEST_VERBOSITY` | `quiet`, `normal`, `verbose` o `debug` |
| `PROPTEST_REPORT` | `report` por defecto: un archivo JSON Lines para herramientas de CI (abajo) |
| `PROPTEST_HANG_TIMEOUT` | `hangTimeout` por defecto en ms (recomendado en CI, por ejemplo 60000) |

<a id="json-report-for-ci"></a>
### Informe JSON para CI

`PROPTEST_REPORT=proptest-report.jsonl nimble test` añade una línea de JSON por propiedad a ese archivo (se crea junto con su directorio; varios programas de prueba pueden compartirlo). Cada línea tiene `format` (1), `name`, `status` (`passed`, `failed`, `flaky`, `gaveUp`, `generatorError`, `insufficientCoverage`, o `hung` desde el [watchdog](TROUBLESHOOTING.md#the-test-hangs), cuya línea tiene menos campos), `passed`, `seed` (una cadena: no cabe en un número JSON), `program`, `replay` (el comando que repite la ejecución), `casesPassed`, `discarded`, `firstFailureAt`, `durationMs`, `message`, `labeledCases`, `labels` (`name`, `kind`, `cases`, `events`, `required` para `cover`), `targets` (`label`, `best`: la mejor puntuación de `target` por nombre), `warnings`, y `failures`: `kind` y `location` (la firma del fallo), `message`, `source` (`explored`, `database`, `example`), `flaky`, `choices`, `shrinkExecutions`, `shrinkStopped`, `inputs` (`name`, `value`), `machine` y `steps` para máquinas de estado, `stackTrace`. Se pueden añadir campos; un campo que cambia de significado o desaparece incrementa `format`.

```sh
jq -r 'select(.passed | not) | "\(.name): \(.status), \(.replay)"' proptest-report.jsonl
```

## Generadores

### Tipos, incluidos los tuyos

`x in T` genera cualquiera de estos, anidados de cualquier forma, sin código: enteros de todos los anchos (incluidos los tipos `range`), `float`/`float32` (incluidos NaN, infinitos y -0.0), `bool`, `char`, `string`, enums, `seq`, `array`, `set`, `Option`, tuplas, `Table`, `OrderedTable`, `HashSet` y **tus propios tipos**:

```nim
type
  Kind = enum circle, rect
  Shape = object                  # fields need not be exported
    name: string
    case kind: Kind
    of circle: r: int
    of rect: w, h: int
  Node = ref object               # recursive: bounded automatically
    val: int
    left, right: Node

forAll(s in Shape, n in Node): ...
```

Los objetos, los case objects, `distinct` y los objetos `ref` se derivan campo a campo; un bug en una rama de un case object se reduce a esa rama con los campos más simples, y un bug en un árbol al árbol más pequeño. Los enteros alcanzan `low(T)` y `high(T)` a menudo, porque ahí viven los bugs. Guía: [GENERATORS.md](GENERATORS.md).

### Combinadores

| Generador | Valores | Se reduce hacia |
|---|---|---|
| `ints(lo, hi)`, `ints()`, `ints(lo, hi, near = [v])` | enteros en `lo .. hi`; `near` propone `v-1`, `v`, `v+1` | el valor más cercano a 0 |
| `floats(lo, hi)`, `floats(allowNaN, allowInf)` | floats | 0.0 |
| `bools()` | `bool` | `false` |
| `chars(alphabet)` | caracteres de `alphabet` | su primer carácter |
| `strings(alphabet, minLen, maxLen)` | cadenas | más cortas, primeros caracteres |
| `seqs(g, minLen, maxLen)` | `seq` de valores de `g` | más cortas, elementos más simples |
| `tables(k, v, ...)`, `hashSets(g, ...)` | contenedores de valores generados | menos entradas, más simples |
| `uniqueSeqs(g, ...)`, `sortedSeqs(g, ...)` | `seq` de valores distintos, o en orden ascendente | más cortas, elementos más simples |
| `sized(proc(n: int): Gen[T] = ...)`, `g.resize(n)` | un generador construido a partir del tamaño actual, o con un tamaño fijo | tamaños menores |
| `strings(alphanumeric, ...)`, `identifiers(maxLen)`, `unicodeStrings(minLen, maxLen)` | letras y dígitos (`alphanumeric` es un alfabeto), identificadores, UTF-8 válido en todos los planos | más cortas, `a` |
| `frequency([(w, g), ...])` | un generador, elegido por peso | la primera entrada |
| `recursive(base, extend, maxDepth)` | árboles: cada nivel es `base` o un nivel más profundo | `base` |
| `optionals(g)` | `Option` | `none` |
| `elements([a, b, c])` | uno de los valores | el primero |
| `oneOf(g1, g2, ...)` | un valor de uno de los generadores | el primer generador |
| `constant(v)` | siempre `v` | |
| `g.map(f)`, `g.filter(pred)`, `g.flatMap(f)` | valores transformados | a través del generador original |
| `gen(T)` | el generador inferido por el tipo, como valor | |

Nunca escribes un reductor: todo generador, incluidas las cadenas de `map`, `filter` y `flatMap`, se reduce automáticamente, y los valores reducidos siguen cumpliendo el filtro.

### Cuando los campos deben concordar: escribe `arbitrary`

La derivación rellena cada campo de forma independiente. Cuando los campos deben concordar (un inicio antes de un fin), sobrecarga `arbitrary`; siempre tiene prioridad sobre la derivación:

```nim
proc arbitrary(src: ChoiceSource; t: typedesc[Money]): Money =
  Money(cents: src.drawInt(0, 1_000_000),
        currency: elements(["USD", "EUR", "BRL"]).generate(src))
```

O construye un valor generador con `newGen` a partir de las primitivas de sorteo (`drawInt`, `drawBool`, `drawIndex`, `drawFloat`, `drawFloatRange`, `drawUpTo`). La única regla: una elección menor debe significar un valor más simple, cosa que todas las primitivas ya cumplen.

```nim
let sortedPairs = newGen(proc(src: ChoiceSource): (int, int) =
  let a = src.drawInt(-100, 100)
  let b = src.drawInt(a, 100)
  (a, b))
```

## Encontrar más bugs y ver qué se probó

Pasar no dice nada de las entradas que nunca se generaron. Formas de comprobarlo y de dirigirlo (diseño: [ADR-0012](../../decisions/0012-bug-finding-power.md); patrones: [PATTERNS.md](PATTERNS.md)):

```nim
forAll(initSettings(cases = 300), xs in seq[int]):
  classify(xs.len == 0, "empty")          # share of cases, printed after the run
  cover(20.0, xs.len >= 10, "ten or more") # fails if confidently below 20%
  label("len " & $min(xs.len, 3))         # cases by a computed text
  check ...
```

- **Fronteras.** Los enteros alcanzan 0, 1, -1 y los límites de su tipo; los floats alcanzan -0.0, NaN, infinitos y subnormales; las colecciones, vacía y de un elemento. Las constantes enteras usadas en la propiedad (`const openFor = 1000`) y los literales enteros del archivo de pruebas se proponen como `v - 1`, `v`, `v + 1`. Para una frontera definida en otro lugar: `ints(0, 2000, near = [openFor])`.
- **Swarm testing** (máquinas de estado): la mitad de las secuencias omite algunos comandos, así que se vuelven probables largas series de los demás (un bug que necesita 12 incrementos sin reset: encontrado en 3 de 100 semillas antes, 97 de 100 con él).
- **Exploración dirigida** para estados profundos que los casos aleatorios rara vez alcanzan: da al motor una puntuación que escalar, y tras la mitad de los casos extiende el mejor caso hasta el momento.
  ```nim
  stateMachine Breaker:
    ...
    invariant:
      target(float(model.reopenings), "reopenings")   # climb toward many reopenings
  ```
  El tope de backoff de un circuit breaker (cinco reaperturas seguidas) se encontró en 3 de 100 semillas sin ella, 20 con ella. Ayuda cuando el progreso se acumula a lo largo de una secuencia; para valores independientes, prefiere pistas `near` o un generador dedicado.
- **Plazos y presupuestos**: `deadline` convierte un caso lento en un fallo, reducido a lo que lo hace lento; `timeBudget` y `shrinkTimeBudget` se detienen antes y lo indican.
- **Health checks** avisan, con una solución, de datos demasiado grandes para `maxChoices`, espacios de entrada menores que `cases` y una generación que domina el tiempo de ejecución.

La capacidad de la propia biblioteca para encontrar bugs se mide: [`benchmarks/b_find.nim`](../../../benchmarks/b_find.nim) ejecuta bugs plantados con semillas fijas y el CI falla si baja una tasa de detección.

## Resultados y fallos

¿Algo parece ir mal (gave up, flaky, un aviso, una semilla que no se repite)? [TROUBLESHOOTING.md](TROUBLESHOOTING.md) parte de lo que ves.

- **Dentro de un `test` de unittest**: una propiedad que falla hace fallar la prueba con un único informe.
- **En otros lugares**: `forAll` lanza `PropertyError` (con `.propertyResult`), y `forAllResult(...)` (mismos argumentos) devuelve el `PropertyResult` sin lanzar.

| Estado | Significado |
|---|---|
| `psPassed` | todos los casos pasaron |
| `psFailed` | al menos un contraejemplo, ejecutado dos veces más para confirmarlo |
| `psFlaky` | el contraejemplo mínimo no volvió a fallar: la propiedad depende del tiempo, de estado global, de hilos o de E/S |
| `psGaveUp` | demasiados casos descartados por `assume` o `filter` |
| `psGeneratorError` | un generador lanzó una excepción: un bug en el generador, no en el código probado |
| `psInsufficientCoverage` | todos los casos pasaron, pero un requisito de `cover` no se cumplió con confianza |

Leer el resultado en código (`forAllResult`, `stateMachineResult`, o `.propertyResult` de un `PropertyError`):

```nim
let r = forAllResult(xs in seq[int]):
  check xs.reversed.reversed == xs
if not r.passed:
  echo formatReport(r)              # the same text report a failing test prints
  for f in r.failures:              # one per distinct bug, already shrunk
    echo f.message, " from ", f.source   # fsExplored, fsDatabase or fsExample
    for (name, value) in f.inputs: echo name, " = ", value
    for step in f.steps: echo step  # state machines: the failing sequence as Nim calls
```

`r.status` es uno de los valores de arriba; `r.runSeed` repite la ejecución; `r.casesRun`, `r.discarded`, `r.labels` y `r.warnings` contienen las estadísticas y los health checks que imprime el informe. Cada fallo tiene además `choices` (su secuencia mínima de elecciones), `shrinkExecutions`, `shrinkStopped` (la reducción alcanzó `shrinkTimeBudget`), `flaky` y `stackTrace`.

Hasta `maxFailures` bugs **distintos** (tipo de excepción o ubicación diferentes) se informan por separado, cada uno reducido por su cuenta; la reducción nunca convierte un bug en otro.

**Reproducir**: cada informe imprime `PROPTEST_SEED=<n>`; ejecuta el mismo binario con ella para obtener los mismos casos y el mismo contraejemplo. La semilla también se escribe en `.proptest/last-run` antes del primer caso, así que sobrevive a un crash.

**Los fallos siguen encontrados**: cada fallo reproducido se guarda en `.proptest/db/` y se repite **antes de cualquier caso aleatorio** en las siguientes ejecuciones, así que una corrección se comprueba enseguida; una entrada se olvida tras pasar tres ejecuciones seguidas. `PROPTEST_DB=off` lo desactiva. Añade `.proptest/` a tu `.gitignore` (el CI puede cachearlo). Para fijar un caso para siempre, añade `example(...)` (un valor por variable, ejecutado primero) o pega el bloque `replayCommands` de un informe con estado en una prueba:

```nim
forAll(x in int, s in string, example(0, ""), example(-1, "a")): ...
```

<a id="features"></a>
## Funcionalidades

- `forAll` / `forAllResult` con tipos y valores generadores
- Generadores para tipos nativos, combinadores, `arbitrary` y `newGen` propios
- Reducción integrada, varios fallos distintos, detección de flaky
- Reescritura de `check`/`require`, `assume`, ajustes, variables de entorno
- Integración con `std/unittest` y `unittest2`; uso independiente
- Informe JSON para herramientas de CI (`PROPTEST_REPORT`)
- Repetición por semilla y rastro de crash (Linux, macOS y Windows en CI)
- Pruebas con estado / basadas en modelos: `stateMachine`, la secuencia fallida más corta impresa como código `replayCommands`
- Generadores derivados para objetos, case objects, `distinct`, `ref` y tipos recursivos; `Table`, `HashSet`; `frequency`, `recursive`; cadenas Unicode
- Base de fallos (los fallos pasados se repiten primero), `example(...)` explícito
- `classify` / `cover` / `label`, estadísticas con estado, niveles de verbosidad
- Sesgo hacia casos límite, pistas de frontera (`near`, constantes extraídas), swarm testing
- Plazo por caso, presupuestos de tiempo para la ejecución y la reducción, health checks
- Referencia de configuración y guía de solución de problemas, comprobadas contra el código en CI
- Política de estabilidad: una semilla se repite entre versiones patch, comprobado por un golden snapshot ([STABILITY.md](STABILITY.md))
- `sized`, `resize`, `uniqueSeqs`, `sortedSeqs`, exploración dirigida (`target`)
- Watchdog (opcional, `PROPTEST_HANG_TIMEOUT`): un caso que nunca termina se informa (entradas, elecciones, repetición) y se guarda, en lugar de colgar la ejecución (necesita `--threads:on`, el valor por defecto de Nim)

## Limitaciones conocidas

- **Un caso que nunca termina cuelga la ejecución, salvo que el watchdog esté activado**: con `PROPTEST_HANG_TIMEOUT=60000` (recomendado en CI; desactivado por defecto) se informa y se guarda pasado ese tiempo, y el programa termina con código 1, porque un caso en ejecución no se puede interrumpir de forma segura. No se puede reducir, y sus entradas se imprimen en la siguiente ejecución (o enseguida con `PROPTEST_VERBOSITY=verbose`). Sin `--threads:on` no hay watchdog.
- **Los estados profundos siguen siendo difíciles**: un estado que necesita un camino largo y concreto (cinco reaperturas seguidas de un breaker, cada una tras la espera justa) rara vez se alcanza con secuencias aleatorias. `target(score)` ayuda cuando la propiedad puede medir el progreso (3 → 20 de 100 semillas para el breaker); para un camino que ya conoces, escríbelo como prueba `replayCommands`.
- **Las compilaciones release solo localizan los fallos de `check`**: sin `--stackTrace:on --lineTrace:on` (`-d:release`, `-d:danger`), las demás excepciones se distinguen solo por el tipo, así que dos bugs que lanzan el mismo tipo se informan como uno. Un aviso en tiempo de compilación lo indica; consulta [TROUBLESHOOTING.md](TROUBLESHOOTING.md#two-bugs-reported-as-one-or-location-unknown).
- **`--panics:on`**: los `Defect` terminan el proceso en el primer caso que falla, así que no se puede reducir (un aviso en tiempo de compilación lo indica).
- Un `except CatchableError` amplio dentro del cuerpo de la propiedad también captura las señales internas de la biblioteca (`assume`, `check` fallido); vuelve a lanzarlas o captura tipos más concretos.
- Los valores generados para una semilla solo cambian en versiones minor, siempre listados en el [CHANGELOG](../../../CHANGELOG.md) ([política de estabilidad](STABILITY.md)), así que una semilla antigua puede no repetirse tras una actualización minor.

## Pruebas con estado

Secuencias aleatorias de comandos se ejecutan contra el sistema real y contra un modelo sencillo; tras cada paso, ambos deben coincidir. Un fallo se informa como la secuencia fallida **más corta**, impresa como código Nim para pegarla como prueba de regresión. Tutorial completo: [STATEFUL.md](STATEFUL.md).

```nim
type Model = object
  items: seq[int]

stateMachine BoundedQueue:
  model: Model()                            # fresh for every sequence
  setup:
    let q = newBoundedQueue[int](capacity = 3)

  command push(x in ints(-10, 10)):
    precondition: model.items.len < 3       # only valid sequences are generated
    run: q.push(x)
    update: model.items.add x

  command pop():
    precondition: model.items.len > 0
    run: q.pop()
    postcondition: result == model.items[0] # checked before `update`
    update: model.items.delete(0)

  invariant: q.len == model.items.len

test "queue matches its model":
  checkStateMachine(BoundedQueue)
```

Con una cola cuyo `pop` falla tras exactamente 3 push y 1 pop:

```
  Shortest failing sequence (4 steps, 10 choices, 150 shrink executions):
    replayCommands BoundedQueue:
      push(0)
      push(0)
      push(0)
      pop()
  Error: [PropertyFailed] check failed: result == model.items[0]
      result was 1
      model.items[0] was 0
  Failed at step 4: pop()
```

El tiempo es un comando (`command advance(ms in ints(0, 2000))` que mueve un reloj falso), así que los bugs dependientes del tiempo se reducen a esperas exactas. `teardown:` siempre se ejecuta; los argumentos pueden tomarse del modelo (`k in elements(model.keys)`).

## Calidad

- 158 pruebas, que pasan en `orc`/`arc` × hilos activados/desactivados × debug/release; ASan, UBSan y comprobación de fugas limpios.
- El PRNG y el hash coinciden con las implementaciones de referencia en C de sus autores y con los vectores oficiales de FNV-1a (golden tests).
- Pruebas de valor: cada bug de referencia de la [SPEC](../../SPEC.md) se reduce a su contraejemplo mínimo exacto; dos bugs independientes se informan ambos, y la reducción nunca salta de un bug a otro (comprobado en 20 semillas).
- Puertas deterministas en CI: reducir cada bug de referencia lleva de 9 a 236 ejecuciones (línea base en `benchmarks/baseline/shrink.json`); los bugs plantados deben seguir encontrándose en tantas semillas como en la línea base (`benchmarks/baseline/find.json`); sortear elecciones y ejecutar pasos con estado nunca reserva memoria, y una prueba comprueba lo mismo para las etiquetas estáticas.
- Primer usuario externo: la prueba de modelo de [`nim-circuit-breaker`](https://github.com/kaio-souza/nim-circuit-break) ejecuta 1000 secuencias aleatorias contra su breaker.
- Cada requisito tiene una fila en [`TRACEABILITY.md`](../../TRACEABILITY.md), comprobada por `nimble trace`. Decisiones de diseño: [`decisions/`](../../decisions/README.md).

```sh
nimble test     # test suite
nimble gate     # deterministic performance gates
nimble bench    # timings (informational)
nimble trace    # traceability matrix
```

## Licencia

[MIT](../../../LICENSE)
