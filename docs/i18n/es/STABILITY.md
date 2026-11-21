**Idiomas:** [English](../../STABILITY.md) · [Português (BR)](../pt-BR/STABILITY.md) · Español · [中文](../zh-CN/STABILITY.md)

> Traducción de [STABILITY.md](../../STABILITY.md). En caso de discrepancia, prevalece la versión en inglés.

# Política de estabilidad

En qué puedes confiar entre versiones de proptest, qué puede cambiar y cómo se anuncia cada cambio. Requisito RL15; garantizado por golden tests (Q7); motivos en [ADR-0015](../../decisions/0015-stability-policy.md).

**En resumen:** dentro de una versión minor (1.0.0, 1.0.1, 1.0.2, ...) la misma semilla produce los mismos valores, la misma exploración y el mismo contraejemplo. Los cambios en cualquiera de esas cosas solo ocurren en una nueva versión minor, y cada uno se lista en el CHANGELOG bajo **Generation changes**.

## Por qué te importa

Una semilla es una promesa de que una ejecución se puede repetir. Si la generación cambiara en una versión patch, una `PROPTEST_SEED` copiada ayer de un fallo de CI podría repetir otra cosa hoy, tras una actualización inocente de dependencias. Tus propias pruebas de regresión que fijan una semilla (`initSettings(seed = 42)`) empezarían a comprobar otras entradas sin que cambiara nada en tu código.

La promesa opuesta, "los valores nunca cambian", congelaría la biblioteca: mejores casos límite, generadores más rápidos y una reducción más lista cambian valores. La política se queda en el medio: se permiten cambios, pero solo en una frontera de versión que tú eliges cruzar, y siempre anunciados.

<a id="what-stays-the-same-within-a-minor-version"></a>
## Qué se mantiene igual dentro de una versión minor

Con la misma versión de proptest (incluidas las versiones patch), el mismo código de prueba y los mismos ajustes:

| Qué | Cubre |
|---|---|
| **Valores generados** | cada generador nativo (`x in T` para cada tipo soportado, objetos derivados, case objects, `distinct`, `ref`, contenedores), cada combinador, y las primitivas de sorteo que usan tus propios generadores (`drawInt`, `drawBool`, `drawIndex`, `drawFloat`, ...) |
| **La ejecución** | cómo la semilla de ejecución se convierte en la semilla de cada propiedad (a partir de su `name`), cómo crecen los tamaños a lo largo de la ejecución, el sesgo hacia casos límite, las constantes extraídas y las pistas `near`, el swarm testing, cuántos casos se descartan |
| **Secuencias con estado** | qué comandos se ejecutan, en qué orden, con qué argumentos |
| **Reducción** | el camino que sigue el reductor y el contraejemplo mínimo informado, para cada fallo encontrado |
| **Base de fallos** | su formato de archivo (`proptest-db 1`) y cómo se indexan las entradas |
| **Informe JSON** | el significado de cada campo de `format` 1 |

Esto vale en cada plataforma y compilación que prueba el CI: Linux, macOS y Windows; debug y release; `--mm:orc` y `--mm:arc`; hilos activados y desactivados; Nim 2.2.4 (Nim devel también se prueba, como fallo permitido: un cambio en el compilador podría romperlo antes de que una versión lo anuncie). El generador aleatorio y el hash son propios de la biblioteca, comprobados contra vectores de referencia, así que nada depende de `random` ni de `hash` de la biblioteca estándar, que pueden cambiar entre versiones de Nim.

### Qué significa "el mismo código de prueba"

Tu código decide parte de lo que se genera, así que algunas ediciones tuyas cambian valores incluso con la misma versión de la biblioteca y la misma semilla:

- **Mover una propiedad.** Su nombre por defecto es `file:line`, y su semilla viene de su nombre. Dale un `name` para conservar su semilla cuando se mueven las líneas.
- **Literales enteros en el archivo de pruebas.** Se proponen como valores frontera (`mineConstants`). Añadir un literal al archivo puede cambiar lo que generan otras propiedades del mismo. `mineConstants = false` hace una propiedad independiente de su archivo.
- **Tus propios generadores** y el orden en que sortean.
- **Ajustes que dan forma a las entradas:** `cases`, `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm`, `mineConstants`, incluidos los del entorno (`PROPTEST_CASES`).

