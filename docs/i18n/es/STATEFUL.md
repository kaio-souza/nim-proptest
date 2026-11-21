**Idiomas:** [English](../../STATEFUL.md) · [Português (BR)](../pt-BR/STATEFUL.md) · Español · [中文](../zh-CN/STATEFUL.md)

> Traducción de [STATEFUL.md](../../STATEFUL.md). En caso de discrepancia, prevalece la versión en inglés.

# Tutorial de pruebas con estado

Algunos bugs no están en una llamada a función sino en una **secuencia** de llamadas: una cola que se comporta mal tras tres push y un pop, una caché que conserva una entrada un milisegundo de más, un circuit breaker que deja pasar una sonda en el momento equivocado. Las pruebas basadas en ejemplos solo los encuentran si alguien ya pensó en la secuencia.

Las pruebas con estado (basadas en modelos) escriben las reglas una vez, como un pequeño **modelo**, y dejan que la biblioteca genere secuencias aleatorias de comandos, ejecute cada una en el sistema real y en el modelo, y los compare tras cada paso. Cuando discrepan, reduce la secuencia a la **más corta** que sigue fallando y la imprime como código Nim que puedes pegar como prueba de regresión.

Este tutorial construye el ejemplo de [`examples/stateful.nim`](../../../examples/stateful.nim) (compilado y ejecutado en CI). Diseño: [ADR-0011](../../decisions/0011-stateful-testing.md).

## 1. El sistema: un circuit breaker

Un circuit breaker protege a quien llama de una dependencia que falla. Tras `threshold` fallos consecutivos se **abre** y rechaza las llamadas; tras `openFor` milisegundos deja pasar una llamada de **sonda** (semiabierto); una sonda con éxito lo cierra, una que falla lo vuelve a abrir.

```nim
type
  Clock = ref object
    ms: int                        # a fake clock: tests move it by hand
  State = enum Closed, Open, HalfOpen
  Breaker = ref object
    clock: Clock
    state: State
    failures: int
    openedAt: int

const threshold = 3
const openFor = 1000

proc call(b: Breaker; succeeds: bool): string =
  ## "ok", "failed" or "rejected".
```

El reloj se inyecta. El código basado en el tiempo solo es comprobable cuando la prueba puede mover el tiempo por sí misma, sin `sleep`.

## 2. El modelo: las reglas, lo más simples posible

El modelo es un valor simple que predice lo que debería hacer el sistema. No necesita ser eficiente ni general, solo obviamente correcto:

```nim
type Model = object
  state: State
  failures, now, openedAt: int

proc admits(m: Model): bool =
  m.state != Open or m.now - m.openedAt >= openFor

proc called(m: var Model; ok: bool) =
  if not m.admits: return
  if m.state == Open: m.state = HalfOpen
  if ok:
    m.state = Closed
    m.failures = 0
  elif m.state == HalfOpen:
    m.state = Open
    m.openedAt = m.now
  else:
    inc m.failures
    if m.failures >= threshold:
      m.state = Open
      m.openedAt = m.now
```

## 3. La máquina: comandos, precondiciones, postcondiciones

```nim
stateMachine BreakerSpec:
  model: Model()                     # a fresh model for every sequence
  setup:                             # a fresh system for every sequence
    let clock = Clock()
    let breaker = newBreaker(clock)

  command succeed():
    run: breaker.call(succeeds = true)
    postcondition: result == (if model.admits: "ok" else: "rejected")
    update: model.called(ok = true)

  command fail():
    run: breaker.call(succeeds = false)
    postcondition: result == (if model.admits: "failed" else: "rejected")
    update: model.called(ok = false)

  command advance(ms in ints(0, 2000)):
    run: clock.ms += ms
    update: model.now += ms

  invariant:
    check breaker.state == model.state
    check breaker.failures == model.failures
```

Qué hace cada sección:

