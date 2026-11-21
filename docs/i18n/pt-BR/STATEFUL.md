**Idiomas:** [English](../../STATEFUL.md) · Português (BR) · [Español](../es/STATEFUL.md) · [中文](../zh-CN/STATEFUL.md)

> Tradução de [STATEFUL.md](../../STATEFUL.md). Em caso de divergência, vale a versão em inglês.

# Tutorial de testes stateful

Alguns bugs não estão numa chamada de função, mas numa **sequência** de chamadas: uma fila que se comporta mal depois de três pushes e um pop, um cache que guarda uma entrada um milissegundo a mais, um circuit breaker que deixa passar uma sonda no momento errado. Testes baseados em exemplos só os encontram se alguém já pensou na sequência.

O teste stateful (baseado em modelo) escreve as regras uma vez, como um pequeno **modelo**, e deixa a biblioteca gerar sequências aleatórias de comandos, rodar cada uma no sistema real e no modelo, e compará-los depois de cada passo. Quando discordam, ela reduz a sequência à **menor** que ainda falha e a imprime como código Nim que você pode colar como teste de regressão.

Este tutorial constrói o exemplo de [`examples/stateful.nim`](../../../examples/stateful.nim) (compilado e executado no CI). Design: [ADR-0011](../../decisions/0011-stateful-testing.md).

## 1. O sistema: um circuit breaker

Um circuit breaker protege quem chama de uma dependência que está falhando. Depois de `threshold` falhas consecutivas ele **abre** e rejeita chamadas; depois de `openFor` milissegundos ele deixa passar uma chamada de **sonda** (meio aberto); uma sonda bem-sucedida o fecha, uma que falha o abre de novo.

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

O relógio é injetado. Código baseado em tempo só é testável quando o teste consegue mover o tempo ele mesmo, sem `sleep`.

## 2. O modelo: as regras, o mais simples possível

O modelo é um valor simples que prevê o que o sistema deveria fazer. Ele não precisa ser eficiente nem genérico, só obviamente correto:

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

## 3. A máquina: comandos, pré-condições, pós-condições

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

O que cada seção faz:

| Seção | Roda | Notas |
|---|---|---|
| `model:` | uma vez por sequência | Uma expressão; a variável `model` a guarda. Use `model: ()` quando não há modelo. |
| `setup:` | uma vez por sequência | Instruções. Suas variáveis são visíveis em todo comando. |
| `teardown:` | depois de toda sequência, mesmo uma que falha | Roda sempre que `setup` terminou. |
| `command name(x in source, ...)` | por passo | Os argumentos usam a sintaxe do `forAll`: um tipo ou um gerador. |
| `precondition:` | antes de escolher um comando | Vê o modelo. Só comandos habilitados são gerados, na exploração **e** no shrinking. |
| `run:` | o passo | Seu valor é `result` em `postcondition:`. |
| `postcondition:` | depois de `run`, **antes** de `update` | Compara `result` com o que o modelo prevê. Uma expressão única é verificada; senão, escreva linhas `check`. |
| `update:` | depois da pós-condição | Avança o modelo. |
| `invariant:` | depois de cada passo | Mesmas regras de `postcondition:`. |

O tempo é só mais um comando (`advance`). Tudo o que depende de tempo fica reproduzível e redutível.

Uma espera uniforme em `0 .. 2000` raramente seria **exatamente** 1000, que é onde mora o bug da seção 5. As constantes inteiras do arquivo de teste, aqui `const openFor = 1000`, são propostas como dicas de fronteira (999, 1000, 1001) durante a exploração ([ADR-0012](../../decisions/0012-bug-finding-power.md)). Quando a fronteira é definida em outro módulo, nomeie-a: `ms in ints(0, 2000, near = [openFor])`.

Os argumentos podem depender do modelo, por exemplo `k in elements(model.keys)` para agir sobre uma chave adicionada antes. Dê a esses comandos uma pré-condição (`model.keys.len > 0`) para que a fonte nunca seja chamada a escolher um elemento de uma lista vazia.

## 4. Rodando

```nim
suite "breaker":
  test "the breaker follows its model":
    checkStateMachine(BreakerSpec, initSettings(cases = 500))
```

Cada caso é uma sequência aleatória de até `maxSteps` comandos (padrão 50; `initSettings(maxSteps = ...)`). As sequências crescem ao longo da execução, as curtas primeiro. `stateMachineResult(BreakerSpec)` retorna o `PropertyResult` em vez de fazer o teste falhar, como `forAllResult` faz.

