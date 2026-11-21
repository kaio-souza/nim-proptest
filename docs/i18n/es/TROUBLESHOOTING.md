**Idiomas:** [English](../../TROUBLESHOOTING.md) · [Português (BR)](../pt-BR/TROUBLESHOOTING.md) · Español · [中文](../zh-CN/TROUBLESHOOTING.md)

> Traducción de [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md). En caso de discrepancia, prevalece la versión en inglés. Los informes de abajo quedan en inglés, como los imprime la biblioteca.

# Solución de problemas

Busca lo que ves, y luego lee por qué ocurre y qué hacer. Los informes de abajo son salidas reales (nombres de archivo acortados). Cada ajuste mencionado se describe en [CONFIGURATION.md](CONFIGURATION.md).

**La propiedad falla o se detiene**

- [Gave up after N passing cases](#gave-up-after-n-passing-cases)
- [FLAKY: el caso mínimo no volvió a fallar](#flaky-the-minimal-case-did-not-fail-again)
- [Un generador lanzó una excepción](#a-generator-raised)
- [Requisitos de cobertura no cumplidos](#missed-its-coverage-requirements)
- [DeadlineExceeded](#deadlineexceeded)
- [La prueba se cuelga](#the-test-hangs)
- [El proceso termina sin informe](#the-process-ends-with-no-report)

**El informe sorprende**

- [Dos bugs informados como uno, o "Location unknown"](#two-bugs-reported-as-one-or-location-unknown)
- [El contraejemplo no es tan pequeño como podría](#the-counterexample-is-not-as-small-as-it-could-be)
- [Repetido desde la base de fallos](#replayed-from-the-failure-database)
- [`PROPTEST_SEED` no reproduce el fallo](#proptest_seed-does-not-reproduce-the-failure)

**Pasa, pero ¿debería?**

- [La propiedad pasa, pero el bug está ahí](#the-property-passes-but-the-bug-is-there)
- [Aviso: only N distinct inputs](#warning-only-n-distinct-inputs)
- [Aviso: cases needed more than maxChoices](#warning-cases-needed-more-than-maxchoices)
- [Aviso: generating inputs takes most of the run time](#warning-generating-inputs-takes-most-of-the-run-time)
- [Aviso: command never ran](#warning-command-never-ran)
- [Aviso: time budget reached](#warning-time-budget-reached)

**Otros**

- [La suite de pruebas es lenta](#the-test-suite-is-slow)
- [La salida de la propiedad inunda el terminal](#output-from-the-property-floods-the-terminal)
- [Un bloque `replayCommands` pegado falla con "precondition ... is false"](#a-pasted-replaycommands-block-fails-with-precondition--is-false)
- [Errores de compilación](#compile-errors)

---

<a id="the-property-fails-or-stops"></a>
## La propiedad falla o se detiene

<a id="gave-up-after-n-passing-cases"></a>
### Gave up after N passing cases

```
Property 'sorted' gave up after 0 passing cases: 1001 cases discarded (0 by filters, 0 too large).
```

**Por qué.** Se descartaron demasiados casos: por `assume(...)`, por un `filter` o `uniqueSeqs` que rechazó 100 valores seguidos, o porque eran demasiado grandes para `maxChoices`. Tras `cases × maxDiscardRatio` descartes (1000 por defecto) la propiedad se detiene, porque ya no está probando gran cosa. Cuando la mayoría de los descartes vienen de filtros, el mensaje añade "Most discards come from `filter` or `uniqueSeqs` rejecting values: generate valid values directly, or widen the generator."

Arriba, la propiedad quería listas ordenadas de al menos 5 elementos, y las listas aleatorias de esa longitud casi nunca están ordenadas.

**Qué hacer.** Genera valores válidos en lugar de rechazar los inválidos:

```nim
# Gives up: rejects every case.
forAll(xs in seq[int]):
  assume(xs.len >= 5 and xs.isSorted)
  ...

# Passes 100 cases: builds only valid inputs, and still shrinks.
forAll(xs in sortedSeqs(ints(), minLen = 5)):
  ...
```

`sortedSeqs` y `uniqueSeqs` cubren las dos formas más comunes. Para valores que dependen entre sí (un inicio antes de un fin), sortea el primero y después el segundo dentro de su rango, como en [GENERATORS.md](GENERATORS.md). Reserva `assume` para exclusiones raras (`assume(d != 0)`).

Los tamaños crecen con cada intento, incluidos los descartados, así que una condición solo sobre el tamaño (`assume(xs.len > 30)`) solo cuesta descartes al principio de la ejecución: pasa, con unos cientos de descartes.

**Contrapartida.** Subir `maxDiscardRatio` hace desaparecer el mensaje pero no el coste: cada caso descartado sigue ejecutando el generador, y los casos que pasan son los pocos que encajaron por casualidad, así que pueden parecerse todos.

<a id="flaky-the-minimal-case-did-not-fail-again"></a>
### FLAKY: el caso mínimo no volvió a fallar

```
Property 'flaky' is flaky at case 3 (67 cases passed, 0 discarded).
  FLAKY: the minimal case did not fail again when re-run.
  Common causes: time, randomness, global state, threads or I/O in the property.
  Counterexample (1 choices, 1 shrink executions):
    x = 0
  Error: [PropertyFailed] check failed: counter mod 3 != 0
        counter mod 3 was 0
```

**Por qué.** Tras la reducción, cada fallo se ejecuta dos veces más. Si no falla las dos veces, el resultado no dependía solo de las entradas generadas. Arriba, la propiedad leía un contador global que cambia en cada ejecución.

**Qué hacer.** Averigua qué lee la propiedad además de sus entradas:

- **Estado global o de módulo**: una caché, un contador, un singleton. Crea estado nuevo dentro del cuerpo, o reinícialo al principio.
- **Tiempo**: `now()`, `epochTime()`, timeouts. Inyecta un reloj y contrólalo desde la propiedad (el [tutorial con estado](STATEFUL.md) lo hace con un reloj falso).
- **Aleatoriedad** en el código probado: siémbrala con un valor generado (`seed in uint64`).
- **Hilos, archivos, red**: el orden y los tiempos cambian entre ejecuciones. Prueba la lógica sin ellos, o haz que la prueba sea dueña del recurso (un directorio temporal por caso).

El informe sigue mostrando el contraejemplo: el bug puede ser real, pero no reproducible tal como está escrito. No vuelvas a ejecutar hasta que pase.

<a id="a-generator-raised"></a>
### Un generador lanzó una excepción

```
Property 'price': a generator raised: [ValueError] invalid integer:
  This is a problem in a generator, not in the code under test.
```

**Por qué.** La excepción vino de generar las entradas, antes de ejecutar el cuerpo: aquí, un `arbitrary` para `Money` llamó a `parseInt` sobre una cadena aleatoria. La biblioteca se detiene enseguida en lugar de informar de un bug que no está en tu código.

**Qué hacer.** Corrige el generador para que toda elección dé un valor válido. Sortea directamente lo que necesitas (`src.drawInt(0, 1_000_000)`) en lugar de generar algo más amplio y convertirlo.

Un error distinto con aspecto parecido: los generadores nativos lanzan `ValueError` ante argumentos imposibles (`ints: lo > hi`, `seqs: invalid lengths`) cuando empieza la propiedad, antes de cualquier caso. Revisa los argumentos.

<a id="missed-its-coverage-requirements"></a>
### Requisitos de cobertura no cumplidos

```
Property 'empty lists' passed 100 cases but missed its coverage requirements:
    cover 'empty': 8.0% of 100 cases, 50.0% required
  Statistics (100 cases):
      8.0%  empty  (cover: 50.0% required)
```

**Por qué.** `cover(50.0, xs.len == 0, "empty")` pide que al menos el 50% de los casos sean listas vacías, y solo el 8% lo fue. Todos los casos pasaron, pero los casos que dijiste que importan fueron raros, así que la propiedad no probó lo que querías. Un requisito solo falla cuando incluso el extremo optimista de un intervalo estadístico queda por debajo; cuando hay demasiados pocos casos para estar seguros, es un aviso ("too few cases to be sure; raise `cases`").

**Qué hacer.** O el generador debería producir esos casos más a menudo (un generador dedicado, `frequency`, `near = [...]`), o el requisito es demasiado estricto. Un requisito en torno a la proporción que de verdad necesitas para probar bien (5%, 10%) suele ser correcto; 50% para una sola situación significa que merece su propia propiedad.

<a id="deadlineexceeded"></a>
### DeadlineExceeded

```
Property 'slow' falsified at case 2 (80 cases passed, 0 discarded).
  Counterexample (1 choices, 9 shrink executions):
    x = 16
  Error: [DeadlineExceeded] case took 10.2 ms; deadline 5.0 ms
```

**Por qué.** `deadline` (o `PROPTEST_DEADLINE`) está fijado, y un caso tardó más. Se reduce como cualquier fallo, a la entrada más pequeña que sigue siendo lenta: aquí, el código duerme cuando `x > 15`, y 16 es esa frontera.

**Qué hacer.** Si la lentitud es un bug (comportamiento cuadrático con alguna entrada), el contraejemplo muestra la entrada. Si es ruido (una máquina de CI cargada, una compilación debug), sube el plazo: ponlo muy por encima del tiempo normal de los casos. La exploración ya permite 1,25 × el plazo, pero la reducción y las re-ejecuciones usan el plazo tal cual, así que un caso al límite también puede informarse como FLAKY.

<a id="the-test-hangs"></a>
### La prueba se cuelga

```
proptest: property 'hangs on 42' did not return: a case has run for more than 300 ms (hangTimeout) while exploring (case 1), running the property.
  Inputs: not recorded while exploring (formatting them would cost time on every case).
  The case was saved in the failure database: the next run replays it first and
  prints its inputs here if it still does not return.
  Choices (1): 42
  Replay: PROPTEST_SEED=1 ./t_hang
  The process stops here (exit code 1): a running case cannot be interrupted safely.
```

**Por qué.** Un caso nunca termina: un bucle infinito, un interbloqueo, la espera de un evento que nunca llega. `deadline` no puede detectarlo, porque mide un caso después de que termina. El watchdog está desactivado por defecto, así que la ejecución simplemente se cuelga. Con `PROPTEST_HANG_TIMEOUT` fijado (arriba, 300 ms), pasado ese tiempo el hilo watchdog informa del caso y termina el proceso: nada puede interrumpir de forma segura un caso en ejecución, así que la ejecución no puede continuar y el caso no se puede reducir.

**Qué hacer.**

1. Si la ejecución simplemente se cuelga sin informe, detenla y vuelve a ejecutarla con el watchdog activado, por ejemplo `PROPTEST_HANG_TIMEOUT=10000 nimble test` (la misma semilla viene de `.proptest/last-run`: `PROPTEST_SEED=<ella>`). Después ejecuta las pruebas una vez más. El caso se guardó, así que se ejecuta primero, con sus entradas registradas:
   ```
   proptest: property 'hangs on 42' did not return: ... while replaying a case that hung in an earlier run (case 1), running the property.
     Inputs:
       x = 42
   ```
   Una máquina de estado muestra los pasos en su lugar, siendo el último el paso que no termina. Con `PROPTEST_DB=off` no se guarda nada: repite con la semilla y `PROPTEST_VERBOSITY=verbose`, que registra las entradas de cada caso.
2. Convierte la entrada en una prueba normal, o en un `example(...)`, y corrige el bucle. Una vez que el caso guardado pase, se olvida tras tres ejecuciones.
3. En CI, mantén el watchdog activado, para que un cuelgue falle con este informe en lugar de llegar al límite de tiempo del job: `PROPTEST_HANG_TIMEOUT=60000`.

Sin `--threads:on` (el valor por defecto de Nim 2 es activado) no hay watchdog: detén el proceso, y luego repite con la semilla de `.proptest/last-run` y `PROPTEST_VERBOSITY=verbose`; el último caso impreso es el anterior al que se cuelga.

<a id="the-process-ends-with-no-report"></a>
### El proceso termina sin informe

**Por qué.** Normalmente `--panics:on`: un Defect (`IndexDefect`, `AssertionDefect`, desbordamiento) termina el proceso en lugar de lanzarse, así que la biblioteca no puede reducirlo ni informar de él. El compilador avisa: "proptest: compiled with --panics:on". Otras causas: un fallo de segmentación (acceso a `nil` con `-d:danger`, o en código C), o `quit()` llamado por el código probado.

**Qué hacer.** Compila las pruebas con `--panics:off` (el valor por defecto) y sin `-d:danger`. La semilla está en `.proptest/last-run` para repetir el crash en un depurador.

<a id="the-report-is-surprising"></a>
## El informe sorprende

<a id="two-bugs-reported-as-one-or-location-unknown"></a>
### Dos bugs informados como uno, o "Location unknown"

Compilación debug: dos bugs, dos fallos.

```
Property 'two bugs' falsified at case 8 (53 cases passed, 0 discarded).
Failure 1 of 2 (ValueError at t_bugs.nim:28)
  ...
    x = 51
    y = 0
  Error: [ValueError] x too big
Failure 2 of 2 (ValueError at t_bugs.nim:29)
  ...
    x = 0
    y = 51
  Error: [ValueError] y too big
```

La misma propiedad compilada con `-d:release`: un fallo, el segundo bug oculto.

```
Property 'two bugs' falsified at case 8 (53 cases passed, 0 discarded).
  Counterexample (2 choices, 17 shrink executions):
    x = 51
    y = 0
  Error: [ValueError] x too big
  Location unknown (no stack trace): failures are told apart by type only.
```

**Por qué.** Dos fallos son el mismo bug cuando tienen el mismo tipo de excepción y se lanzan en la misma línea de tu código. La línea viene de la traza de pila, que `-d:release` desactiva. Los fallos de `check` mantienen su línea en cualquier compilación, porque la línea se registra donde está escrito el `check`.

**Qué hacer.** Ejecuta las pruebas de propiedades en compilaciones debug, o añade `--stackTrace:on --lineTrace:on` a la compilación release ([tabla](CONFIGURATION.md#compile-time-options)). Una compilación así se anuncia en tiempo de compilación con el aviso "proptest: built without stack traces". El caso contrario, un bug informado como varios, ocurre cuando el mismo bug se lanza en líneas distintas según la entrada; los contraejemplos se parecen entonces, y corregir uno corrige los demás.

<a id="the-counterexample-is-not-as-small-as-it-could-be"></a>
### El contraejemplo no es tan pequeño como podría

**Por qué**, de más a menos común:

- **Un generador propio rompe la regla de la reducción**: una elección menor debe dar un valor más simple. `src.drawInt(0, 100)` la cumple; `100 - src.drawInt(0, 100)` la invierte, así que la reducción avanza hacia 100. Asigna elecciones simples a valores simples.
- **La reducción se detuvo pronto**: el informe dice "Shrinking stopped at its time budget" (`shrinkTimeBudget`), o las ejecuciones mostradas igualan `maxShrinks`. Sube el presupuesto, o haz cada ejecución más rápida.
- **El mínimo no está donde esperas**: la reducción minimiza las *elecciones*, lo que para los generadores nativos significa colecciones más cortas, valores más cercanos a 0, el primer valor del enum, la primera rama de `oneOf`. `x = -1` puede ser el valor fallido más simple cuando `x = 1` pasa.
- **Hay un `filter` encima**: los valores reducidos deben seguir pasando el filtro, lo que puede bloquear valores más simples. Generar valores válidos directamente también ayuda aquí.

<a id="replayed-from-the-failure-database"></a>
### Repetido desde la base de fallos

```
  Replayed from the failure database: it failed in an earlier run.
```

**Por qué.** Un fallo encontrado en una ejecución anterior se guardó en `.proptest/db/` y se repite antes de cualquier caso aleatorio, para que una corrección se compruebe enseguida. Este sigue fallando.

**Qué hacer.** Nada especial: es un fallo real, con el mismo informe que cuando se encontró. Una entrada se olvida tras pasar 3 ejecuciones seguidas; las entradas que ya no encajan con los generadores (cambiaste los tipos) se descartan. Para empezar de cero, borra `.proptest/db/`; para desactivarlo, `PROPTEST_DB=off`.

<a id="proptest_seed-does-not-reproduce-the-failure"></a>
### `PROPTEST_SEED` no reproduce el fallo

**Por qué.** La semilla reproduce una ejecución solo si todo lo demás que decide las entradas es igual. Comprueba, en orden:

1. **El código cambió.** La semilla de una propiedad viene de su nombre, que por defecto es su `file:line`: añadir una línea encima cambia sus entradas. Las constantes extraídas del archivo también cambian. Usa la semilla con el binario que la imprimió, o pon un `name` a la propiedad.
2. **Los ajustes difieren.** `cases` decide cómo crecen los tamaños, así que `PROPTEST_CASES=1000` con una semilla impresa por una ejecución de 100 casos da otras entradas. Lo mismo vale para `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm` y `mineConstants`.
3. **La propiedad fija `seed`.** Una semilla fija en los ajustes tiene prioridad sobre `PROPTEST_SEED`.
4. **La propiedad no es determinista.** Si el informe decía FLAKY, ver [arriba](#flaky-the-minimal-case-did-not-fail-again).

La plataforma y el modo de compilación no importan: la misma semilla da los mismos valores en Linux, macOS y Windows, debug y release.

<a id="it-passes-but-should-it"></a>
## Pasa, pero ¿debería?

<a id="the-property-passes-but-the-bug-is-there"></a>
### La propiedad pasa, pero el bug está ahí

Una propiedad que pasa solo dice que las entradas que probó estaban bien. Mira lo que probó:

1. **Cuenta los casos que te importan.** Añade `classify` para las situaciones que necesita el bug, y `cover` si tienen que ocurrir:
   ```nim
   forAll(xs in seq[int]):
     classify(xs.len == 0, "empty")
     classify(xs.len > 100, "long")
     cover(1.0, low(int) in xs, "has low(int)")
     check ...
   ```
   Las estadísticas se imprimen tras una ejecución que pasa.
2. **Mira las entradas** con `PROPTEST_VERBOSITY=verbose PROPTEST_CASES=20`.
3. Luego, según lo que falte:

| Falta | Solución | Contrapartida |
|---|---|---|
| un valor concreto (un límite definido en otro módulo) | `ints(lo, hi, near = [limit])` | ninguna: se siguen sorteando otros valores |
| entradas largas | sube `maxSize`, o `seqs(g, minLen = ...)` | casos más lentos |
| una combinación rara | más `cases` (en CI: `PROPTEST_CASES`) | el tiempo crece linealmente |
| una categoría entera | un generador dedicado, o `frequency` | más código que mantener |
| estados profundos de una máquina de estado | sube `maxSteps`; mantén `swarm` activado | secuencias más largas |

Las constantes enteras del cuerpo de la propiedad ya se proponen como `v - 1`, `v`, `v + 1` (`mineConstants`); las constantes definidas en otro módulo no.

<a id="warning-only-n-distinct-inputs"></a>
### Aviso: only N distinct inputs

```
Property 'few inputs' passed 100 cases.
  Warnings:
    only 2 distinct inputs in 100 passing cases: the input space is small, so a plain loop over it would be exhaustive
```

**Por qué.** La propiedad ejecutó 100 casos sobre muchas menos entradas distintas (menos de 1 de cada 10 distintas). Aquí la entrada es un `bool`, que tiene dos valores.

**Qué hacer.** Si el espacio de entradas es de verdad tan pequeño, un bucle sobre todos los valores es más corto y completo:

```nim
for b in [false, true]:
  check ...
```

Si debería ser mayor, el generador es demasiado estrecho (`ints(0, 3)` cuando querías `ints(0, 3000)`). Si el aviso es esperado, `initSettings(suppress = {hcFewDistinct})`.

<a id="warning-cases-needed-more-than-maxchoices"></a>
### Aviso: cases needed more than maxChoices

```
Property 'too large' passed 100 cases.
  Warnings:
    440 cases needed more than maxChoices (8192) choices and were skipped: bound collection sizes (`seqs(g, maxLen = ...)`) or raise maxChoices
```

**Por qué.** Las colecciones anidadas crecen rápido: una `seq[seq[string]]` con `maxSize = 1000` produce valores con decenas de miles de elecciones. Esos casos se omitieron, y los 100 que pasaron son los más pequeños: las entradas grandes quedaron sin probar.

**Qué hacer.** Acota los tamaños donde importa, o baja `maxSize`. La misma forma con límites no produce aviso ni siquiera con `maxSize = 1000`:

```nim
let bounded = seqs(seqs(strings(alphanumeric, 0, 20), maxLen = 10), maxLen = 100)
forAll(initSettings(maxSize = 1000), v in bounded): ...
```

Sube `maxChoices` solo cuando las entradas grandes sean el objetivo, sabiendo que cada caso tarda entonces más en ejecutarse y en reducirse.

<a id="warning-generating-inputs-takes-most-of-the-run-time"></a>
### Aviso: generating inputs takes most of the run time

**Por qué.** Más del 80% del tiempo se fue en generar entradas en lugar de ejecutar la propiedad: normalmente un `filter` que rechaza la mayoría de los valores, o un generador propio que construye valores grandes y tira la mayoría.

**Qué hacer.** Genera valores válidos directamente, o acota los tamaños. Si la propiedad es barata y la generación es legítimamente el trabajo, `suppress = {hcSlowGeneration}`.

<a id="warning-command-never-ran"></a>
### Aviso: command never ran

```
Property 'CounterSpec' passed 100 cases.
  Warnings:
    command 'reset' never ran in 100 sequences; its precondition was false 1934 times
```

**Por qué.** En una máquina de estado, un comando cuya precondición nunca es verdadera nunca se prueba. Aquí `reset` necesita más de 1000 incrementos, y las secuencias tienen como mucho 50 pasos.

**Qué hacer.** Haz alcanzable el estado (sube `maxSteps`, o añade un comando que llegue antes), o relaja la precondición si el modelo lo permite. Las estadísticas con `PROPTEST_VERBOSITY=verbose` muestran cuántas veces se ejecutó cada comando y cuántas veces su precondición fue falsa.

<a id="warning-time-budget-reached"></a>
### Aviso: time budget reached

```
Property 'budget' passed 173 cases.
  Warnings:
    time budget of 200 ms reached after 173 of 100000 cases
```

**Por qué.** `timeBudget` (o `PROPTEST_TIME_BUDGET`) detuvo antes la exploración. La propiedad pasó los casos que ejecutó.

**Qué hacer.** Nada, si el objetivo era acotar el tiempo. Si no, sube el presupuesto, baja `cases`, o haz la propiedad más rápida.

<a id="other"></a>
## Otros

<a id="the-test-suite-is-slow"></a>
### La suite de pruebas es lenta

En orden aproximado de efecto:

1. **Modo de compilación.** La generación en una compilación debug es varias veces más lenta que en release. Si compilas las pruebas en release, añade `--stackTrace:on --lineTrace:on` para conservar la ubicación de los fallos ([por qué](#two-bugs-reported-as-one-or-location-unknown)).
2. **Menos casos en local, más en CI.** Mantén el valor por defecto en el código y fija `PROPTEST_CASES` en CI.
3. **Entradas más pequeñas.** Un `maxSize` menor, o generadores acotados, para propiedades cuyo código es lento con entradas grandes.
4. **Acota el tiempo.** `timeBudget` por propiedad; `deadline` para encontrar las entradas que hacen lento un caso.

Para ver en qué se va el tiempo, `PROPTEST_REPORT=report.jsonl` registra `durationMs` por propiedad:

```sh
jq -r '"\(.durationMs)\t\(.name)"' report.jsonl | sort -rn | head
```

<a id="output-from-the-property-floods-the-terminal"></a>
### La salida de la propiedad inunda el terminal

**Por qué.** El cuerpo se ejecuta una vez por caso y una vez por paso de reducción: un `echo` en él imprime cientos de veces. La biblioteca en sí no imprime nada por caso con la verbosidad por defecto.

**Qué hacer.** Quita la salida de depuración cuando termines. Para ver las entradas, usa `PROPTEST_VERBOSITY=verbose`; para ver distribuciones, `classify` y `label`. Un texto que debería explicar un fallo pertenece al propio `check`: las comparaciones ya imprimen ambos lados (`x was 500`).

<a id="a-pasted-replaycommands-block-fails-with-precondition--is-false"></a>
### Un bloque `replayCommands` pegado falla con "precondition ... is false"

```
replayCommands: precondition of step 3 (pop()) is false, so this sequence cannot happen
```

**Por qué.** La secuencia la imprimió una versión anterior de la máquina de estado. El modelo o las precondiciones cambiaron, así que la secuencia ya no es posible.

**Qué hacer.** Si el cambio fue intencionado, borra la prueba de regresión o vuelve a generarla a partir de una nueva ejecución fallida. Si no, el cambio rompió el modelo.

<a id="compile-errors"></a>
### Errores de compilación

| Error | Causa | Solución |
|---|---|---|
| `type expected` en `forAll(x: int)` | Nim interpreta los argumentos `name: value` como un constructor de objeto antes de que la macro los vea | escribe `forAll(x in int)` |
| `declare variables as `name in Type` or `name in generator`` | `forAll(x = ints(0, 1))` | `forAll(x in ints(0, 1))` |
| `forAll needs a body: forAll(x in int): ...` | la llamada no tiene cuerpo, o se usa como expresión | añade el cuerpo; para obtener el resultado como valor, `let r = forAllResult(...): ...` |
| `proptest cannot generate field 'f' of P: overload `arbitrary` for its type, or for P` | un tipo de campo sin generador (un `proc`, un puntero, un tipo de C) | escribe `arbitrary` para el tipo de ese campo, o para `P` ([GENERATORS.md](GENERATORS.md)) |
| `proptest cannot derive T: its discriminant 'k' is a range type` | una limitación de Nim 2.2.4 | usa un enum como discriminante, o escribe `arbitrary` para `T` |
| `example(...) needs one value per variable (N)` | un ejemplo con valores de menos o de más | un valor por `name in source`, en orden |
| `classify is only valid inside forAll or a stateMachine` | `classify`, `cover` o `label` fuera de una propiedad | muévelo dentro del cuerpo |
| Aviso `proptest: compiled with --panics:on` | ver [arriba](#the-process-ends-with-no-report) | compila las pruebas con `--panics:off` |
| Aviso `proptest: built without stack traces`, o `... without --lineTrace:on` | una compilación release: ver [arriba](#two-bugs-reported-as-one-or-location-unknown) | `--stackTrace:on --lineTrace:on`, o `-d:proptestTraceWarning=false` si tus propiedades fallan mediante `check` |