[CONFIGURATION.md](CONFIGURATION.md#what-a-replay-needs) lista lo que necesita una repetición.

## Qué puede cambiar en cualquier versión

Esto no está cubierto: depender de ello en una prueba haría frágil la prueba.

- **El informe de texto**: redacción, disposición, qué estadísticas y avisos se imprimen. Analiza el [informe JSON](README.md#json-report-for-ci) en su lugar.
- **Cómo se imprimen los valores** (`show`, `showCode`) cuando el cambio los hace más claros o más correctos. Un bloque `replayCommands` impreso por una versión anterior sigue siendo Nim válido, pero una versión más nueva puede imprimirlo de otra forma.
- **Health checks y avisos**: nuevos checks, otros umbrales.
- **Todo lo que depende del tiempo**: `deadline`, `timeBudget`, `shrinkTimeBudget`, el check de generación lenta. Una máquina más rápida ejecuta más casos dentro de un presupuesto de tiempo.
- **Rendimiento**: el número de ejecuciones de reducción para llegar al mismo contraejemplo puede bajar (el contraejemplo en sí sigue igual dentro de una versión minor).
- **API nueva**: nuevos generadores, combinadores, ajustes, campos en `PropertyResult` y nuevos campos en el informe JSON. Añadir un campo nunca cambia `format`.

## Cómo se anuncian los cambios

La entrada de cada versión en el CHANGELOG agrupa los cambios por tipo:

| Encabezado | Contiene | Permitido en |
|---|---|---|
| **Added**, **Fixed**, **Changed** | API nueva, correcciones de bugs, cambios en el informe o en la documentación | cualquier versión |
| **Generation changes** | cualquier cosa de [Qué se mantiene igual](#what-stays-the-same-within-a-minor-version): valores, exploración, reducción, formatos de archivo | una versión minor (x.y.0) |
| **Breaking** | cambios de API que hacen que el código deje de compilar o cambie de significado | una versión major (x.0.0) |

Una entrada en **Generation changes** dice qué cambia, para qué generadores o ajustes, y si las semillas guardadas y las entradas de la base de fallos se siguen repitiendo. Los cambios de generación se agrupan: varios llegan juntos en una versión minor, para que las semillas dejen de repetirse una sola vez y no tras cada mejora.

Un cambio de API **Breaking** va precedido, cuando es posible, por una versión `{.deprecated.}` de la API antigua durante al menos una versión minor, con un mensaje que nombra el reemplazo.

Una corrección de bug que cambia valores (un generador que nunca podía producir algún valor que debería) sigue siendo un cambio de generación: espera a la siguiente versión minor salvo que el bug haga la biblioteca inutilizable, en cuyo caso la versión patch lo indica bajo **Generation changes**.

## Cuando actualizas

- **Versión patch (1.0.1 → 1.0.2):** nada que hacer. Las semillas, las pruebas fijadas y los fallos guardados siguen funcionando.
- **Versión minor (1.0 → 1.1):** lee **Generation changes**. Las semillas impresas por la versión antigua repiten otras entradas: repite los fallos antiguos de CI con la versión antigua. Las propiedades con una `seed` fija pasan a comprobar otras entradas, lo que normalmente está bien; revisa cualquier prueba que afirme los valores exactos que produce una semilla. La base de fallos no necesita nada: las entradas que ya no encajan con los generadores se descartan, las que ahora pasan se olvidan tras tres ejecuciones, y un bug real sigue fallando.
- **Para conservar una entrada concreta para siempre**, no dependas de una semilla: escríbela con `example(...)` o, para máquinas de estado, pega el bloque `replayCommands` en una prueba. Esos no dependen de la generación en absoluto.

## Cómo se garantiza

- **Golden snapshot** (`tests/t_golden.nim`, `tests/golden/snapshot.txt`): ejecuta 51 propiedades a través de todo el pipeline (cada tipo y combinador, tipos derivados, constantes extraídas, sesgo hacia límites, tamaños, swarm, reducción de varios bugs de referencia, una máquina de estado, el archivo de la base de fallos) y compara un hash de cada valor generado y de cada candidato de reducción, más muestras legibles, con el snapshot confirmado en el repositorio. El CI lo ejecuta en cada plataforma y modo de compilación de arriba.
- **Vectores de referencia** (`tests/t_prng.nim`): el generador aleatorio y el hash frente al código de referencia de sus autores y los vectores oficiales de FNV-1a.
- **Proceso**: cuando falla la prueba del snapshot, el mensaje lo dice. Un cambio intencionado se registra con `nimble golden` y una entrada en el CHANGELOG bajo **Generation changes** en el mismo commit; cualquier otra cosa es una regresión que corregir.

La prueba del snapshot es la evidencia de que una versión patch cumple su promesa: si pasa en el commit de la versión, la versión genera exactamente lo mismo que la anterior de la misma versión minor.