## 5. Lendo uma falha

Compile o exemplo com `-d:plantBug`. Esse bug só deixa passar a sonda *depois* de 1000 ms, e não *em* 1000 ms:

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

A sequência aleatória que falhou primeiro (caso 91) tinha dezenas de passos. O relatório mostra a menor: três falhas para abrir o circuito, uma espera de **exatamente** o timeout, e a chamada que deveria ter passado. Qualquer passo anterior pode ser removido e o bug desaparece; qualquer espera diferente de 1000 não o mostra. O mesmo bug também quebra a pós-condição de `fail()`, que é outra verificação, então é relatado separadamente com sua própria menor sequência.

O bloco `replayCommands` é Nim válido. Cole-o num teste e ele roda os mesmos passos, com o mesmo setup, pós-condições e invariantes, como teste de regressão permanente:

```nim
  test "probe allowed exactly at the timeout (regression)":
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
      advance(1000)
      succeed()
```

Se a pré-condição de um passo repetido for falsa, `replayCommands` lança `ValueError` nomeando esse passo, porque uma sequência assim nunca pode ser gerada.

## 6. Quando o modelo está errado

Uma falha significa que o sistema e o modelo discordam. Às vezes quem está errado é o modelo. Enquanto este exemplo era escrito, a primeira versão de `called` não contava a falha que abre o circuito, e o teste respondeu em poucos casos:

```
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
  Error: [PropertyFailed] check failed: breaker.failures == model.failures
      breaker.failures was 3
      model.failures was 2
```

Três passos bastam para ver qual regra está errada. Decida qual lado bate com a especificação, e corrija esse lado.

## 7. Dicas

- **Mantenha o modelo bobo.** Uma lista em vez de um buffer circular, um contador em vez de uma janela deslizante. Se o modelo é tão complexo quanto o sistema, os dois podem ter o mesmo bug.
- **Nomeie as fronteiras que o arquivo não mostra.** As constantes do arquivo de teste são mineradas automaticamente; para uma definida em outro lugar, use `ints(lo, hi, near = [...])`. O shrinking não é afetado.
- **Verifique o que foi exercitado.** Com `PROPTEST_VERBOSITY=verbose`, uma máquina que passa imprime quantas vezes cada comando rodou, quantas vezes sua pré-condição o bloqueou, e os comprimentos das sequências. Um comando que nunca rodou é sempre relatado como aviso. `cover(20.0, model.state == Open, "reached Open")` dentro de um `update:` faz o teste falhar quando menos de 20% das sequências chegam a esse estado.
- **O swarm testing está ligado.** Metade das sequências deixa alguns comandos de fora, então longas sequências dos outros (muitos incrementos sem reset) ficam prováveis. `initSettings(swarm = false)` o desliga.
- **Verifique o que o usuário observa**: valores retornados nas pós-condições, estado visível nos invariantes. Não verifique campos privados.
- **Erros esperados são valores.** Se o sistema lança exceção numa chamada rejeitada, capture-a dentro de `run:` e retorne algo que o modelo prevê (`"rejected"`). Qualquer exceção que escapa de `run:` é uma falha.
- **Um exemplo real**: [`nim-circuit-breaker`](https://github.com/kaio-souza/nim-circuit-break) testa seu breaker assim (`tests/t_model.nim`), com backoff, `successThreshold` e seu `FakeClock`, em 1000 sequências.

## Limites

- Estados que exigem um caminho longo e específico (cinco reaberturas seguidas de um breaker, cada uma após a espera certa) continuam raramente alcançados por sequências aleatórias. Se o modelo consegue medir o progresso, dê a ele uma pontuação com `target(float(model.reopenings), "reopenings")` em `invariant:`: depois de metade dos casos, o motor estende a melhor sequência até ali (no limite de backoff do breaker, 3 → 20 de 100 seeds; [ADR-0016](../../decisions/0016-targeted-exploration.md)). Para um caminho que você já conhece, escreva-o como teste de regressão `replayCommands`, ou restrinja os comandos de uma máquina dedicada.
- Os comandos rodam um depois do outro, numa única thread.
- Os valores dos argumentos são impressos com `showCode`, que produz literais Nim para os tipos nativos. Para um tipo de argumento próprio, sobrecarregue `showCode` para que o bloco impresso compile.
- `stateMachine` precisa ser usado no nível do módulo. Os nomes gerados (`BreakerSpec`, `BreakerSpecStep`, os construtores dos comandos) são exportados, então uma máquina pode ficar no seu próprio módulo.
