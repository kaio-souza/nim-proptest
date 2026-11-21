**Idiomas:** [English](../../CONFIGURATION.md) · Português (BR) · [Español](../es/CONFIGURATION.md) · [中文](../zh-CN/CONFIGURATION.md)

> Tradução de [CONFIGURATION.md](../../CONFIGURATION.md). Em caso de divergência, vale a versão em inglês.

# Referência de configuração

Toda configuração, variável de ambiente e opção de compilação, com seu padrão, seu custo e quando mudá-la. Problemas e suas soluções: [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

- [Receitas](#recipes): copie uma e adapte
- [Como um valor é escolhido](#how-a-value-is-chosen): configuração explícita, ambiente, padrão
- [Configurações](#settings), agrupadas pelo que controlam
- [Variáveis de ambiente](#environment-variables)
- [Opções de compilação](#compile-time-options): modo de build, `--panics`, stack traces
- [Arquivos que a biblioteca grava](#files-the-library-writes)
- [O que uma repetição precisa](#what-a-replay-needs)

<a id="recipes"></a>
## Receitas

**No dia a dia, nada a configurar.** 100 casos por propriedade, shrinking ligado, falhas salvas e repetidas primeiro na execução seguinte. A maioria das propriedades nunca precisa de configuração.

```nim
forAll(xs in seq[int]):
  check xs.sorted.sorted == xs.sorted
```

**Mais casos no CI do que na sua máquina.** Use o ambiente, não o código, para que as execuções locais continuem rápidas:

```sh
PROPTEST_CASES=1000 PROPTEST_HANG_TIMEOUT=60000 PROPTEST_REPORT=proptest-report.jsonl nimble test
```

`PROPTEST_HANG_TIMEOUT` liga o watchdog: um caso que nunca retorna encerra a execução com um relatório, em vez de rodar até o limite de tempo do job de CI.

Uma propriedade que define `cases` ela mesma ignora `PROPTEST_CASES` (veja a [precedência](#how-a-value-is-chosen)): deixe `cases` de fora das propriedades que você quer que o CI escale.

**Uma execução noturna profunda.** Muito mais casos, limitados por tempo para que uma propriedade lenta não ocupe a noite toda:

```sh
PROPTEST_CASES=100000 PROPTEST_TIME_BUDGET=60000 PROPTEST_HANG_TIMEOUT=60000 PROPTEST_VERBOSITY=quiet nimble test
```

`timeBudget` vale por propriedade: cada uma para depois de 60 s com um aviso dizendo quantos casos rodaram.

**Repetir uma falha.** Copie a linha `Replay:` do relatório. Mesmo binário, mesmo ambiente de resto:

```sh
PROPTEST_SEED=17542877672211577899 ./tests/t_sorting
```

**Ver o que uma propriedade gera.** As entradas de cada caso, e todas as estatísticas:

```sh
PROPTEST_VERBOSITY=verbose PROPTEST_CASES=20 ./tests/t_sorting
```

**Uma propriedade cara.** Menos casos, maiores, e um limite de tempo por caso:

```nim
forAll(initSettings(cases = 30, maxSize = 300, deadline = 2000), doc in Document):
  check parse(render(doc)) == doc
```

**Uma propriedade que precisa ver sempre as mesmas entradas** (um exemplo na documentação, um teste da própria biblioteca): fixe a seed. Ela passa a ignorar `PROPTEST_SEED`.

```nim
forAll(initSettings(seed = 42), x in int): ...
```

**As mesmas configurações para muitas propriedades.** `Settings` é um objeto simples; construa-o uma vez:

```nim
let heavy = initSettings(cases = 50, maxSize = 500, deadline = 1000)

test "round trip":
  forAll(heavy, doc in Document):
    check parse(render(doc)) == doc

test "rendering is stable":
  forAll(heavy, doc in Document):
    check render(doc) == render(parse(render(doc)))
```

Cada propriedade continua recebendo sua própria seed (derivada do seu nome `file:line`), então compartilhar configurações não faz duas propriedades sortearem os mesmos valores. Por isso, deixe `name` vazio em configurações compartilhadas.

<a id="how-a-value-is-chosen"></a>
## Como um valor é escolhido

Para cada configuração, vale o primeiro que se aplica:

1. **O argumento** passado a `initSettings(...)`.
2. **A variável de ambiente**, para as configurações que têm uma (lida quando `initSettings` roda).
3. **O padrão embutido.**

```nim
# PROPTEST_CASES=1000 in the environment:
forAll(x in int): ...                          # 1000 cases: environment
forAll(initSettings(cases = 20), x in int): ... # 20 cases: argument
```

A seed segue a mesma ordem: `seed` nas configurações, depois `PROPTEST_SEED`, depois uma seed aleatória escolhida uma vez por processo. Essa **seed da execução** não é usada diretamente: cada propriedade deriva sua própria seed dela e do seu `name`, então uma única `PROPTEST_SEED` repete todas as propriedades do programa, e as propriedades não compartilham fluxos aleatórios.

Uma variável de ambiente que não pode ser interpretada é um erro, não um padrão silencioso: `PROPTEST_CASES=abc` lança `ValueError: PROPTEST_CASES is not an integer: abc` na primeira propriedade. Configurações inválidas (`cases = 0`, `edgeBias = 2.0`) lançam `ValueError: invalid proptest settings: ...` antes de qualquer caso rodar.

<a id="settings"></a>
## Configurações

Passe-as a `initSettings(...)` entre os argumentos de `forAll`, `forAllResult` ou `checkStateMachine`. Em máquinas de estado, **um caso é uma sequência inteira** de comandos.

<a id="how-much-to-test"></a>
### Quanto testar

| Configuração | Padrão | Ambiente | Válido |
|---|---|---|---|
| `cases` | 100 | `PROPTEST_CASES` | >= 1 |
| `maxSize` | 100 | | >= 0 |
| `maxSteps` | 50 | | >= 1 |
| `maxDepth` | 5 | | >= 0 |
| `maxChoices` | 8192 | | >= 1 |

**`cases`**: casos explorados, passando ou falhando. O custo cresce linearmente; a chance de atingir um bug que exige uma entrada rara também cresce, mas devagar: um bug atingido por 1 entrada em 1000 é encontrado por 100 casos em cerca de 1 execução em 10, e por 1000 casos em cerca de 2 execuções em 3. Aumente no CI, não no código. **Mudá-lo muda as entradas** de todos os casos (os tamanhos crescem ao longo da execução, veja `maxSize`), então uma seed só se repete com o mesmo `cases`.

**`maxSize`**: o quão grandes os valores ficam. Os tamanhos crescem de 0 no primeiro caso até `maxSize` no último, então os primeiros casos são pequenos e simples. Casos descartados também avançam o tamanho, então uma propriedade que descarta entradas pequenas (`assume(xs.len > 30)`) ainda chega às maiores. Dentro de um gerador, `sized` lê o tamanho atual e `resize` o fixa ([GENERATORS.md](GENERATORS.md)). Medido em `seq[int]` com 100 casos:

| `maxSize` | comprimento médio | mais longo |
|---|---|---|
| 10 | 3 | 16 |
| 100 (padrão) | 40 | 154 |
| 1000 | 416 | 1927 |

Aumente quando um bug precisa de entradas longas (um buffer que enche com 256 elementos); diminua quando o código testado é lento com entradas grandes. Coleções aninhadas são mais curtas que as do nível de cima. Valores maiores também levam mais tempo para reduzir, mas o shrinking sempre termina em um mínimo. Limites de tamanho de um gerador ficam melhor no próprio gerador: `seqs(ints(), maxLen = 10)`.

**`maxSteps`** (máquinas de estado): a maior sequência de comandos. A maioria dos bugs precisa de poucos passos, e o swarm testing (abaixo) torna prováveis longas sequências de um mesmo comando dentro de 50. Aumente para bugs que exigem muitos passos (um contador que estoura depois de 300 incrementos); o custo por sequência cresce junto.

**`maxDepth`**: a profundidade dos dados recursivos durante a exploração (árvores, objetos `ref` que apontam para o próprio tipo, `seq` aninhada). Mais fundo significa casos maiores e mais lentos. 0 dá o valor mais simples de um tipo recursivo (uma ref `nil`, uma lista de filhos vazia).

**`maxChoices`**: escolhas aleatórias que um caso pode usar (um `int` é uma escolha, uma `seq` é mais ou menos uma por elemento, mais seus elementos). Um caso que precisa de mais é pulado e contado como "too large", o que impede um gerador descontrolado de esgotar a memória. Quando o [health check](TROUBLESHOOTING.md#warning-cases-needed-more-than-maxchoices) disser que muitos casos foram pulados, limite primeiro os tamanhos do gerador; aumente `maxChoices` só se casos grandes forem o objetivo.

<a id="shrinking"></a>
### Shrinking

| Configuração | Padrão | Ambiente | Válido |
|---|---|---|---|
| `maxShrinks` | 2000 | `PROPTEST_MAX_SHRINKS` | >= 0 |
| `shrinkTimeBudget` | 0 (nenhum) | | >= 0 ms |
| `maxFailures` | 3 | | >= 1 |

**`maxShrinks`**: execuções da propriedade gastas reduzindo cada falha. Os bugs de referência da biblioteca são reduzidos ao mínimo exato em 9 a 236 execuções, então 2000 é generoso; o orçamento importa quando uma execução é lenta. 0 relata o primeiro caso que falhou como foi encontrado, sem redução.

**`shrinkTimeBudget`**: um limite de tempo por falha, para propriedades lentas. Quando ele é atingido, o relatório diz "Shrinking stopped at its time budget" e mostra o menor contraexemplo até ali: válido, talvez não mínimo.

**`maxFailures`**: falhas distintas (tipo de exceção ou local diferentes) mantidas e reduzidas. A exploração continua depois da primeira falha para encontrar outras, e para quando esse número é conhecido. 1 para no primeiro bug, o que é mais rápido mas esconde um segundo bug até o primeiro ser corrigido.

<a id="finding-bugs"></a>
### Encontrando bugs

| Configuração | Padrão | Ambiente | Válido |
|---|---|---|---|
| `edgeBias` | 0.25 | | 0.0 .. 1.0 |
| `mineConstants` | true | | |
| `swarm` | true | | |
| `maxDiscardRatio` | 10 | | >= 0 |

**`edgeBias`**: a fração de sorteios que propõe um valor de borda em vez de um uniforme: 0, 1, -1 e os limites do tipo para inteiros; -0.0, NaN, infinitos e subnormais para floats; coleções vazias e de um elemento. Os bugs se concentram ali. 0.0 dá apenas valores uniformes; valores maiores testam mais as bordas e menos os valores típicos. Mudá-lo muda as entradas de todos os casos.

**`mineConstants`**: literais inteiros e constantes no corpo da propriedade (e, com menos sorteios, em todo o arquivo de teste) são propostos como `v - 1`, `v`, `v + 1`. É assim que `x == 1000` é encontrado em `0 .. 2000`. Também significa que uma propriedade que menciona `997` vê 996 a 998 mais vezes do que o acaso: normalmente o que você quer. Desligue para medir o comportamento aleatório puro. Para uma fronteira definida em outro módulo, use `ints(lo, hi, near = [v])`.

**`swarm`** (máquinas de estado): metade das sequências deixa de fora um subconjunto aleatório de comandos, então longas sequências dos que sobram ficam prováveis ("12 incrementos sem reset": encontrado em 3 de 100 seeds sem swarm, 97 com ele). A outra metade usa todos os comandos. Desligue só para comparar.

**`maxDiscardRatio`**: uma propriedade desiste depois de `cases × maxDiscardRatio` casos descartados (por `assume`, por `filter`, ou grandes demais). Aumentá-lo esconde o problema; gerar valores válidos diretamente o resolve ([gave up](TROUBLESHOOTING.md#gave-up-after-n-passing-cases)).

<a id="time"></a>
### Tempo

| Configuração | Padrão | Ambiente | Válido |
|---|---|---|---|
| `deadline` | 0 (desligado) | `PROPTEST_DEADLINE` | >= 0 ms |
| `timeBudget` | 0 (nenhum) | `PROPTEST_TIME_BUDGET` | >= 0 ms |
| `hangTimeout` | 0 (desligado) | `PROPTEST_HANG_TIMEOUT` | >= 0 ms; 0 é desligado |

**`deadline`**: um caso que demora mais falha com `DeadlineExceeded` e é reduzido como qualquer falha: à menor entrada que continua lenta. Use para encontrar degraus de desempenho (comportamento quadrático em alguma entrada). Durante a exploração, um caso tem 1,25 × o deadline, para que um que passe só um pouco não vire um relatório flaky. Contrapartida: os tempos variam entre máquinas e sob carga, então defina-o bem acima do tempo normal dos casos, especialmente no CI. Ele não para um caso que nunca retorna: isso é com `hangTimeout`.

**`timeBudget`**: um limite de tempo para a exploração, por propriedade. Quando é atingido, a propriedade para e relata o que fez: uma propriedade que passou diz "time budget of N ms reached after K of M cases" como aviso. Mantém o tempo do CI limitado, ao custo de menos casos em máquinas lentas.

**`hangTimeout`**: um caso que não retornou depois desse tempo (um loop infinito, um deadlock) é relatado por uma thread watchdog, que então **encerra o processo** com código de saída 1: um caso em execução não pode ser interrompido com segurança, então não há como continuar a execução. O relatório diz a propriedade, o que estava rodando (explorando, reduzindo, um caso salvo), as escolhas do caso e o comando de repetição; o caso é salvo no banco de falhas, então a próxima execução o repete primeiro e imprime suas entradas. Uma linha `hung` é anexada ao relatório JSON. **Desligado por padrão**, para que depurar um caso passo a passo ou uma propriedade legitimamente lenta nunca encerre o processo de surpresa. Ligue onde um travamento custa mais caro, no CI, bem acima do seu caso normal mais lento: `PROPTEST_HANG_TIMEOUT=60000`. Sem ele, um caso que nunca retorna trava a execução até ser interrompido ([e então](TROUBLESHOOTING.md#the-test-hangs)). O watchdog precisa de `--threads:on` (o padrão do Nim 2) e vigia uma propriedade por vez: propriedades rodando em paralelo em outras threads não são vigiadas. [O que fazer quando ele dispara](TROUBLESHOOTING.md#the-test-hangs).

<a id="output"></a>
### Saída

| Configuração | Padrão | Ambiente | Valores |
|---|---|---|---|
| `verbosity` | `vNormal` | `PROPTEST_VERBOSITY` | `quiet`, `normal`, `verbose`, `debug` |
| `report` | vazio (nenhum) | `PROPTEST_REPORT` | um caminho de arquivo |
| `suppress` | `{}` | | `hcLargeData`, `hcFewDistinct`, `hcSlowGeneration` |

**`verbosity`**:

| Nível | Imprime |
|---|---|
| `quiet` | só as falhas |
| `normal` | também os avisos, e as estatísticas das propriedades que usam `classify`, `cover` ou `label` |
| `verbose` | também uma linha por caso com suas entradas, e todas as estatísticas (contagem de comandos stateful, comprimentos de sequência) |
| `debug` | também cada passo de shrinking aceito |

No ambiente, os nomes não têm o prefixo `v` (`PROPTEST_VERBOSITY=verbose`); no código têm (`verbosity = vVerbose`).

**`report`**: um arquivo [JSON Lines](https://jsonlines.org) ao qual o resultado de cada propriedade é anexado, para ferramentas de CI. O arquivo e seu diretório são criados; vários programas de teste podem compartilhar um arquivo. Um caminho que não pode ser gravado lança `IOError` com o caminho. Campos: veja o [README](README.md#json-report-for-ci). Exemplo: listar as falhas e como repeti-las.

```sh
jq -r 'select(.passed | not) | "\(.name): \(.status) — \(.replay)"' proptest-report.jsonl
```

**`suppress`**: health checks a não rodar nesta propriedade. Prefira corrigir o que o check aponta; suprima quando o aviso é esperado (uma propriedade sobre `bool` tem mesmo só duas entradas).

<a id="identity-and-reproduction"></a>
### Identidade e reprodução

| Configuração | Padrão | Ambiente |
|---|---|---|
| `seed` | aleatória | `PROPTEST_SEED` |
| `name` | `file:line` | |

**`seed`**: fixa a seed da execução para esta propriedade; ela passa a ignorar `PROPTEST_SEED`. Bom para documentação e para os testes da própria biblioteca; ruim para testes comuns, que explorariam as mesmas 100 entradas para sempre.

**`name`**: aparece nos relatórios, e é usado para duas coisas:

- **A seed da propriedade** é derivada da seed da execução e do nome. Com o nome padrão (`file:line`), acrescentar uma linha acima de uma propriedade muda suas entradas para a mesma `PROPTEST_SEED`. Uma seed impressa em um relatório repete o binário que a imprimiu; depois de editar o arquivo, confie no banco de falhas.
- **A chave no banco de falhas.** Sem nome, a chave é um hash do código da propriedade, então editar a propriedade esquece suas falhas salvas (elas podem não fazer mais sentido). Com nome, as falhas salvas sobrevivem a edições; as que não cabem mais nos geradores são descartadas.

Dê um nome às propriedades que você referencia em outros lugares (um bug tracker, um painel de CI): ele continua estável quando as linhas mudam de lugar.

<a id="environment-variables"></a>
## Variáveis de ambiente

| Variável | Define | Formato | Uso típico |
|---|---|---|---|
| `PROPTEST_SEED` | seed da execução | inteiro sem sinal de 64 bits | repetir uma falha |
| `PROPTEST_CASES` | `cases` padrão | inteiro | mais casos no CI |
| `PROPTEST_MAX_SHRINKS` | `maxShrinks` padrão | inteiro | propriedades lentas no CI |
| `PROPTEST_DEADLINE` | `deadline` padrão | inteiro, ms | pegar casos lentos no CI |
| `PROPTEST_TIME_BUDGET` | `timeBudget` padrão | inteiro, ms | limitar execuções noturnas |
| `PROPTEST_HANG_TIMEOUT` | `hangTimeout` padrão | inteiro, ms; 0 (padrão) é desligado | ligar o watchdog no CI: um travamento falha com relatório |
| `PROPTEST_VERBOSITY` | `verbosity` padrão | `quiet`, `normal`, `verbose`, `debug` | olhar as entradas geradas |
| `PROPTEST_REPORT` | `report` padrão | caminho de arquivo | JSON para ferramentas de CI |
| `PROPTEST_DB` | diretório dos arquivos locais | caminho, ou `off` | mover ou desligar `.proptest/` |

Configurações sem variável (`maxSize`, `edgeBias`, ...) mudam o que uma propriedade testa, e não quanto tempo ela roda, então é melhor mantê-las no código, onde quem lê as vê. Para defini-las para uma suíte inteira, compartilhe um valor `Settings` ([receita](#recipes)).

<a id="compile-time-options"></a>
## Opções de compilação

**Modo de build e stack traces.** As falhas são diferenciadas pelo tipo da exceção e pela linha do seu código onde foram lançadas. Essa linha vem do stack trace, que `-d:release` e `-d:danger` desligam:

| Build | Falhas de `check` | `doAssert`, `raise`, erros de índice | Verificação de overflow e índice |
|---|---|---|---|
| debug (padrão) | localizadas | localizadas | ligada |
| `-d:release` | localizadas | só o tipo | ligada |
| `-d:release --stackTrace:on` | localizadas | só o arquivo (`t_sort.nim:0`) | ligada |
| `-d:release --stackTrace:on --lineTrace:on` | localizadas | localizadas | ligada |
| `-d:danger` | localizadas | só o tipo | **desligada** |

Sem localização, dois bugs diferentes que lançam o mesmo tipo de exceção parecem um só, e o relatório diz "Location unknown (no stack trace)". Prefira builds debug para testes de propriedade, ou acrescente `--stackTrace:on --lineTrace:on` a um build release (os dois: o stack trace sozinho não tem números de linha). A biblioteca avisa em tempo de compilação quando algum deles falta:

```
Warning: proptest: built without stack traces (-d:release and -d:danger turn them off). Failures other than `check` are then told apart by exception type only: two bugs that raise the same type are reported as one. Build tests with --stackTrace:on --lineTrace:on, or silence this with -d:proptestTraceWarning=false.
```

**`-d:proptestTraceWarning=false`.** Silencia esse aviso, para uma suíte que compila em release de propósito e cujas propriedades falham via `check` (localizado em qualquer build). Evite `-d:danger`: com as verificações desligadas, um índice fora dos limites é comportamento indefinido em vez de uma falha que a biblioteca pode capturar e reduzir.

**`--panics:on`.** Defects (`IndexDefect`, `AssertionDefect`, ...) encerram o processo na hora, então o caso que falha não pode ser reduzido. A biblioteca avisa em tempo de compilação. Compile os testes com o padrão `--panics:off`; se precisar mantê-lo ligado, a seed da execução já está em `.proptest/last-run` para repetir o crash.

**`-d:proptestDb=<dir>` ou `-d:proptestDb=off`.** O padrão compilado de `PROPTEST_DB`, para um binário de teste que nunca deve gravar arquivos (a variável ainda o sobrescreve).

**Gerenciamento de memória e threads.** `--mm:orc` (padrão) e `--mm:arc`, com threads ligadas ou desligadas, são todos testados no CI em Linux, macOS e Windows.

<a id="files-the-library-writes"></a>
## Arquivos que a biblioteca grava

Todos sob `PROPTEST_DB` (padrão `.proptest`, relativo ao diretório de trabalho). Adicione-o ao `.gitignore`.

| Arquivo | Gravado | Para quê |
|---|---|---|
| `last-run` | antes do primeiro caso de cada execução | a seed da execução e o comando: repete uma execução que deu crash ou travou |
| `db/<hash>.txt` | depois de uma propriedade que falhou | casos mínimos que falham, repetidos primeiro nas próximas execuções; esquecidos depois de 3 execuções seguidas passando |

Erros de gravação são ignorados: um diretório somente leitura nunca faz um teste falhar. `PROPTEST_DB=off` não grava nada.

**Contrapartida do banco de falhas.** Um bug que você acabou de ver é tentado primeiro, então uma correção é verificada na hora, sem esperar a exploração aleatória encontrá-lo de novo. O custo: duas execuções do mesmo binário com a mesma seed podem diferir, porque a segunda também repete falhas salvas. Use `PROPTEST_DB=off` quando precisar de execuções idênticas (benchmarks, comparar seeds). No CI o diretório começa vazio, a menos que você faça cache dele; fazer cache leva falhas de uma execução de CI para a seguinte.

<a id="what-a-replay-needs"></a>
## O que uma repetição precisa

`PROPTEST_SEED=<n>` reproduz uma execução exatamente quando todo o resto que decide as entradas é igual:

- o mesmo teste compilado (mesmo código, logo os mesmos nomes de propriedade e as mesmas constantes mineradas dele);
- as mesmas configurações que moldam as entradas: `cases`, `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm`, `mineConstants`, inclusive `PROPTEST_CASES`;
- uma propriedade determinística: sem relógio, estado global, threads ou I/O que mudem seu resultado. Caso contrário, o relatório diz FLAKY.

O gerador aleatório e o hash da biblioteca são próprios e fixos (testados contra vetores de referência em todas as plataformas), então a mesma seed dá os mesmos valores em Linux, macOS e Windows, em debug e release. Os valores gerados para uma seed só mudam entre versões da biblioteca com uma entrada no CHANGELOG em **Generation changes**.