| Sección | Se ejecuta | Notas |
|---|---|---|
| `model:` | una vez por secuencia | Una expresión; la variable `model` la contiene. Usa `model: ()` cuando no hay modelo. |
| `setup:` | una vez por secuencia | Sentencias. Sus variables son visibles en todos los comandos. |
| `teardown:` | tras cada secuencia, incluso una que falla | Se ejecuta siempre que `setup` terminó. |
| `command name(x in source, ...)` | por paso | Los argumentos usan la sintaxis de `forAll`: un tipo o un generador. |
| `precondition:` | antes de elegir un comando | Ve el modelo. Solo se generan comandos habilitados, en la exploración **y** en la reducción. |
| `run:` | el paso | Su valor es `result` en `postcondition:`. |
| `postcondition:` | tras `run`, **antes** de `update` | Compara `result` con lo que predice el modelo. Una expresión única se comprueba; si no, escribe líneas `check`. |
| `update:` | tras la postcondición | Hace avanzar el modelo. |
| `invariant:` | tras cada paso | Mismas reglas que `postcondition:`. |

El tiempo es un comando más (`advance`). Todo lo basado en el tiempo se vuelve reproducible y reducible.

Una espera uniforme en `0 .. 2000` rara vez sería **exactamente** 1000, que es donde vive el bug de la sección 5. Las constantes enteras del archivo de pruebas, aquí `const openFor = 1000`, se proponen como pistas de frontera (999, 1000, 1001) durante la exploración ([ADR-0012](../../decisions/0012-bug-finding-power.md)). Cuando la frontera está definida en otro módulo, nómbrala: `ms in ints(0, 2000, near = [openFor])`.

Los argumentos pueden depender del modelo, por ejemplo `k in elements(model.keys)` para actuar sobre una clave añadida antes. Da a esos comandos una precondición (`model.keys.len > 0`) para que nunca se pida a la fuente un elemento de una lista vacía.

## 4. Ejecutarla

```nim
suite "breaker":
  test "the breaker follows its model":
    checkStateMachine(BreakerSpec, initSettings(cases = 500))
```

Cada caso es una secuencia aleatoria de hasta `maxSteps` comandos (por defecto 50; `initSettings(maxSteps = ...)`). Las secuencias crecen a lo largo de la ejecución, primero las cortas. `stateMachineResult(BreakerSpec)` devuelve el `PropertyResult` en lugar de hacer fallar la prueba, como hace `forAllResult`.

## 5. Leer un fallo

Compila el ejemplo con `-d:plantBug`. Ese bug deja pasar la sonda solo *después* de 1000 ms, no *a los* 1000 ms:

```
Property 'BreakerSpec' falsified at case 91 (496 cases passed, 0 discarded).
Failure 1 of 2 (PropertyFailed at stateful.nim:92)
  Shortest failing sequence (5 steps, 12 choices, 171 shrink executions):
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
      advance(1000)
      succeed()
  Error: [PropertyFailed] check failed: result == if model.admits: "ok" else: "rejected"
      result was "rejected"
      if model.admits: "ok" else: "rejected" was "ok"
  Location: stateful.nim:92
  Failed at step 5: succeed()
Failure 2 of 2 (PropertyFailed at stateful.nim:97)
  Shortest failing sequence (5 steps, 12 choices, 191 shrink executions):
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
      advance(1000)
      fail()
  ...
  Replay: PROPTEST_SEED=3 ./stateful
```

La secuencia aleatoria que falló primero (caso 91) tenía decenas de pasos. El informe muestra la más corta: tres fallos para abrir el circuito, una espera de **exactamente** el timeout, y la llamada que debería haber pasado. Si se quita cualquier paso anterior, el bug desaparece; cualquier espera distinta de 1000 no lo muestra. El mismo bug también rompe la postcondición de `fail()`, que es otra comprobación, así que se informa por separado con su propia secuencia más corta.

