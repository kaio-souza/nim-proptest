**Idiomas:** [English](../../PATTERNS.md) · [Português (BR)](../pt-BR/PATTERNS.md) · Español · [中文](../zh-CN/PATTERNS.md)

> Traducción de [PATTERNS.md](../../PATTERNS.md). En caso de discrepancia, prevalece la versión en inglés.

# Recetario de patrones de propiedades

La parte difícil de las pruebas basadas en propiedades rara vez es la biblioteca. Es decidir **qué comprobar** cuando no puedes escribir la salida esperada para una entrada aleatoria. Estos patrones cubren la mayoría de las propiedades reales. Cada uno tiene una versión que pasa en [`examples/patterns.nim`](../../../examples/patterns.nim), compilado y ejecutado en CI.

## Ida y vuelta (round trip)

Si una función deshace otra, componerlas devuelve la entrada. Úsalo para serialización, análisis sintáctico, codificación, compresión y conversiones.

```nim
forAll(xs in seq[int]):
  check decode(encode(xs)) == xs
```

Detecta pérdidas de precisión, bugs de escapado y entradas vacías o límite (`@[]`, `low(int)`) que los ejemplos escritos a mano omiten.

## Oráculo (implementación de referencia)

Compara el código con una versión más lenta y obviamente correcta: una función optimizada contra un bucle ingenuo, una implementación nueva contra la antigua, una caché contra el cálculo directo.

```nim
forAll(xs in seq[int]):
  check fastSum(xs) == oracleSum(xs)
```

Una prueba con estado es este mismo patrón aplicado a una secuencia de operaciones: el modelo es el oráculo ([STATEFUL.md](STATEFUL.md)).

## Invariante

Cuando no se conoce la salida exacta, algunas de sus propiedades sí: una ordenación conserva la longitud y ordena los elementos; un árbol equilibrado sigue equilibrado; un total sigue siendo no negativo.

```nim
forAll(xs in seq[int]):
  let s = xs.sorted
  check s.len == xs.len
  for i in 1 ..< s.len: check s[i - 1] <= s[i]
```

## Idempotencia

Aplicar la operación dos veces es lo mismo que aplicarla una vez: normalizar, quitar duplicados, formatear, activar una bandera, un `PUT` de HTTP.

```nim
forAll(xs in seq[int]):
  check dedupe(dedupe(xs)) == dedupe(xs)
```

## Relación metamórfica

No conoces `f(x)`, pero sabes cómo cambia cuando `x` cambia de una forma conocida. Añadir un elemento lo suma a la suma, barajar no cambia un conjunto, escalar la entrada escala una salida lineal.

```nim
forAll(xs in seqs(ints(-1000, 1000)), k in ints(-1000, 1000)):
  check oracleSum(xs & @[k]) == oracleSum(xs) + k
```

Acota los valores cuando la relación puede desbordar: un desbordamiento es un hallazgo real, pero no es el que trata esta propiedad.

## Nunca falla

La propiedad más débil y a menudo la más productiva: para cualquier entrada, el código o devuelve un valor o lanza el error que documenta. Los `Defect` (índice fuera de rango, desbordamiento, acceso a nil) y las excepciones inesperadas son fallos.

```nim
forAll(s in string):
  try: discard parseJson(s)
  except JsonParsingError, ValueError: discard
```

## Fronteras

Los bugs viven donde cambia el dominio: el último reintento, un timeout de exactamente 1000 ms, una capacidad de 3. Los generadores de enteros ya prueban `0`, `1`, `-1` y los límites del tipo. Para tus propias fronteras:

- **Las constantes se extraen automáticamente.** Los literales enteros y los valores `const` usados en la propiedad, y los literales enteros de cualquier parte del archivo de pruebas, se proponen como `v - 1`, `v` y `v + 1` durante la exploración ([ADR-0012](../../decisions/0012-bug-finding-power.md)). `initSettings(mineConstants = false)` lo desactiva.
- **Dilo explícitamente** con `ints(lo, hi, near = [...])` cuando la frontera viene de otro sitio (otro módulo, un archivo de configuración):

```nim
forAll(attempt in ints(0, 100, near = [maxRetries])):
  if attempt < maxRetries: check backoffMs(attempt) >= 100
  else: check backoffMs(attempt) == -1
```

Ninguno de los dos cambia la reducción: el contraejemplo informado sigue siendo el más simple.

## Cobertura: asegúrate de que ocurren los casos interesantes

Una propiedad que pasa no dice nada de las entradas que nunca se generaron. `classify` muestra la distribución; `cover` convierte un requisito en una comprobación:

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

`cover` hace fallar la propiedad solo cuando la proporción observada está **con confianza** por debajo del requisito (el límite superior de un intervalo de Wilson al 95%). Con demasiados pocos casos para estar seguros imprime un aviso y sugiere subir `cases`. `label($x.kind)` cuenta casos por un texto calculado. En una máquina de estado, `cover` cuenta secuencias, y el informe también lista cuántas veces se ejecutó cada comando y cuántas veces lo bloqueó su precondición.

## Cuando cuesta encontrar una propiedad

- Empieza por **nunca falla**, y luego añade **ida y vuelta** e **invariantes**: no necesitan valores esperados.
- Si tienes dos implementaciones, o una versión antigua y una nueva, usa **oráculo**.
- Si el sistema tiene estado (una caché, una cola, una conexión, un circuit breaker), usa una **máquina de estado**.
- Si la propiedad solo es cierta para algunas entradas, genera esas entradas directamente. `assume` y `filter` descartan casos, y demasiados descartes detienen la ejecución con un mensaje que lo indica.
