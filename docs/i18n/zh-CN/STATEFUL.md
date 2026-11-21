**语言：** [English](../../STATEFUL.md) · [Português (BR)](../pt-BR/STATEFUL.md) · [Español](../es/STATEFUL.md) · 中文

> 本文译自 [STATEFUL.md](../../STATEFUL.md)。如有出入，以英文版为准。

# 有状态测试教程

有些 bug 不在某一次函数调用里，而在一**系列**调用中：一个在三次 push 和一次 pop 后行为异常的队列，一个多保留了一毫秒条目的缓存，一个在错误时刻放行探测请求的熔断器。基于示例的测试只有在有人事先想到这个序列时才能发现它们。

有状态（基于模型）测试把规则一次性写成一个小**模型**，然后让库生成随机命令序列，把每个序列分别在真实系统和模型上运行，并在每一步之后比较两者。当它们不一致时，库会把序列收缩到仍然失败的**最短**序列，并打印成可以粘贴为回归测试的 Nim 代码。

本教程构建 [`examples/stateful.nim`](../../../examples/stateful.nim) 中的示例（在 CI 中编译运行）。设计：[ADR-0011](../../decisions/0011-stateful-testing.md)。

## 1. 系统：熔断器

熔断器保护调用方免受故障依赖的影响。连续 `threshold` 次失败后它会**打开**并拒绝调用；`openFor` 毫秒后它会放行一次**探测**调用（半开）；探测成功则关闭，失败则再次打开。

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

时钟是注入的。只有当测试能自己推进时间、而不用 `sleep` 时，基于时间的代码才可测试。

## 2. 模型：规则，越简单越好

模型是一个普通的值，用来预测系统应当做什么。它不需要高效或通用，只需要显然正确：

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

## 3. 状态机：命令、前置条件、后置条件

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

各部分的作用：

| 部分 | 运行时机 | 说明 |
|---|---|---|
| `model:` | 每个序列一次 | 一个表达式；变量 `model` 保存它。没有模型时用 `model: ()`。 |
| `setup:` | 每个序列一次 | 语句。其中的变量在所有命令中可见。 |
| `teardown:` | 每个序列之后，即使序列失败 | 只要 `setup` 已完成就会运行。 |
| `command name(x in source, ...)` | 每一步 | 参数使用 `forAll` 语法：类型或生成器。 |
| `precondition:` | 选择命令之前 | 能看到模型。只会生成已启用的命令，在探索**和**收缩时都是如此。 |
| `run:` | 这一步本身 | 其值在 `postcondition:` 中为 `result`。 |
| `postcondition:` | `run` 之后、`update` **之前** | 把 `result` 与模型的预测相比较。单个表达式会被检查；否则写 `check` 行。 |
| `update:` | 后置条件之后 | 推进模型。 |
| `invariant:` | 每一步之后 | 规则与 `postcondition:` 相同。 |

时间只是另一个命令（`advance`）。一切与时间相关的东西都变得可复现、可收缩。

在 `0 .. 2000` 中均匀抽取的等待时间很少会**恰好**是 1000，而第 5 节的 bug 正好在那里。测试文件中的整数常量（这里是 `const openFor = 1000`）会在探索期间被作为边界提示（999、1000、1001）提出（[ADR-0012](../../decisions/0012-bug-finding-power.md)）。当边界定义在另一个模块中时，显式指出它：`ms in ints(0, 2000, near = [openFor])`。

参数可以依赖模型，例如用 `k in elements(model.keys)` 来操作之前添加的某个键。给这类命令加上前置条件（`model.keys.len > 0`），这样就永远不会要求选择源从空列表中取元素。

## 4. 运行

```nim
suite "breaker":
  test "the breaker follows its model":
    checkStateMachine(BreakerSpec, initSettings(cases = 500))
```

每个用例是一个最多 `maxSteps` 个命令的随机序列（默认 50；`initSettings(maxSteps = ...)`）。序列在运行过程中逐渐变长，先短后长。`stateMachineResult(BreakerSpec)` 会返回 `PropertyResult` 而不是让测试失败，就像 `forAllResult` 那样。

## 5. 阅读一次失败

