**Idiomas:** [English](../../../README.md) · Português (BR) · [Español](../es/README.md) · [中文](../zh-CN/README.md)

> Tradução do [README em inglês](../../../README.md). Em caso de divergência, vale a versão em inglês.

# proptest

Uma **biblioteca de testes baseados em propriedades para a linguagem [Nim](https://nim-lang.org)**, distribuída como pacote Nimble. Declare uma regra, deixe a biblioteca gerar as entradas e receba a **menor** entrada que a quebra.

> Propriedades sobre tipos nativos e **seus próprios objetos, sem código de gerador**, e testes stateful (baseados em modelo), com shrinking automático, falhas repetidas primeiro na execução seguinte, estatísticas de cobertura e exploração que busca valores de fronteira. Versão 1.0: a API e os valores gerados para uma seed seguem a [política de estabilidade](STABILITY.md). Veja os [recursos](#features).

## Instalação

```sh
nimble install https://github.com/kaio-souza/nim-proptest
```

Ou a partir de um clone: `nimble install` (ou `nimble develop` para trabalhar nele). Requer Nim >= 2.2.4; sem dependências fora da biblioteca padrão.

## Início rápido

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

A segunda propriedade está errada, e o relatório mostra o contraexemplo **mínimo** (100, e não um número par grande qualquer) e como repeti-lo:

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

Versões executáveis: [`examples/quickstart.nim`](../../../examples/quickstart.nim) (com bugs plantados), [`examples/tour.nim`](../../../examples/tour.nim) (todos os recursos abaixo), [`examples/generators.nim`](../../../examples/generators.nim) (o guia de geradores), [`examples/patterns.nim`](../../../examples/patterns.nim) (o livro de padrões) e [`examples/stateful.nim`](../../../examples/stateful.nim) (o tutorial stateful); compiladas e executadas no CI.

## Escrevendo propriedades

### Variáveis: `name in source`

Cada variável é um **tipo** (o gerador é inferido) ou um **valor gerador**:

```nim
forAll(xs in seq[int], s in string, flag in bool): ...     # types
forAll(n in ints(0, 100), word in strings("abc", 1, 5)): ... # generator values
```

As fontes são avaliadas uma vez por propriedade. `forAll(x: int)` não funciona: o Nim interpreta uma chamada cujos argumentos parecem todos `name: value` como construtor de objeto, antes de qualquer macro rodar.

### Asserções

Dentro de `forAll`, `check` e `require` são reescritos para que um caso que falha seja capturado em silêncio e só a falha final, já reduzida, seja relatada (uma vez). `doAssert`, qualquer exceção lançada e `Defect`s (erros de índice, overflow...) também contam como falhas.

### Descartando casos: `assume`

```nim
forAll(a in ints(-1000, 1000), b in ints(-1000, 1000)):
  assume(b != 0)
  check a mod b == a - (a div b) * b
```

Casos descartados demais encerram a execução com um relatório de "gave up". Prefira gerar valores válidos diretamente a usar `assume` e `filter`.

### Configurações

Passe um valor `initSettings(...)` entre os argumentos. A maioria das propriedades não precisa de nenhum. As tabelas abaixo são um resumo; [CONFIGURATION.md](CONFIGURATION.md) traz receitas (CI, execuções noturnas, repetição, propriedades lentas), o custo de cada configuração e quais precisam ser iguais para uma seed se repetir.

```nim
forAll(initSettings(cases = 500, maxShrinks = 5_000), x in int8): ...
```

| Configuração | Padrão | Significado |
|---|---|---|
| `cases` | 100 | Casos a executar |
| `maxSteps` | 50 | Testes stateful: comandos por sequência |
| `maxDepth` | 5 | Aninhamento de dados recursivos durante a exploração |
| `maxShrinks` | 2000 | Orçamento de execuções para reduzir cada falha |
| `maxSize` | 100 | Tamanho atingido no último caso (limita o comprimento típico das coleções) |
| `maxDiscardRatio` | 10 | Desiste após `cases × ratio` casos descartados |
| `maxFailures` | 3 | Falhas distintas relatadas por propriedade |
| `maxChoices` | 8192 | Escolhas aleatórias por caso; casos maiores são descartados |
| `deadline` | 0 (desligado) | Limite por caso em ms: casos mais lentos falham e são reduzidos |
| `timeBudget` | 0 (nenhum) | Limite de tempo da exploração em ms; para de forma controlada e avisa |
| `shrinkTimeBudget` | 0 (nenhum) | Limite de tempo do shrinking por falha em ms; mantém o melhor até ali |
| `edgeBias` | 0.25 | Fração de propostas de casos de borda (limites, 0, 1, floats especiais, coleções vazias e de um elemento) |
| `mineConstants` | true | Constantes inteiras da propriedade e do arquivo de teste como dicas de fronteira |
| `swarm` | true | Testes stateful: metade das sequências deixa alguns comandos de fora |
| `verbosity` | `vNormal` | `vQuiet`, `vNormal`, `vVerbose` (cada caso, cada estatística), `vDebug` (passos do shrinking) |
| `suppress` | `{}` | Health checks a pular: `hcLargeData`, `hcFewDistinct`, `hcSlowGeneration` |
| `hangTimeout` | 0 (desligado) | Watchdog: um caso que roda por mais tempo (ms) é relatado e salvo, e o programa sai com código 1 |
| `report` | `PROPTEST_REPORT` | Arquivo JSON Lines ao qual cada resultado é anexado; vazio: nenhum |
| `seed` | aleatória | Fixa a seed da execução |
| `name` | `file:line` | Nome da propriedade; dele deriva sua própria seed |

| Variável de ambiente | Efeito |
|---|---|
| `PROPTEST_SEED` | Repete uma execução (impressa em todo relatório de falha) |
| `PROPTEST_CASES` | `cases` padrão, por exemplo mais no CI do que localmente |
| `PROPTEST_MAX_SHRINKS` | `maxShrinks` padrão |
| `PROPTEST_DB` | Diretório dos arquivos locais: seed da execução, banco de falhas (padrão `.proptest`), ou `off` |
| `PROPTEST_DEADLINE` | `deadline` padrão em ms (por exemplo, defina no CI) |
| `PROPTEST_TIME_BUDGET` | `timeBudget` padrão em ms |
| `PROPTEST_VERBOSITY` | `quiet`, `normal`, `verbose` ou `debug` |
| `PROPTEST_REPORT` | `report` padrão: um arquivo JSON Lines para ferramentas de CI (abaixo) |
| `PROPTEST_HANG_TIMEOUT` | `hangTimeout` padrão em ms (recomendado no CI, por exemplo 60000) |

<a id="json-report-for-ci"></a>
### Relatório JSON para CI

`PROPTEST_REPORT=proptest-report.jsonl nimble test` anexa uma linha de JSON por propriedade a esse arquivo (ele é criado junto com seu diretório; vários programas de teste podem compartilhá-lo). Cada linha tem `format` (1), `name`, `status` (`passed`, `failed`, `flaky`, `gaveUp`, `generatorError`, `insufficientCoverage`, ou `hung` vindo do [watchdog](TROUBLESHOOTING.md#the-test-hangs), cuja linha tem menos campos), `passed`, `seed` (uma string: não cabe num número JSON), `program`, `replay` (o comando que repete a execução), `casesPassed`, `discarded`, `firstFailureAt`, `durationMs`, `message`, `labeledCases`, `labels` (`name`, `kind`, `cases`, `events`, `required` para `cover`), `targets` (`label`, `best`: a melhor pontuação de `target` por nome), `warnings`, e `failures`: `kind` e `location` (a assinatura da falha), `message`, `source` (`explored`, `database`, `example`), `flaky`, `choices`, `shrinkExecutions`, `shrinkStopped`, `inputs` (`name`, `value`), `machine` e `steps` para máquinas de estado, `stackTrace`. Campos podem ser acrescentados; um campo que muda de significado ou desaparece incrementa `format`.

```sh
jq -r 'select(.passed | not) | "\(.name): \(.status), \(.replay)"' proptest-report.jsonl
```

## Geradores

### Tipos, inclusive os seus

`x in T` gera qualquer um destes, aninhados de qualquer forma, sem código: inteiros de todas as larguras (inclusive tipos `range`), `float`/`float32` (inclusive NaN, infinitos e -0.0), `bool`, `char`, `string`, enums, `seq`, `array`, `set`, `Option`, tuplas, `Table`, `OrderedTable`, `HashSet` e **seus próprios tipos**:

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

Objetos, case objects, `distinct` e objetos `ref` são derivados campo a campo; um bug em um ramo de um case object é reduzido àquele ramo com os campos mais simples, e um bug em árvore à menor árvore. Inteiros atingem `low(T)` e `high(T)` com frequência, porque é ali que os bugs moram. Guia: [GENERATORS.md](GENERATORS.md).

### Combinadores

| Gerador | Valores | Reduz em direção a |
|---|---|---|
| `ints(lo, hi)`, `ints()`, `ints(lo, hi, near = [v])` | inteiros em `lo .. hi`; `near` propõe `v-1`, `v`, `v+1` | o valor mais próximo de 0 |
| `floats(lo, hi)`, `floats(allowNaN, allowInf)` | floats | 0.0 |
| `bools()` | `bool` | `false` |
| `chars(alphabet)` | caracteres de `alphabet` | seu primeiro caractere |
| `strings(alphabet, minLen, maxLen)` | strings | mais curtas, primeiros caracteres |
| `seqs(g, minLen, maxLen)` | `seq` de valores de `g` | mais curtas, elementos mais simples |
| `tables(k, v, ...)`, `hashSets(g, ...)` | contêineres de valores gerados | menos entradas, mais simples |
| `uniqueSeqs(g, ...)`, `sortedSeqs(g, ...)` | `seq` de valores distintos, ou em ordem crescente | mais curtas, elementos mais simples |
| `sized(proc(n: int): Gen[T] = ...)`, `g.resize(n)` | um gerador construído a partir do tamanho atual, ou com tamanho fixo | tamanhos menores |
| `strings(alphanumeric, ...)`, `identifiers(maxLen)`, `unicodeStrings(minLen, maxLen)` | letras e dígitos (`alphanumeric` é um alfabeto), identificadores, UTF-8 válido em todos os planos | mais curtas, `a` |
| `frequency([(w, g), ...])` | um gerador, escolhido por peso | a primeira entrada |
| `recursive(base, extend, maxDepth)` | árvores: cada nível é `base` ou um nível mais fundo | `base` |
| `optionals(g)` | `Option` | `none` |
| `elements([a, b, c])` | um dos valores | o primeiro |
| `oneOf(g1, g2, ...)` | um valor de um dos geradores | o primeiro gerador |
| `constant(v)` | sempre `v` | |
| `g.map(f)`, `g.filter(pred)`, `g.flatMap(f)` | valores transformados | através do gerador original |
| `gen(T)` | o gerador inferido pelo tipo, como valor | |

Você nunca escreve um shrinker: todo gerador, inclusive cadeias de `map`, `filter` e `flatMap`, é reduzido automaticamente, e os valores reduzidos continuam satisfazendo o filtro.

### Quando os campos precisam concordar: escreva `arbitrary`

A derivação preenche cada campo de forma independente. Quando os campos precisam concordar (um início antes de um fim), sobrecarregue `arbitrary`; ele sempre tem prioridade sobre a derivação:

```nim
proc arbitrary(src: ChoiceSource; t: typedesc[Money]): Money =
  Money(cents: src.drawInt(0, 1_000_000),
        currency: elements(["USD", "EUR", "BRL"]).generate(src))
```

Ou construa um valor gerador com `newGen` a partir das primitivas de sorteio (`drawInt`, `drawBool`, `drawIndex`, `drawFloat`, `drawFloatRange`, `drawUpTo`). A única regra: uma escolha menor deve significar um valor mais simples, o que todas as primitivas já seguem.

```nim
let sortedPairs = newGen(proc(src: ChoiceSource): (int, int) =
  let a = src.drawInt(-100, 100)
  let b = src.drawInt(a, 100)
  (a, b))
```

## Encontrando mais bugs e vendo o que foi testado

Passar não diz nada sobre entradas que nunca foram geradas. Formas de verificar e de direcionar isso (design: [ADR-0012](../../decisions/0012-bug-finding-power.md); padrões: [PATTERNS.md](PATTERNS.md)):

```nim
forAll(initSettings(cases = 300), xs in seq[int]):
  classify(xs.len == 0, "empty")          # share of cases, printed after the run
  cover(20.0, xs.len >= 10, "ten or more") # fails if confidently below 20%
  label("len " & $min(xs.len, 3))         # cases by a computed text
  check ...
```

- **Fronteiras.** Inteiros atingem 0, 1, -1 e os limites do tipo; floats atingem -0.0, NaN, infinitos e subnormais; coleções atingem vazia e de um elemento. Constantes inteiras usadas na propriedade (`const openFor = 1000`) e literais inteiros do arquivo de teste são propostos como `v - 1`, `v`, `v + 1`. Para uma fronteira definida em outro lugar: `ints(0, 2000, near = [openFor])`.
- **Swarm testing** (máquinas de estado): metade das sequências deixa alguns comandos de fora, então longas sequências dos outros ficam prováveis (um bug que exige 12 incrementos sem reset: encontrado em 3 de 100 seeds antes, 97 de 100 com ele).
- **Exploração direcionada** para estados profundos que casos aleatórios raramente alcançam: dê ao motor uma pontuação para subir, e depois de metade dos casos ele estende o melhor caso até ali.
  ```nim
  stateMachine Breaker:
    ...
    invariant:
      target(float(model.reopenings), "reopenings")   # climb toward many reopenings
  ```
  O limite de backoff de um circuit breaker (cinco reaberturas seguidas) foi encontrado em 3 de 100 seeds sem isso, 20 com isso. Ajuda quando o progresso se acumula ao longo de uma sequência; para valores independentes, prefira dicas `near` ou um gerador dedicado.
- **Deadlines e orçamentos**: `deadline` faz de um caso lento uma falha, reduzida ao que o deixa lento; `timeBudget` e `shrinkTimeBudget` param antes e avisam.
- **Health checks** alertam, com uma correção, sobre dados grandes demais para `maxChoices`, espaços de entrada menores que `cases` e geração dominando o tempo de execução.

O poder de encontrar bugs da própria biblioteca é medido: [`benchmarks/b_find.nim`](../../../benchmarks/b_find.nim) roda bugs plantados em seeds fixas e o CI falha se uma taxa de detecção cair.

## Resultados e falhas

Algo parece errado (gave up, flaky, um aviso, uma seed que não se repete)? [TROUBLESHOOTING.md](TROUBLESHOOTING.md) parte do que você vê.

- **Dentro de um `test` do unittest**: uma propriedade que falha faz o teste falhar com um único relatório.
- **Em outros lugares**: `forAll` lança `PropertyError` (com `.propertyResult`), e `forAllResult(...)` (mesmos argumentos) retorna o `PropertyResult` sem lançar.

| Status | Significado |
|---|---|
| `psPassed` | todos os casos passaram |
| `psFailed` | ao menos um contraexemplo, executado de novo duas vezes para confirmar |
| `psFlaky` | o contraexemplo mínimo não falhou de novo: a propriedade depende de tempo, estado global, threads ou I/O |
| `psGaveUp` | casos demais descartados por `assume` ou `filter` |
| `psGeneratorError` | um gerador lançou exceção: um bug no gerador, não no código testado |
| `psInsufficientCoverage` | todos os casos passaram, mas um requisito de `cover` não foi atingido com confiança |

Lendo o resultado no código (`forAllResult`, `stateMachineResult`, ou `.propertyResult` de um `PropertyError`):

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

`r.status` é um dos valores acima; `r.runSeed` repete a execução; `r.casesRun`, `r.discarded`, `r.labels` e `r.warnings` guardam as estatísticas e os health checks que o relatório imprime. Cada falha também tem `choices` (sua sequência mínima de escolhas), `shrinkExecutions`, `shrinkStopped` (o shrinking atingiu `shrinkTimeBudget`), `flaky` e `stackTrace`.

Até `maxFailures` bugs **distintos** (tipo de exceção ou local diferentes) são relatados separadamente, cada um reduzido por conta própria; o shrinking nunca transforma um bug em outro.

**Reproduzindo**: todo relatório imprime `PROPTEST_SEED=<n>`; rode o mesmo binário com ela para obter os mesmos casos e o mesmo contraexemplo. A seed também é gravada em `.proptest/last-run` antes do primeiro caso, então sobrevive a um crash.

**Falhas continuam encontradas**: cada falha reproduzida é salva em `.proptest/db/` e repetida **antes de qualquer caso aleatório** nas próximas execuções, então uma correção é verificada na hora; uma entrada é esquecida depois de passar três execuções seguidas. `PROPTEST_DB=off` desliga isso. Adicione `.proptest/` ao seu `.gitignore` (o CI pode fazer cache dele). Para fixar um caso de vez, adicione `example(...)` (um valor por variável, executado primeiro) ou cole o bloco `replayCommands` de um relatório stateful em um teste:

```nim
forAll(x in int, s in string, example(0, ""), example(-1, "a")): ...
```

<a id="features"></a>
## Recursos

- `forAll` / `forAllResult` com tipos e valores geradores
- Geradores para tipos nativos, combinadores, `arbitrary` e `newGen` próprios
- Shrinking integrado, múltiplas falhas distintas, detecção de flaky
- Reescrita de `check`/`require`, `assume`, configurações, variáveis de ambiente
- Integração com `std/unittest` e `unittest2`; uso independente
- Relatório JSON para ferramentas de CI (`PROPTEST_REPORT`)
- Repetição por seed e rastro de crash (Linux, macOS e Windows no CI)
- Testes stateful / baseados em modelo: `stateMachine`, menor sequência que falha impressa como código `replayCommands`
- Geradores derivados para objetos, case objects, `distinct`, `ref` e tipos recursivos; `Table`, `HashSet`; `frequency`, `recursive`; strings Unicode
- Banco de falhas (falhas passadas repetidas primeiro), `example(...)` explícito
- `classify` / `cover` / `label`, estatísticas stateful, níveis de verbosidade
- Viés para casos de borda, dicas de fronteira (`near`, constantes mineradas), swarm testing
- Deadline por caso, orçamentos de tempo para execução e shrinking, health checks
- Referência de configuração e guia de solução de problemas, verificados contra o código no CI
- Política de estabilidade: uma seed se repete entre versões patch, verificada por um golden snapshot ([STABILITY.md](STABILITY.md))
- `sized`, `resize`, `uniqueSeqs`, `sortedSeqs`, exploração direcionada (`target`)
- Watchdog (opcional, `PROPTEST_HANG_TIMEOUT`): um caso que nunca retorna é relatado (entradas, escolhas, repetição) e salvo, em vez de travar a execução (requer `--threads:on`, o padrão do Nim)

## Limitações conhecidas

- **Um caso que nunca retorna trava a execução, a menos que o watchdog esteja ligado**: com `PROPTEST_HANG_TIMEOUT=60000` (recomendado no CI; desligado por padrão) ele é relatado e salvo depois desse tempo, e o programa sai com código 1, porque um caso em execução não pode ser interrompido com segurança. Ele não pode ser reduzido, e suas entradas são impressas na execução seguinte (ou na hora com `PROPTEST_VERBOSITY=verbose`). Sem `--threads:on` não há watchdog.
- **Estados profundos continuam difíceis**: um estado que exige um caminho longo e específico (cinco reaberturas seguidas de um breaker, cada uma após a espera certa) raramente é alcançado por sequências aleatórias. `target(score)` ajuda quando a propriedade consegue medir o progresso (3 → 20 de 100 seeds para o breaker); para um caminho que você já conhece, escreva-o como um teste `replayCommands`.
- **Builds release só localizam falhas de `check`**: sem `--stackTrace:on --lineTrace:on` (`-d:release`, `-d:danger`), as outras exceções são diferenciadas apenas pelo tipo, então dois bugs que lançam o mesmo tipo são relatados como um. Um aviso em tempo de compilação diz isso; veja [TROUBLESHOOTING.md](TROUBLESHOOTING.md#two-bugs-reported-as-one-or-location-unknown).
- **`--panics:on`**: `Defect`s encerram o processo no primeiro caso que falha, então ele não pode ser reduzido (um aviso em tempo de compilação diz isso).
- Um `except CatchableError` amplo dentro do corpo da propriedade também captura os sinais internos da biblioteca (`assume`, `check` que falhou); relance-os ou capture tipos mais específicos.
- Os valores gerados para uma seed só mudam em versões minor, sempre listados no [CHANGELOG](../../../CHANGELOG.md) ([política de estabilidade](STABILITY.md)), então uma seed antiga pode não se repetir após uma atualização minor.

## Testes stateful

Sequências aleatórias de comandos rodam contra o sistema real e contra um modelo simples; depois de cada passo, os dois precisam concordar. Uma falha é relatada como a **menor** sequência que falha, impressa como código Nim para colar como teste de regressão. Tutorial completo: [STATEFUL.md](STATEFUL.md).

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

Com uma fila cujo `pop` erra depois de exatamente 3 pushes e 1 pop:

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

O tempo é um comando (`command advance(ms in ints(0, 2000))` movendo um relógio falso), então bugs dependentes de tempo são reduzidos a esperas exatas. `teardown:` sempre roda; argumentos podem ser tirados do modelo (`k in elements(model.keys)`).

## Qualidade

- 158 testes, passando em `orc`/`arc` × threads ligadas/desligadas × debug/release; ASan, UBSan e verificação de vazamentos limpos.
- O PRNG e o hash batem com as implementações de referência em C de seus autores e com os vetores oficiais do FNV-1a (golden tests).
- Testes de valor: cada bug de referência da [SPEC](../../SPEC.md) é reduzido ao seu contraexemplo mínimo exato; dois bugs independentes são ambos relatados, e o shrinking nunca escorrega de um bug para outro (verificado em 20 seeds).
- Gates determinísticos no CI: reduzir cada bug de referência leva de 9 a 236 execuções (baseline em `benchmarks/baseline/shrink.json`); bugs plantados precisam continuar sendo encontrados em tantas seeds quanto no baseline (`benchmarks/baseline/find.json`); sortear escolhas e executar passos stateful nunca aloca memória, e um teste verifica o mesmo para labels estáticos.
- Primeiro usuário externo: o teste de modelo de [`nim-circuit-breaker`](https://github.com/kaio-souza/nim-circuit-break) roda 1000 sequências aleatórias contra seu breaker.
- Todo requisito tem uma linha em [`TRACEABILITY.md`](../../TRACEABILITY.md), verificada por `nimble trace`. Decisões de design: [`decisions/`](../../decisions/README.md).

```sh
nimble test     # test suite
nimble gate     # deterministic performance gates
nimble bench    # timings (informational)
nimble trace    # traceability matrix
```

## Licença

[MIT](../../../LICENSE)