El bloque `replayCommands` es Nim válido. Pégalo en una prueba y ejecuta los mismos pasos, con el mismo setup, postcondiciones e invariantes, como prueba de regresión permanente:

```nim
  test "probe allowed exactly at the timeout (regression)":
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
      advance(1000)
      succeed()
```

Si la precondición de un paso repetido es falsa, `replayCommands` lanza `ValueError` nombrando ese paso, porque una secuencia así nunca puede generarse.

## 6. Cuando el modelo está mal

Un fallo significa que el sistema y el modelo discrepan. A veces el que está mal es el modelo. Mientras se escribía este ejemplo, la primera versión de `called` no contaba el fallo que abre el circuito, y la prueba respondió en pocos casos:

```
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
  Error: [PropertyFailed] check failed: breaker.failures == model.failures
      breaker.failures was 3
      model.failures was 2
```

Tres pasos bastan para ver qué regla falla. Decide qué lado coincide con la especificación, y corrige ese lado.

## 7. Consejos

- **Mantén el modelo tonto.** Una lista en lugar de un búfer circular, un contador en lugar de una ventana deslizante. Si el modelo es tan complejo como el sistema, ambos pueden compartir el mismo bug.
- **Nombra las fronteras que el archivo no muestra.** Las constantes del archivo de pruebas se extraen automáticamente; para una definida en otro sitio, usa `ints(lo, hi, near = [...])`. La reducción no se ve afectada.
- **Comprueba qué se ejercitó.** Con `PROPTEST_VERBOSITY=verbose` una máquina que pasa imprime cuántas veces se ejecutó cada comando, cuántas veces lo bloqueó su precondición y las longitudes de las secuencias. Un comando que nunca se ejecutó siempre se informa como aviso. `cover(20.0, model.state == Open, "reached Open")` dentro de un `update:` hace fallar la prueba cuando menos del 20% de las secuencias llegan a ese estado.
- **El swarm testing está activado.** La mitad de las secuencias omite algunos comandos, así que se vuelven probables largas series de los demás (muchos incrementos sin reset). `initSettings(swarm = false)` lo desactiva.
- **Comprueba lo que observa el usuario**: valores devueltos en las postcondiciones, estado visible en los invariantes. No compruebes campos privados.
- **Los errores esperados son valores.** Si el sistema lanza una excepción ante una llamada rechazada, captúrala dentro de `run:` y devuelve algo que el modelo predice (`"rejected"`). Cualquier excepción que escape de `run:` es un fallo.
- **Un ejemplo real**: [`nim-circuit-breaker`](https://github.com/kaio-souza/nim-circuit-breaker) prueba su breaker así (`tests/t_model.nim`), con backoff, `successThreshold` y su `FakeClock`, sobre 1000 secuencias.

## Límites

- Los estados que necesitan un camino largo y concreto (cinco reaperturas seguidas de un breaker, cada una tras la espera justa) siguen alcanzándose rara vez con secuencias aleatorias. Si el modelo puede medir el progreso, dale una puntuación con `target(float(model.reopenings), "reopenings")` en `invariant:`: tras la mitad de los casos, el motor extiende la mejor secuencia hasta el momento (en el tope de backoff del breaker, 3 → 20 de 100 semillas; [ADR-0016](../../decisions/0016-targeted-exploration.md)). Para un camino que ya conoces, escríbelo como prueba de regresión `replayCommands`, o restringe los comandos de una máquina dedicada.
- Los comandos se ejecutan uno tras otro en un solo hilo.
- Los valores de los argumentos se imprimen con `showCode`, que produce literales Nim para los tipos nativos. Para un tipo de argumento propio, sobrecarga `showCode` para que el bloque impreso compile.
- `stateMachine` debe usarse a nivel de módulo. Los nombres generados (`BreakerSpec`, `BreakerSpecStep`, los constructores de comandos) se exportan, así que una máquina puede vivir en su propio módulo.