用 `-d:plantBug` 构建该示例。这个 bug 让探测只在 1000 毫秒*之后*放行，而不是*在* 1000 毫秒时：

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

最初失败的那个随机序列（第 91 个用例）有几十步。报告显示的是最短的那个：三次失败让电路打开，一次**恰好**等于超时的等待，以及本应被放行的那次调用。去掉任何前面的步骤，bug 就会消失；任何不等于 1000 的等待都不会暴露它。同一个 bug 也破坏了 `fail()` 的后置条件，这是另一个检查，所以会以它自己的最短序列被单独报告。

`replayCommands` 块是合法的 Nim 代码。把它粘贴进一个测试，它就会以相同的 setup、后置条件和不变量运行相同的步骤，成为永久的回归测试：

```nim
  test "probe allowed exactly at the timeout (regression)":
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
      advance(1000)
      succeed()
```

如果重放的某一步的前置条件为假，`replayCommands` 会抛出指明该步骤的 `ValueError`，因为这样的序列永远不可能被生成。

## 6. 当模型出错时

失败意味着系统和模型不一致。有时出错的是模型。编写这个示例时，`called` 的第一个版本没有计入让电路打开的那次失败，测试在几个用例内就给出了答案：

```
    replayCommands BreakerSpec:
      fail()
      fail()
      fail()
  Error: [PropertyFailed] check failed: breaker.failures == model.failures
      breaker.failures was 3
      model.failures was 2
```

三步就足以看出哪条规则不对。判断哪一方符合规格，然后修正另一方。

## 7. 提示

- **让模型保持简单。** 用列表代替环形缓冲区，用计数器代替滑动窗口。如果模型和系统一样复杂，两者可能会有同一个 bug。
- **给文件里看不到的边界起名字。** 测试文件中的常量会被自动挖掘；对于定义在别处的常量，用 `ints(lo, hi, near = [...])`。收缩不受影响。
- **检查哪些东西被执行到了。** 使用 `PROPTEST_VERBOSITY=verbose` 时，通过的状态机会打印每个命令运行了多少次、被其前置条件阻止了多少次，以及序列长度。从未运行过的命令总会以警告形式报告。在 `update:` 中写 `cover(20.0, model.state == Open, "reached Open")`，当到达该状态的序列少于 20% 时测试就会失败。
- **swarm testing 默认开启。** 一半的序列会省略部分命令，于是其余命令的长串连续执行（多次递增且没有重置）变得很可能。`initSettings(swarm = false)` 可将其关闭。
- **检查用户能观察到的东西**：后置条件中的返回值，不变量中的可见状态。不要检查私有字段。
- **预期内的错误是值。** 如果系统在拒绝调用时抛出异常，就在 `run:` 内捕获它，并返回模型能预测的东西（`"rejected"`）。任何从 `run:` 中逃逸的异常都是失败。
- **一个真实例子**：[`nim-circuit-breaker`](https://github.com/kaio-souza/nim-circuit-breaker) 就是这样测试它的熔断器的（`tests/t_model.nim`），包括退避、`successThreshold` 和它的 `FakeClock`，共 1000 个序列。

## 限制

- 需要一条又长又特定的路径才能到达的状态（熔断器连续五次重新打开，每次都在恰当的等待之后）依然很少被随机序列触达。如果模型能度量进展，就在 `invariant:` 中用 `target(float(model.reopenings), "reopenings")` 给它一个分数：完成一半用例之后，引擎会扩展目前最好的序列（在熔断器的退避上限上，100 个种子中从 3 次提升到 20 次；[ADR-0016](../../decisions/0016-targeted-exploration.md)）。对于你已经知道的路径，把它写成 `replayCommands` 回归测试，或者在一个专门的状态机中缩小命令范围。
- 命令在单个线程上依次运行。
- 参数值用 `showCode` 打印，它为内置类型生成 Nim 字面量。对于自定义参数类型，重载 `showCode`，让打印出的代码块能够编译。
- `stateMachine` 必须在模块顶层使用。生成的名称（`BreakerSpec`、`BreakerSpecStep`、命令构造器）都会被导出，所以状态机可以放在它自己的模块中。
