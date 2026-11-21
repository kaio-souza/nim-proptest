**Idiomas:** [English](../../TROUBLESHOOTING.md) · Português (BR) · [Español](../es/TROUBLESHOOTING.md) · [中文](../zh-CN/TROUBLESHOOTING.md)

> Tradução de [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md). Em caso de divergência, vale a versão em inglês. Os relatórios abaixo ficam em inglês, como a biblioteca os imprime.

# Solução de problemas

Encontre o que você está vendo, depois leia por que acontece e o que fazer. Os relatórios abaixo são saídas reais (nomes de arquivo encurtados). Toda configuração mencionada está descrita em [CONFIGURATION.md](CONFIGURATION.md).

**A propriedade falha ou para**

- [Gave up after N passing cases](#gave-up-after-n-passing-cases)
- [FLAKY: o caso mínimo não falhou de novo](#flaky-the-minimal-case-did-not-fail-again)
- [Um gerador lançou exceção](#a-generator-raised)
- [Requisitos de cobertura não atingidos](#missed-its-coverage-requirements)
- [DeadlineExceeded](#deadlineexceeded)
- [O teste trava](#the-test-hangs)
- [O processo termina sem relatório](#the-process-ends-with-no-report)

**O relatório surpreende**

- [Dois bugs relatados como um, ou "Location unknown"](#two-bugs-reported-as-one-or-location-unknown)
- [O contraexemplo não é tão pequeno quanto poderia](#the-counterexample-is-not-as-small-as-it-could-be)
- [Repetido do banco de falhas](#replayed-from-the-failure-database)
- [`PROPTEST_SEED` não reproduz a falha](#proptest_seed-does-not-reproduce-the-failure)

**Passa, mas deveria?**

- [A propriedade passa, mas o bug está lá](#the-property-passes-but-the-bug-is-there)
- [Aviso: only N distinct inputs](#warning-only-n-distinct-inputs)
- [Aviso: cases needed more than maxChoices](#warning-cases-needed-more-than-maxchoices)
- [Aviso: generating inputs takes most of the run time](#warning-generating-inputs-takes-most-of-the-run-time)
- [Aviso: command never ran](#warning-command-never-ran)
- [Aviso: time budget reached](#warning-time-budget-reached)

**Outros**

- [A suíte de testes é lenta](#the-test-suite-is-slow)
- [A saída da propriedade inunda o terminal](#output-from-the-property-floods-the-terminal)
- [Um bloco `replayCommands` colado falha com "precondition ... is false"](#a-pasted-replaycommands-block-fails-with-precondition--is-false)
- [Erros de compilação](#compile-errors)

---

<a id="the-property-fails-or-stops"></a>
## A propriedade falha ou para

<a id="gave-up-after-n-passing-cases"></a>
### Gave up after N passing cases

```
Property 'sorted' gave up after 0 passing cases: 1001 cases discarded (0 by filters, 0 too large).
```

**Por quê.** Casos demais foram jogados fora: por `assume(...)`, por um `filter` ou `uniqueSeqs` que rejeitou 100 valores seguidos, ou porque eram grandes demais para `maxChoices`. Depois de `cases × maxDiscardRatio` descartes (1000 por padrão) a propriedade para, porque já não está testando muita coisa. Quando a maioria dos descartes vem de filtros, a mensagem acrescenta "Most discards come from `filter` or `uniqueSeqs` rejecting values: generate valid values directly, or widen the generator."

Acima, a propriedade queria listas ordenadas de pelo menos 5 elementos, e listas aleatórias desse tamanho quase nunca estão ordenadas.

**O que fazer.** Gere valores válidos em vez de rejeitar os inválidos:

```nim
# Gives up: rejects every case.
forAll(xs in seq[int]):
  assume(xs.len >= 5 and xs.isSorted)
  ...

# Passes 100 cases: builds only valid inputs, and still shrinks.
forAll(xs in sortedSeqs(ints(), minLen = 5)):
  ...
```

`sortedSeqs` e `uniqueSeqs` cobrem os dois formatos mais comuns. Para valores que dependem um do outro (um início antes de um fim), sorteie o primeiro e depois o segundo dentro do intervalo dele, como em [GENERATORS.md](GENERATORS.md). Guarde `assume` para exclusões raras (`assume(d != 0)`).

Os tamanhos crescem a cada tentativa, inclusive as descartadas, então uma condição só sobre tamanho (`assume(xs.len > 30)`) só custa descartes no começo da execução: ela passa, com algumas centenas de descartes.

**Contrapartida.** Aumentar `maxDiscardRatio` faz a mensagem sumir, mas não o custo: cada caso descartado ainda roda o gerador, e os casos que passam são os poucos que por acaso se encaixaram, então podem ser todos parecidos.

<a id="flaky-the-minimal-case-did-not-fail-again"></a>
### FLAKY: o caso mínimo não falhou de novo

```
Property 'flaky' is flaky at case 3 (67 cases passed, 0 discarded).
  FLAKY: the minimal case did not fail again when re-run.
  Common causes: time, randomness, global state, threads or I/O in the property.
  Counterexample (1 choices, 1 shrink executions):
    x = 0
  Error: [PropertyFailed] check failed: counter mod 3 != 0
        counter mod 3 was 0
```

**Por quê.** Depois do shrinking, toda falha roda mais duas vezes. Se não falhar nas duas, o resultado não dependia só das entradas geradas. Acima, a propriedade lia um contador global que muda a cada execução.

**O que fazer.** Descubra o que a propriedade lê além das suas entradas:

- **Estado global ou de módulo**: um cache, um contador, um singleton. Crie estado novo dentro do corpo, ou reinicie-o no começo.
- **Tempo**: `now()`, `epochTime()`, timeouts. Injete um relógio e controle-o pela propriedade (o [tutorial stateful](STATEFUL.md) faz isso com um relógio falso).
- **Aleatoriedade** no código testado: use como seed um valor gerado (`seed in uint64`).
- **Threads, arquivos, rede**: ordem e tempo mudam entre execuções. Teste a lógica sem eles, ou faça o teste ser dono do recurso (um diretório temporário por caso).

O relatório ainda mostra o contraexemplo: o bug pode ser real, mas não reproduzível do jeito que está escrito. Não fique rodando de novo até passar.

<a id="a-generator-raised"></a>
### Um gerador lançou exceção

```
Property 'price': a generator raised: [ValueError] invalid integer:
  This is a problem in a generator, not in the code under test.
```

**Por quê.** A exceção veio da geração das entradas, antes de o corpo rodar: aqui, um `arbitrary` para `Money` chamou `parseInt` em uma string aleatória. A biblioteca para na hora em vez de relatar um bug que não está no seu código.

**O que fazer.** Corrija o gerador para que toda escolha dê um valor válido. Sorteie diretamente o que você precisa (`src.drawInt(0, 1_000_000)`) em vez de gerar algo mais amplo e converter.

Um erro diferente, com cara parecida: os geradores nativos lançam `ValueError` para argumentos impossíveis (`ints: lo > hi`, `seqs: invalid lengths`) quando a propriedade começa, antes de qualquer caso. Confira os argumentos.

<a id="missed-its-coverage-requirements"></a>
### Requisitos de cobertura não atingidos

```
Property 'empty lists' passed 100 cases but missed its coverage requirements:
    cover 'empty': 8.0% of 100 cases, 50.0% required
  Statistics (100 cases):
      8.0%  empty  (cover: 50.0% required)
```

**Por quê.** `cover(50.0, xs.len == 0, "empty")` pede que pelo menos 50% dos casos sejam listas vazias, e só 8% foram. Todos os casos passaram, mas os casos que você disse que importam foram raros, então a propriedade não testou o que você queria. Um requisito só falha quando até a ponta otimista de um intervalo estatístico fica abaixo dele; quando há casos de menos para ter certeza, vira um aviso ("too few cases to be sure; raise `cases`").

**O que fazer.** Ou o gerador deve produzir esses casos com mais frequência (um gerador dedicado, `frequency`, `near = [...]`), ou o requisito é rígido demais. Um requisito em torno da fração de que você realmente precisa para testar bem (5%, 10%) costuma estar certo; 50% para uma única situação significa que ela merece sua própria propriedade.

<a id="deadlineexceeded"></a>
### DeadlineExceeded

```
Property 'slow' falsified at case 2 (80 cases passed, 0 discarded).
  Counterexample (1 choices, 9 shrink executions):
    x = 16
  Error: [DeadlineExceeded] case took 10.2 ms; deadline 5.0 ms
```

**Por quê.** `deadline` (ou `PROPTEST_DEADLINE`) está definido, e um caso demorou mais. Ele é reduzido como qualquer falha, à menor entrada que continua lenta: aqui, o código dorme quando `x > 15`, e 16 é essa fronteira.

**O que fazer.** Se a lentidão é um bug (comportamento quadrático em alguma entrada), o contraexemplo mostra a entrada. Se é ruído (uma máquina de CI carregada, um build debug), aumente o deadline: defina-o bem acima do tempo normal dos casos. A exploração já permite 1,25 × o deadline, mas o shrinking e as re-execuções usam o próprio deadline, então um caso no limite também pode ser relatado como FLAKY.

<a id="the-test-hangs"></a>
### O teste trava

```
proptest: property 'hangs on 42' did not return: a case has run for more than 300 ms (hangTimeout) while exploring (case 1), running the property.
  Inputs: not recorded while exploring (formatting them would cost time on every case).
  The case was saved in the failure database: the next run replays it first and
  prints its inputs here if it still does not return.
  Choices (1): 42
  Replay: PROPTEST_SEED=1 ./t_hang
  The process stops here (exit code 1): a running case cannot be interrupted safely.
```

**Por quê.** Um caso nunca retorna: um loop infinito, um deadlock, a espera por um evento que nunca chega. `deadline` não consegue pegá-lo, porque mede um caso depois que ele retorna. O watchdog é desligado por padrão, então a execução simplesmente trava. Com `PROPTEST_HANG_TIMEOUT` definido (acima, 300 ms), depois desse tempo a thread watchdog relata o caso e encerra o processo: nada consegue interromper com segurança um caso em execução, então a execução não pode continuar e o caso não pode ser reduzido.

**O que fazer.**

1. Se a execução simplesmente trava sem relatório, interrompa-a e rode de novo com o watchdog ligado, por exemplo `PROPTEST_HANG_TIMEOUT=10000 nimble test` (a mesma seed vem de `.proptest/last-run`: `PROPTEST_SEED=<ela>`). Depois rode os testes mais uma vez. O caso foi salvo, então roda primeiro, com suas entradas registradas:
   ```
   proptest: property 'hangs on 42' did not return: ... while replaying a case that hung in an earlier run (case 1), running the property.
     Inputs:
       x = 42
   ```
   Uma máquina de estado mostra os passos em vez disso, sendo o último o passo que não retorna. Com `PROPTEST_DB=off` nada é salvo: repita com a seed e `PROPTEST_VERBOSITY=verbose`, que registra as entradas de todo caso.
2. Transforme a entrada em um teste comum, ou em um `example(...)`, e corrija o loop. Quando o caso salvo passar, ele é esquecido depois de três execuções.
3. No CI, mantenha o watchdog ligado, para que um travamento falhe com este relatório em vez de atingir o limite de tempo do job: `PROPTEST_HANG_TIMEOUT=60000`.

Sem `--threads:on` (o padrão do Nim 2 é ligado) não há watchdog: interrompa o processo, depois repita com a seed de `.proptest/last-run` e `PROPTEST_VERBOSITY=verbose`; o último caso impresso é o anterior ao que trava.

<a id="the-process-ends-with-no-report"></a>
### O processo termina sem relatório

**Por quê.** Normalmente `--panics:on`: um Defect (`IndexDefect`, `AssertionDefect`, overflow) encerra o processo em vez de ser lançado, então a biblioteca não consegue reduzi-lo nem relatá-lo. O compilador avisa: "proptest: compiled with --panics:on". Outras causas: uma falha de segmentação (acesso a `nil` sob `-d:danger`, ou em código C), ou `quit()` chamado pelo código testado.

**O que fazer.** Compile os testes com `--panics:off` (o padrão) e sem `-d:danger`. A seed está em `.proptest/last-run` para repetir o crash num depurador.

<a id="the-report-is-surprising"></a>
## O relatório surpreende

<a id="two-bugs-reported-as-one-or-location-unknown"></a>
### Dois bugs relatados como um, ou "Location unknown"

Build debug: dois bugs, duas falhas.

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

A mesma propriedade compilada com `-d:release`: uma falha, o segundo bug escondido.

```
Property 'two bugs' falsified at case 8 (53 cases passed, 0 discarded).
  Counterexample (2 choices, 17 shrink executions):
    x = 51
    y = 0
  Error: [ValueError] x too big
  Location unknown (no stack trace): failures are told apart by type only.
```

**Por quê.** Duas falhas são o mesmo bug quando têm o mesmo tipo de exceção e são lançadas na mesma linha do seu código. A linha vem do stack trace, que `-d:release` desliga. Falhas de `check` mantêm sua linha em qualquer build, porque a linha é registrada onde o `check` está escrito.

**O que fazer.** Rode testes de propriedade em builds debug, ou acrescente `--stackTrace:on --lineTrace:on` ao build release ([tabela](CONFIGURATION.md#compile-time-options)). Um build assim é anunciado em tempo de compilação pelo aviso "proptest: built without stack traces". O caso oposto, um bug relatado como vários, acontece quando o mesmo bug é lançado em linhas diferentes dependendo da entrada; os contraexemplos então se parecem, e corrigir um corrige os outros.

<a id="the-counterexample-is-not-as-small-as-it-could-be"></a>
### O contraexemplo não é tão pequeno quanto poderia

**Por quê**, do mais ao menos comum:

- **Um gerador próprio quebra a regra do shrinking**: uma escolha menor deve dar um valor mais simples. `src.drawInt(0, 100)` segue a regra; `100 - src.drawInt(0, 100)` a inverte, então o shrinking anda em direção a 100. Mapeie escolhas simples para valores simples.
- **O shrinking parou cedo**: o relatório diz "Shrinking stopped at its time budget" (`shrinkTimeBudget`), ou as execuções mostradas são iguais a `maxShrinks`. Aumente o orçamento, ou torne cada execução mais rápida.
- **O mínimo não está onde você espera**: o shrinking minimiza as *escolhas*, o que para os geradores nativos significa coleções mais curtas, valores mais próximos de 0, o primeiro valor do enum, o primeiro ramo de `oneOf`. `x = -1` pode ser o valor mais simples que falha quando `x = 1` passa.
- **Há um `filter` por cima**: valores reduzidos ainda precisam passar no filtro, o que pode bloquear valores mais simples. Gerar valores válidos diretamente ajuda aqui também.

<a id="replayed-from-the-failure-database"></a>
### Repetido do banco de falhas

```
  Replayed from the failure database: it failed in an earlier run.
```

**Por quê.** Uma falha encontrada numa execução anterior foi salva em `.proptest/db/` e é repetida antes de qualquer caso aleatório, para que uma correção seja verificada na hora. Esta ainda falha.

**O que fazer.** Nada de especial: é uma falha real, com o mesmo relatório de quando foi encontrada. Uma entrada é esquecida depois de passar 3 execuções seguidas; entradas que não cabem mais nos geradores (você mudou os tipos) são descartadas. Para começar do zero, apague `.proptest/db/`; para desligar, `PROPTEST_DB=off`.

<a id="proptest_seed-does-not-reproduce-the-failure"></a>
### `PROPTEST_SEED` não reproduz a falha

**Por quê.** A seed reproduz uma execução só se todo o resto que decide as entradas for igual. Confira, na ordem:

1. **O código mudou.** A seed de uma propriedade vem do seu nome, que por padrão é seu `file:line`: acrescentar uma linha acima dela muda suas entradas. As constantes mineradas do arquivo também mudam. Use a seed com o binário que a imprimiu, ou dê um `name` à propriedade.
2. **As configurações diferem.** `cases` decide como os tamanhos crescem, então `PROPTEST_CASES=1000` com uma seed impressa por uma execução de 100 casos dá outras entradas. O mesmo vale para `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm` e `mineConstants`.
3. **A propriedade define `seed`.** Uma seed fixa nas configurações tem prioridade sobre `PROPTEST_SEED`.
4. **A propriedade não é determinística.** Se o relatório disse FLAKY, veja [acima](#flaky-the-minimal-case-did-not-fail-again).

Plataforma e modo de build não importam: a mesma seed dá os mesmos valores em Linux, macOS e Windows, debug e release.

<a id="it-passes-but-should-it"></a>
## Passa, mas deveria?

<a id="the-property-passes-but-the-bug-is-there"></a>
### A propriedade passa, mas o bug está lá

Uma propriedade que passa só diz que as entradas que ela tentou estavam bem. Veja o que ela tentou:

1. **Conte os casos que importam.** Acrescente `classify` para as situações de que o bug precisa, e `cover` se elas precisam acontecer:
   ```nim
   forAll(xs in seq[int]):
     classify(xs.len == 0, "empty")
     classify(xs.len > 100, "long")
     cover(1.0, low(int) in xs, "has low(int)")
     check ...
   ```
   As estatísticas são impressas depois de uma execução que passa.
2. **Olhe as entradas** com `PROPTEST_VERBOSITY=verbose PROPTEST_CASES=20`.
3. Então, conforme o que estiver faltando:

| Faltando | Correção | Contrapartida |
|---|---|---|
| um valor específico (um limite definido em outro módulo) | `ints(lo, hi, near = [limit])` | nenhuma: outros valores continuam sendo sorteados |
| entradas longas | aumente `maxSize`, ou `seqs(g, minLen = ...)` | casos mais lentos |
| uma combinação rara | mais `cases` (no CI: `PROPTEST_CASES`) | o tempo cresce linearmente |
| uma categoria inteira | um gerador dedicado, ou `frequency` | mais código para manter |
| estados profundos de uma máquina de estado | aumente `maxSteps`; mantenha `swarm` ligado | sequências mais longas |

Constantes inteiras no corpo da propriedade já são propostas como `v - 1`, `v`, `v + 1` (`mineConstants`); constantes definidas em outro módulo não.

<a id="warning-only-n-distinct-inputs"></a>
### Aviso: only N distinct inputs

```
Property 'few inputs' passed 100 cases.
  Warnings:
    only 2 distinct inputs in 100 passing cases: the input space is small, so a plain loop over it would be exhaustive
```

**Por quê.** A propriedade rodou 100 casos sobre muito menos entradas distintas (menos de 1 em 10 distintas). Aqui a entrada é um `bool`, que tem dois valores.

**O que fazer.** Se o espaço de entradas é mesmo tão pequeno, um loop por todos os valores é mais curto e completo:

```nim
for b in [false, true]:
  check ...
```

Se deveria ser maior, o gerador é estreito demais (`ints(0, 3)` quando você queria `ints(0, 3000)`). Se o aviso é esperado, `initSettings(suppress = {hcFewDistinct})`.

<a id="warning-cases-needed-more-than-maxchoices"></a>
### Aviso: cases needed more than maxChoices

```
Property 'too large' passed 100 cases.
  Warnings:
    440 cases needed more than maxChoices (8192) choices and were skipped: bound collection sizes (`seqs(g, maxLen = ...)`) or raise maxChoices
```

**Por quê.** Coleções aninhadas crescem rápido: uma `seq[seq[string]]` com `maxSize = 1000` produz valores com dezenas de milhares de escolhas. Esses casos foram pulados, e os 100 que passaram são os menores: as entradas grandes ficaram sem teste.

**O que fazer.** Limite os tamanhos onde importa, ou diminua `maxSize`. O mesmo formato com limites não produz aviso nem com `maxSize = 1000`:

```nim
let bounded = seqs(seqs(strings(alphanumeric, 0, 20), maxLen = 10), maxLen = 100)
forAll(initSettings(maxSize = 1000), v in bounded): ...
```

Aumente `maxChoices` só quando entradas grandes forem o objetivo, sabendo que cada caso então leva mais tempo para rodar e para reduzir.

<a id="warning-generating-inputs-takes-most-of-the-run-time"></a>
### Aviso: generating inputs takes most of the run time

**Por quê.** Mais de 80% do tempo foi gasto gerando entradas em vez de rodando a propriedade: normalmente um `filter` que rejeita a maioria dos valores, ou um gerador próprio que constrói valores grandes e joga a maioria fora.

**O que fazer.** Gere valores válidos diretamente, ou limite os tamanhos. Se a propriedade é barata e a geração é legitimamente o trabalho, `suppress = {hcSlowGeneration}`.

<a id="warning-command-never-ran"></a>
### Aviso: command never ran

```
Property 'CounterSpec' passed 100 cases.
  Warnings:
    command 'reset' never ran in 100 sequences; its precondition was false 1934 times
```

**Por quê.** Numa máquina de estado, um comando cuja pré-condição nunca é verdadeira nunca é testado. Aqui `reset` precisa de mais de 1000 incrementos, e as sequências têm no máximo 50 passos.

**O que fazer.** Torne o estado alcançável (aumente `maxSteps`, ou acrescente um comando que chegue lá mais rápido), ou afrouxe a pré-condição se o modelo permitir. As estatísticas com `PROPTEST_VERBOSITY=verbose` mostram quantas vezes cada comando rodou e quantas vezes sua pré-condição foi falsa.

<a id="warning-time-budget-reached"></a>
### Aviso: time budget reached

```
Property 'budget' passed 173 cases.
  Warnings:
    time budget of 200 ms reached after 173 of 100000 cases
```

**Por quê.** `timeBudget` (ou `PROPTEST_TIME_BUDGET`) parou a exploração antes. A propriedade passou nos casos que rodou.

**O que fazer.** Nada, se o objetivo era limitar o tempo. Se não, aumente o orçamento, diminua `cases`, ou torne a propriedade mais rápida.

<a id="other"></a>
## Outros

<a id="the-test-suite-is-slow"></a>
### A suíte de testes é lenta

Em ordem aproximada de efeito:

1. **Modo de build.** A geração num build debug é várias vezes mais lenta que em release. Se você compila os testes em release, acrescente `--stackTrace:on --lineTrace:on` para manter a localização das falhas ([por quê](#two-bugs-reported-as-one-or-location-unknown)).
2. **Menos casos localmente, mais no CI.** Mantenha o padrão no código e defina `PROPTEST_CASES` no CI.
3. **Entradas menores.** Um `maxSize` menor, ou geradores limitados, para propriedades cujo código é lento com entradas grandes.
4. **Limite o tempo.** `timeBudget` por propriedade; `deadline` para encontrar as entradas que deixam um caso lento.

Para ver para onde vai o tempo, `PROPTEST_REPORT=report.jsonl` registra `durationMs` por propriedade:

```sh
jq -r '"\(.durationMs)\t\(.name)"' report.jsonl | sort -rn | head
```

<a id="output-from-the-property-floods-the-terminal"></a>
### A saída da propriedade inunda o terminal

**Por quê.** O corpo roda uma vez por caso e uma vez por passo de shrinking: um `echo` nele imprime centenas de vezes. A biblioteca em si não imprime nada por caso na verbosidade padrão.

**O que fazer.** Remova a saída de depuração quando terminar. Para ver as entradas, use `PROPTEST_VERBOSITY=verbose`; para ver distribuições, `classify` e `label`. Um texto que deveria explicar uma falha pertence ao próprio `check`: comparações já imprimem os dois lados (`x was 500`).

<a id="a-pasted-replaycommands-block-fails-with-precondition--is-false"></a>
### Um bloco `replayCommands` colado falha com "precondition ... is false"

```
replayCommands: precondition of step 3 (pop()) is false, so this sequence cannot happen
```

**Por quê.** A sequência foi impressa por uma versão anterior da máquina de estado. O modelo ou as pré-condições mudaram, então a sequência não é mais possível.

**O que fazer.** Se a mudança foi intencional, apague o teste de regressão ou gere-o de novo a partir de uma nova execução que falhe. Se não, a mudança quebrou o modelo.

<a id="compile-errors"></a>
### Erros de compilação

| Erro | Causa | Correção |
|---|---|---|
| `type expected` em `forAll(x: int)` | o Nim interpreta argumentos `name: value` como construtor de objeto antes de o macro vê-los | escreva `forAll(x in int)` |
| `declare variables as `name in Type` or `name in generator`` | `forAll(x = ints(0, 1))` | `forAll(x in ints(0, 1))` |
| `forAll needs a body: forAll(x in int): ...` | a chamada não tem corpo, ou é usada como expressão | acrescente o corpo; para obter o resultado como valor, `let r = forAllResult(...): ...` |
| `proptest cannot generate field 'f' of P: overload `arbitrary` for its type, or for P` | um tipo de campo sem gerador (um `proc`, um ponteiro, um tipo vindo de C) | escreva `arbitrary` para o tipo desse campo, ou para `P` ([GENERATORS.md](GENERATORS.md)) |
| `proptest cannot derive T: its discriminant 'k' is a range type` | uma limitação do Nim 2.2.4 | use um enum como discriminante, ou escreva `arbitrary` para `T` |
| `example(...) needs one value per variable (N)` | um exemplo com valores de menos ou de mais | um valor por `name in source`, na ordem |
| `classify is only valid inside forAll or a stateMachine` | `classify`, `cover` ou `label` fora de uma propriedade | mova-o para dentro do corpo |
| Aviso `proptest: compiled with --panics:on` | veja [acima](#the-process-ends-with-no-report) | compile os testes com `--panics:off` |
| Aviso `proptest: built without stack traces`, ou `... without --lineTrace:on` | um build release: veja [acima](#two-bugs-reported-as-one-or-location-unknown) | `--stackTrace:on --lineTrace:on`, ou `-d:proptestTraceWarning=false` se suas propriedades falham via `check` |
