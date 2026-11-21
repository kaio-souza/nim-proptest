**Idiomas:** [English](../../CONFIGURATION.md) · [Português (BR)](../pt-BR/CONFIGURATION.md) · Español · [中文](../zh-CN/CONFIGURATION.md)

> Traducción de [CONFIGURATION.md](../../CONFIGURATION.md). En caso de discrepancia, prevalece la versión en inglés.

# Referencia de configuración

Cada ajuste, variable de entorno y opción de compilación, con su valor por defecto, lo que cuesta y cuándo cambiarlo. Problemas y sus soluciones: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

- [Recetas](#recipes): copia una y adáptala
- [Cómo se elige un valor](#how-a-value-is-chosen): ajuste explícito, entorno, valor por defecto
- [Ajustes](#settings), agrupados por lo que controlan
- [Variables de entorno](#environment-variables)
- [Opciones de compilación](#compile-time-options): modo de compilación, `--panics`, trazas de pila
- [Archivos que escribe la biblioteca](#files-the-library-writes)
- [Qué necesita una repetición](#what-a-replay-needs)

<a id="recipes"></a>
## Recetas

**En el día a día, nada que ajustar.** 100 casos por propiedad, reducción activada, fallos guardados y repetidos primero en la siguiente ejecución. La mayoría de las propiedades nunca necesitan un ajuste.

```nim
forAll(xs in seq[int]):
  check xs.sorted.sorted == xs.sorted
```

**Más casos en CI que en tu máquina.** Usa el entorno, no el código, para que las ejecuciones locales sigan siendo rápidas:

```sh
PROPTEST_CASES=1000 PROPTEST_HANG_TIMEOUT=60000 PROPTEST_REPORT=proptest-report.jsonl nimble test
```

`PROPTEST_HANG_TIMEOUT` activa el watchdog: un caso que nunca termina acaba la ejecución con un informe en lugar de correr hasta el límite de tiempo del job de CI.

Una propiedad que fija `cases` por sí misma ignora `PROPTEST_CASES` (ver la [precedencia](#how-a-value-is-chosen)): no pongas `cases` en las propiedades que quieres que el CI escale.

**Una ejecución nocturna profunda.** Muchos más casos, acotados por tiempo para que una propiedad lenta no se coma la noche:

```sh
PROPTEST_CASES=100000 PROPTEST_TIME_BUDGET=60000 PROPTEST_HANG_TIMEOUT=60000 PROPTEST_VERBOSITY=quiet nimble test
```

`timeBudget` es por propiedad: cada una se detiene tras 60 s con un aviso que dice cuántos casos se ejecutaron.

**Repetir un fallo.** Copia la línea `Replay:` del informe. Mismo binario y, por lo demás, mismo entorno:

```sh
PROPTEST_SEED=17542877672211577899 ./tests/t_sorting
```

**Ver qué genera una propiedad.** Las entradas de cada caso y todas las estadísticas:

```sh
PROPTEST_VERBOSITY=verbose PROPTEST_CASES=20 ./tests/t_sorting
```

**Una propiedad costosa.** Menos casos, más grandes, y un tope de tiempo por caso:

```nim
forAll(initSettings(cases = 30, maxSize = 300, deadline = 2000), doc in Document):
  check parse(render(doc)) == doc
```

**Una propiedad que siempre debe ver las mismas entradas** (un ejemplo en la documentación, una prueba de la propia biblioteca): fija la semilla. Entonces ignora `PROPTEST_SEED`.

```nim
forAll(initSettings(seed = 42), x in int): ...
```

**Los mismos ajustes para muchas propiedades.** `Settings` es un objeto simple; constrúyelo una vez:

```nim
let heavy = initSettings(cases = 50, maxSize = 500, deadline = 1000)

test "round trip":
  forAll(heavy, doc in Document):
    check parse(render(doc)) == doc

test "rendering is stable":
  forAll(heavy, doc in Document):
    check render(doc) == render(parse(render(doc)))
```

Cada propiedad sigue recibiendo su propia semilla (derivada de su nombre `file:line`), así que compartir ajustes no hace que dos propiedades sorteen los mismos valores. Por eso, deja `name` vacío en los ajustes compartidos.

<a id="how-a-value-is-chosen"></a>
## Cómo se elige un valor

Para cada ajuste, gana el primero que se aplique:

1. **El argumento** dado a `initSettings(...)`.
2. **La variable de entorno**, para los ajustes que la tienen (se lee cuando se ejecuta `initSettings`).
3. **El valor por defecto integrado.**

```nim
# PROPTEST_CASES=1000 in the environment:
forAll(x in int): ...                          # 1000 cases: environment
forAll(initSettings(cases = 20), x in int): ... # 20 cases: argument
```

La semilla sigue el mismo orden: `seed` en los ajustes, después `PROPTEST_SEED`, después una semilla aleatoria elegida una vez por proceso. Esa **semilla de ejecución** no se usa directamente: cada propiedad deriva la suya a partir de ella y de su `name`, así que una sola `PROPTEST_SEED` repite todas las propiedades del programa, y las propiedades no comparten flujos aleatorios.

Una variable de entorno que no se puede interpretar es un error, no un valor por defecto silencioso: `PROPTEST_CASES=abc` lanza `ValueError: PROPTEST_CASES is not an integer: abc` en la primera propiedad. Los ajustes inválidos (`cases = 0`, `edgeBias = 2.0`) lanzan `ValueError: invalid proptest settings: ...` antes de que se ejecute ningún caso.

<a id="settings"></a>
## Ajustes

Pásalos a `initSettings(...)` entre los argumentos de `forAll`, `forAllResult` o `checkStateMachine`. En las máquinas de estado, **un caso es una secuencia completa** de comandos.

<a id="how-much-to-test"></a>
### Cuánto probar

| Ajuste | Por defecto | Entorno | Válido |
|---|---|---|---|
| `cases` | 100 | `PROPTEST_CASES` | >= 1 |
| `maxSize` | 100 | | >= 0 |
| `maxSteps` | 50 | | >= 1 |
| `maxDepth` | 5 | | >= 0 |
| `maxChoices` | 8192 | | >= 1 |

**`cases`**: casos explorados, pasen o fallen. El coste crece linealmente; la probabilidad de dar con un bug que necesita una entrada rara también crece, pero despacio: un bug que aparece con 1 entrada de cada 1000 lo encuentran 100 casos en aproximadamente 1 de cada 10 ejecuciones, y 1000 casos en aproximadamente 2 de cada 3. Súbelo en CI, no en el código. **Cambiarlo cambia las entradas** de todos los casos (los tamaños crecen a lo largo de la ejecución, ver `maxSize`), así que una semilla solo se repite con el mismo `cases`.

**`maxSize`**: lo grandes que llegan a ser los valores. Los tamaños crecen de 0 en el primer caso a `maxSize` en el último, así que los primeros casos son pequeños y simples. Los casos descartados también hacen avanzar el tamaño, así que una propiedad que descarta entradas pequeñas (`assume(xs.len > 30)`) sigue llegando a las grandes. Dentro de un generador, `sized` lee el tamaño actual y `resize` lo fija ([GENERATORS.md](GENERATORS.md)). Medido sobre `seq[int]` con 100 casos:

| `maxSize` | longitud media | la más larga |
|---|---|---|
| 10 | 3 | 16 |
| 100 (por defecto) | 40 | 154 |
| 1000 | 416 | 1927 |

Súbelo cuando un bug necesita entradas largas (un búfer que se llena con 256 elementos); bájalo cuando el código probado es lento con entradas grandes. Las colecciones anidadas son más cortas que las de primer nivel. Los valores más grandes también tardan más en reducirse, pero la reducción siempre termina en uno mínimo. Los límites de tamaño de un generador se ponen mejor en el propio generador: `seqs(ints(), maxLen = 10)`.

**`maxSteps`** (máquinas de estado): la secuencia de comandos más larga. La mayoría de los bugs necesitan pocos pasos, y el swarm testing (abajo) hace probables largas series de un mismo comando dentro de 50. Súbelo para bugs que necesitan muchos pasos (un contador que desborda tras 300 incrementos); el coste por secuencia crece con él.

**`maxDepth`**: la profundidad de los datos recursivos durante la exploración (árboles, objetos `ref` que apuntan a su propio tipo, `seq` anidadas). Más profundidad significa casos más grandes y lentos. 0 da el valor más simple de un tipo recursivo (una ref `nil`, una lista de hijos vacía).

**`maxChoices`**: elecciones aleatorias que puede usar un caso (un `int` es una elección, una `seq` es aproximadamente una por elemento más sus elementos). Un caso que necesita más se omite y se cuenta como "too large", lo que impide que un generador desbocado agote la memoria. Cuando el [health check](TROUBLESHOOTING.md#warning-cases-needed-more-than-maxchoices) diga que se omitieron muchos casos, acota primero los tamaños del generador; sube `maxChoices` solo si los casos grandes son el objetivo.

<a id="shrinking"></a>
### Reducción

| Ajuste | Por defecto | Entorno | Válido |
|---|---|---|---|
| `maxShrinks` | 2000 | `PROPTEST_MAX_SHRINKS` | >= 0 |
| `shrinkTimeBudget` | 0 (ninguno) | | >= 0 ms |
| `maxFailures` | 3 | | >= 1 |

**`maxShrinks`**: ejecuciones de la propiedad dedicadas a reducir cada fallo. Los bugs de referencia de la biblioteca se reducen a su mínimo exacto en 9 a 236 ejecuciones, así que 2000 es generoso; el presupuesto importa cuando una ejecución es lenta. 0 informa del primer caso fallido tal como se encontró, sin reducir.

**`shrinkTimeBudget`**: un tope de tiempo por fallo, para propiedades lentas. Cuando se alcanza, el informe dice "Shrinking stopped at its time budget" y muestra el contraejemplo más pequeño hasta entonces: válido, quizá no mínimo.

**`maxFailures`**: fallos distintos (tipo de excepción o ubicación diferentes) que se conservan y se reducen. La exploración continúa tras el primer fallo para encontrar otros, y se detiene cuando se conocen tantos. 1 se detiene en el primer bug, lo que es más rápido pero oculta un segundo bug hasta que se corrige el primero.

<a id="finding-bugs"></a>
### Encontrar bugs

| Ajuste | Por defecto | Entorno | Válido |
|---|---|---|---|
| `edgeBias` | 0.25 | | 0.0 .. 1.0 |
| `mineConstants` | true | | |
| `swarm` | true | | |
| `maxDiscardRatio` | 10 | | >= 0 |

**`edgeBias`**: la proporción de sorteos que proponen un valor límite en lugar de uno uniforme: 0, 1, -1 y los límites del tipo para enteros; -0.0, NaN, infinitos y subnormales para floats; colecciones vacías y de un elemento. Los bugs se concentran ahí. 0.0 solo da valores uniformes; valores más altos prueban más los límites y menos los valores típicos. Cambiarlo cambia las entradas de todos los casos.

**`mineConstants`**: los literales enteros y las constantes del cuerpo de la propiedad (y, con menos sorteos, de todo el archivo de pruebas) se proponen como `v - 1`, `v`, `v + 1`. Así se encuentra `x == 1000` en `0 .. 2000`. También significa que una propiedad que menciona `997` ve de 996 a 998 más a menudo que por azar: normalmente lo que quieres. Desactívalo para medir el comportamiento aleatorio puro. Para una frontera definida en otro módulo, usa `ints(lo, hi, near = [v])`.

**`swarm`** (máquinas de estado): la mitad de las secuencias omite un subconjunto aleatorio de comandos, así que se vuelven probables largas series de los restantes ("12 incrementos sin reset": encontrado en 3 de 100 semillas sin swarm, 97 con él). La otra mitad usa todos los comandos. Desactívalo solo para comparar.

**`maxDiscardRatio`**: una propiedad se rinde tras `cases × maxDiscardRatio` casos descartados (por `assume`, por `filter`, o demasiado grandes). Subirlo oculta el problema; generar valores válidos directamente lo resuelve ([gave up](TROUBLESHOOTING.md#gave-up-after-n-passing-cases)).

<a id="time"></a>
### Tiempo

| Ajuste | Por defecto | Entorno | Válido |
|---|---|---|---|
| `deadline` | 0 (desactivado) | `PROPTEST_DEADLINE` | >= 0 ms |
| `timeBudget` | 0 (ninguno) | `PROPTEST_TIME_BUDGET` | >= 0 ms |
| `hangTimeout` | 0 (desactivado) | `PROPTEST_HANG_TIMEOUT` | >= 0 ms; 0 es desactivado |

**`deadline`**: un caso que tarda más falla con `DeadlineExceeded` y se reduce como cualquier fallo: a la entrada más pequeña que sigue siendo lenta. Úsalo para encontrar saltos de rendimiento (comportamiento cuadrático con alguna entrada). Durante la exploración, un caso dispone de 1,25 × el plazo, para que uno que se pasa por poco no se convierta en un informe flaky. Contrapartida: los tiempos varían entre máquinas y con carga, así que ponlo muy por encima del tiempo normal de los casos, sobre todo en CI. No detiene un caso que nunca termina: eso lo hace `hangTimeout`.

**`timeBudget`**: un tope de tiempo para la exploración, por propiedad. Cuando se alcanza, la propiedad se detiene e informa de lo que hizo: una propiedad que pasa dice "time budget of N ms reached after K of M cases" como aviso. Mantiene acotado el tiempo de CI a costa de menos casos en máquinas lentas.

**`hangTimeout`**: un caso que no ha terminado tras este tiempo (un bucle infinito, un interbloqueo) lo informa un hilo watchdog, que después **termina el proceso** con código de salida 1: un caso en ejecución no se puede interrumpir de forma segura, así que no hay forma de continuar la ejecución. El informe nombra la propiedad, qué se estaba ejecutando (explorando, reduciendo, un caso guardado), las elecciones del caso y el comando de repetición; el caso se guarda en la base de fallos, así que la siguiente ejecución lo repite primero e imprime sus entradas. Se añade una línea `hung` al informe JSON. **Desactivado por defecto**, para que depurar un caso paso a paso o una propiedad legítimamente lenta nunca termine el proceso por sorpresa. Actívalo donde un cuelgue cuesta más, en CI, muy por encima de tu caso normal más lento: `PROPTEST_HANG_TIMEOUT=60000`. Sin él, un caso que nunca termina cuelga la ejecución hasta que se detiene ([entonces](TROUBLESHOOTING.md#the-test-hangs)). El watchdog necesita `--threads:on` (el valor por defecto de Nim 2) y vigila una propiedad a la vez: las propiedades ejecutadas concurrentemente en otros hilos no se vigilan. [Qué hacer cuando salta](TROUBLESHOOTING.md#the-test-hangs).

<a id="output"></a>
### Salida

| Ajuste | Por defecto | Entorno | Valores |
|---|---|---|---|
| `verbosity` | `vNormal` | `PROPTEST_VERBOSITY` | `quiet`, `normal`, `verbose`, `debug` |
| `report` | vacío (ninguno) | `PROPTEST_REPORT` | una ruta de archivo |
| `suppress` | `{}` | | `hcLargeData`, `hcFewDistinct`, `hcSlowGeneration` |

**`verbosity`**:

| Nivel | Imprime |
|---|---|
| `quiet` | solo los fallos |
| `normal` | también los avisos, y las estadísticas de las propiedades que usan `classify`, `cover` o `label` |
| `verbose` | también una línea por caso con sus entradas, y todas las estadísticas (recuento de comandos con estado, longitudes de secuencia) |
| `debug` | también cada paso de reducción aceptado |

En el entorno, los nombres no llevan el prefijo `v` (`PROPTEST_VERBOSITY=verbose`); en el código sí (`verbosity = vVerbose`).

**`report`**: un archivo [JSON Lines](https://jsonlines.org) al que se añade el resultado de cada propiedad, para herramientas de CI. Se crean el archivo y su directorio; varios programas de prueba pueden compartir un archivo. Una ruta en la que no se puede escribir lanza `IOError` con la ruta. Campos: ver el [README](README.md#json-report-for-ci). Ejemplo: listar los fallos y cómo repetirlos.

```sh
jq -r 'select(.passed | not) | "\(.name): \(.status) — \(.replay)"' proptest-report.jsonl
```

**`suppress`**: health checks que no se ejecutan en esta propiedad. Es preferible corregir lo que indica el check; suprímelo cuando el aviso es esperado (una propiedad sobre `bool` tiene de verdad dos entradas).

<a id="identity-and-reproduction"></a>
### Identidad y reproducción

| Ajuste | Por defecto | Entorno |
|---|---|---|
| `seed` | aleatoria | `PROPTEST_SEED` |
| `name` | `file:line` | |

**`seed`**: fija la semilla de ejecución de esta propiedad; entonces ignora `PROPTEST_SEED`. Bueno para la documentación y las pruebas de la propia biblioteca; malo para pruebas normales, que explorarían las mismas 100 entradas para siempre.

**`name`**: aparece en los informes y se usa para dos cosas:

- **La semilla de la propiedad** se deriva de la semilla de ejecución y del nombre. Con el nombre por defecto (`file:line`), añadir una línea encima de una propiedad cambia sus entradas para la misma `PROPTEST_SEED`. Una semilla impresa en un informe repite el binario que la imprimió; tras editar el archivo, confía en la base de fallos.
- **La clave en la base de fallos.** Sin nombre, la clave es un hash del código de la propiedad, así que editar la propiedad olvida sus fallos guardados (puede que ya no tengan sentido). Con nombre, los fallos guardados sobreviven a las ediciones; los que ya no encajan con los generadores se descartan.

Pon nombre a las propiedades a las que te refieres en otros sitios (un gestor de incidencias, un panel de CI): se mantiene estable cuando las líneas se mueven.

<a id="environment-variables"></a>
## Variables de entorno

| Variable | Fija | Formato | Uso típico |
|---|---|---|---|
| `PROPTEST_SEED` | semilla de ejecución | entero sin signo de 64 bits | repetir un fallo |
| `PROPTEST_CASES` | `cases` por defecto | entero | más casos en CI |
| `PROPTEST_MAX_SHRINKS` | `maxShrinks` por defecto | entero | propiedades lentas en CI |
| `PROPTEST_DEADLINE` | `deadline` por defecto | entero, ms | detectar casos lentos en CI |
| `PROPTEST_TIME_BUDGET` | `timeBudget` por defecto | entero, ms | acotar las ejecuciones nocturnas |
| `PROPTEST_HANG_TIMEOUT` | `hangTimeout` por defecto | entero, ms; 0 (por defecto) es desactivado | activar el watchdog en CI: un cuelgue falla con un informe |
| `PROPTEST_VERBOSITY` | `verbosity` por defecto | `quiet`, `normal`, `verbose`, `debug` | ver las entradas generadas |
| `PROPTEST_REPORT` | `report` por defecto | ruta de archivo | JSON para herramientas de CI |
| `PROPTEST_DB` | directorio de los archivos locales | ruta, u `off` | mover o desactivar `.proptest/` |

Los ajustes sin variable (`maxSize`, `edgeBias`, ...) cambian lo que prueba una propiedad más que cuánto tarda, así que es mejor dejarlos en su código, donde quien lo lee los ve. Para fijarlos en toda una suite, comparte un valor `Settings` ([receta](#recipes)).

<a id="compile-time-options"></a>
## Opciones de compilación

**Modo de compilación y trazas de pila.** Los fallos se distinguen por el tipo de excepción y por la línea de tu código donde se lanzaron. Esa línea viene de la traza de pila, que `-d:release` y `-d:danger` desactivan:

| Compilación | Fallos de `check` | `doAssert`, `raise`, errores de índice | Comprobación de desbordamiento e índice |
|---|---|---|---|
| debug (por defecto) | localizados | localizados | activada |
| `-d:release` | localizados | solo el tipo | activada |
| `-d:release --stackTrace:on` | localizados | solo el archivo (`t_sort.nim:0`) | activada |
| `-d:release --stackTrace:on --lineTrace:on` | localizados | localizados | activada |
| `-d:danger` | localizados | solo el tipo | **desactivada** |

Sin ubicaciones, dos bugs distintos que lanzan el mismo tipo de excepción parecen uno, y el informe dice "Location unknown (no stack trace)". Usa preferiblemente compilaciones debug para las pruebas de propiedades, o añade `--stackTrace:on --lineTrace:on` a una compilación release (las dos: la traza de pila sola no tiene números de línea). La biblioteca avisa en tiempo de compilación cuando falta alguna:

```
Warning: proptest: built without stack traces (-d:release and -d:danger turn them off). Failures other than `check` are then told apart by exception type only: two bugs that raise the same type are reported as one. Build tests with --stackTrace:on --lineTrace:on, or silence this with -d:proptestTraceWarning=false.
```

**`-d:proptestTraceWarning=false`.** Silencia ese aviso, para una suite que compila en release a propósito y cuyas propiedades fallan mediante `check` (localizado en cualquier compilación). Evita `-d:danger`: con las comprobaciones desactivadas, un índice fuera de rango es comportamiento indefinido en lugar de un fallo que la biblioteca puede capturar y reducir.

**`--panics:on`.** Los Defect (`IndexDefect`, `AssertionDefect`, ...) terminan el proceso al instante, así que el caso fallido no se puede reducir. La biblioteca avisa en tiempo de compilación. Compila las pruebas con el valor por defecto `--panics:off`; si tienes que mantenerlo activado, la semilla de ejecución ya está en `.proptest/last-run` para repetir el crash.

**`-d:proptestDb=<dir>` o `-d:proptestDb=off`.** El valor por defecto compilado de `PROPTEST_DB`, para un binario de prueba que nunca debe escribir archivos (la variable sigue teniendo prioridad).

**Gestión de memoria e hilos.** `--mm:orc` (por defecto) y `--mm:arc`, con hilos activados o desactivados, se prueban todos en CI en Linux, macOS y Windows.

<a id="files-the-library-writes"></a>
## Archivos que escribe la biblioteca

Todos bajo `PROPTEST_DB` (por defecto `.proptest`, relativo al directorio de trabajo). Añádelo a `.gitignore`.

| Archivo | Se escribe | Para qué |
|---|---|---|
| `last-run` | antes del primer caso de cada ejecución | la semilla de ejecución y el comando: repite una ejecución que se cayó o se colgó |
| `db/<hash>.txt` | tras una propiedad que falló | casos fallidos mínimos, repetidos primero en las siguientes ejecuciones; se olvidan tras 3 ejecuciones seguidas que pasan |

Los errores de escritura se ignoran: un directorio de solo lectura nunca hace fallar una prueba. `PROPTEST_DB=off` no escribe nada.

**Contrapartida de la base de fallos.** Un bug que acabas de ver se reintenta primero, así que una corrección se comprueba enseguida, sin esperar a que la exploración aleatoria lo vuelva a encontrar. El coste: dos ejecuciones del mismo binario con la misma semilla pueden diferir, porque la segunda también repite fallos guardados. Usa `PROPTEST_DB=off` cuando necesites ejecuciones idénticas (benchmarks, comparar semillas). En CI el directorio empieza vacío salvo que lo cachees; cachearlo lleva los fallos de una ejecución de CI a la siguiente.

<a id="what-a-replay-needs"></a>
## Qué necesita una repetición

`PROPTEST_SEED=<n>` reproduce una ejecución exactamente cuando todo lo demás que decide las entradas es igual:

- la misma prueba compilada (mismo código, por tanto los mismos nombres de propiedad y las mismas constantes extraídas de él);
- los mismos ajustes que dan forma a las entradas: `cases`, `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm`, `mineConstants`, incluido `PROPTEST_CASES`;
- una propiedad determinista: sin reloj, estado global, hilos ni E/S que cambien su resultado. Si no, el informe dice FLAKY.

El generador aleatorio y el hash son propios de la biblioteca y fijos (probados contra vectores de referencia en todas las plataformas), así que la misma semilla da los mismos valores en Linux, macOS y Windows, en debug y release. Los valores generados para una semilla solo cambian entre versiones de la biblioteca con una entrada en el CHANGELOG bajo **Generation changes**.
