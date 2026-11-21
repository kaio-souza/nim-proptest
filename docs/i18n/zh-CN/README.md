**语言：** [English](../../../README.md) · [Português (BR)](../pt-BR/README.md) · [Español](../es/README.md) · 中文

> 本文译自[英文 README](../../../README.md)。如有出入，以英文版为准。

# proptest

一个**面向 [Nim](https://nim-lang.org) 编程语言的基于属性的测试库**，以 Nimble 包的形式发布。写下一条规则，让库生成输入，然后得到能打破这条规则的**最小**输入。

> 支持针对内置类型和**你自己的对象（无需编写生成器代码）**的属性，以及有状态（基于模型）的测试，具备自动收缩（shrinking）、下次运行优先重放上次失败、覆盖率统计，以及主动寻找边界值的探索。1.0 版本：API 以及同一种子生成的值遵循[稳定性策略](STABILITY.md)。参见[功能列表](#features)。

## 安装

```sh
nimble install https://github.com/kaio-souza/nim-proptest
```

或者从克隆的仓库：`nimble install`（若要在其上开发，用 `nimble develop`）。需要 Nim >= 2.2.4；除标准库外没有任何依赖。

## 快速上手

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

第二个属性是错的，报告会给出**最小**反例（100，而不是某个随机的大偶数）以及重放方法：

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

可运行的版本：[`examples/quickstart.nim`](../../../examples/quickstart.nim)（含故意埋入的 bug）、[`examples/tour.nim`](../../../examples/tour.nim)（下文所有功能）、[`examples/generators.nim`](../../../examples/generators.nim)（生成器指南）、[`examples/patterns.nim`](../../../examples/patterns.nim)（模式手册）和 [`examples/stateful.nim`](../../../examples/stateful.nim)（有状态测试教程）；均在 CI 中编译并运行。

## 编写属性

### 变量：`name in source`

每个变量要么是一个**类型**（自动推断生成器），要么是一个**生成器值**：

```nim
forAll(xs in seq[int], s in string, flag in bool): ...     # types
forAll(n in ints(0, 100), word in strings("abc", 1, 5)): ... # generator values
```

每个属性的来源只求值一次。`forAll(x: int)` 行不通：如果一个调用的所有参数看起来都是 `name: value`，Nim 会在任何宏运行之前把它解析成对象构造。

### 断言

在 `forAll` 内部，`check` 和 `require` 会被改写，使失败的用例被静默捕获，只报告最终收缩后的失败（且只报告一次）。`doAssert`、任何抛出的异常以及 `Defect`（索引错误、溢出等）也都算作失败。

### 丢弃用例：`assume`

```nim
forAll(a in ints(-1000, 1000), b in ints(-1000, 1000)):
  assume(b != 0)
  check a mod b == a - (a div b) * b
```

丢弃的用例过多会以 "gave up" 报告结束运行。与其用 `assume` 和 `filter`，不如直接生成有效值。

### 设置

在参数中传入一个 `initSettings(...)` 值。大多数属性不需要任何设置。下面的表格只是概要；[CONFIGURATION.md](CONFIGURATION.md) 提供了配方（CI、夜间运行、重放、慢属性）、每项设置的代价，以及种子要重放成功哪些设置必须一致。

```nim
forAll(initSettings(cases = 500, maxShrinks = 5_000), x in int8): ...
```

| 设置 | 默认值 | 含义 |
|---|---|---|
| `cases` | 100 | 要运行的用例数 |
| `maxSteps` | 50 | 有状态测试：每个序列的命令数 |
| `maxDepth` | 5 | 探索时递归数据的嵌套深度 |
| `maxShrinks` | 2000 | 收缩每个失败的执行预算 |
| `maxSize` | 100 | 最后一个用例达到的规模（限制集合的典型长度） |
| `maxDiscardRatio` | 10 | 丢弃 `cases × ratio` 个用例后放弃 |
| `maxFailures` | 3 | 每个属性报告的不同失败数 |
| `maxChoices` | 8192 | 每个用例的随机选择数；更大的用例会被丢弃 |
| `deadline` | 0（关闭） | 单个用例的时间上限（毫秒）：更慢的用例算失败并被收缩 |
| `timeBudget` | 0（无） | 探索的时间上限（毫秒）；平稳停止并给出说明 |
| `shrinkTimeBudget` | 0（无） | 每个失败的收缩时间上限（毫秒）；保留目前最好的结果 |
| `edgeBias` | 0.25 | 边界用例提议所占比例（极限值、0、1、特殊浮点数、空集合和单元素集合） |
| `mineConstants` | true | 把属性和测试文件中的整数常量作为边界提示 |
| `swarm` | true | 有状态测试：一半的序列会省略部分命令 |
| `verbosity` | `vNormal` | `vQuiet`、`vNormal`、`vVerbose`（每个用例、每项统计）、`vDebug`（收缩步骤） |
| `suppress` | `{}` | 要跳过的健康检查：`hcLargeData`、`hcFewDistinct`、`hcSlowGeneration` |
| `hangTimeout` | 0（关闭） | 看门狗：运行超过该时长（毫秒）的用例会被报告并保存，程序以退出码 1 结束 |
| `report` | `PROPTEST_REPORT` | 追加每个结果的 JSON Lines 文件；为空则不写 |
| `seed` | 随机 | 固定本次运行的种子 |
| `name` | `file:line` | 属性名；由它派生属性自己的种子 |

| 环境变量 | 作用 |
|---|---|
| `PROPTEST_SEED` | 重放一次运行（每个失败报告中都会打印） |
| `PROPTEST_CASES` | 默认 `cases`，例如在 CI 中比本地多 |
| `PROPTEST_MAX_SHRINKS` | 默认 `maxShrinks` |
| `PROPTEST_DB` | 本地文件目录：运行种子、失败数据库（默认 `.proptest`），或 `off` |
| `PROPTEST_DEADLINE` | 默认 `deadline`（毫秒），例如在 CI 中设置 |
| `PROPTEST_TIME_BUDGET` | 默认 `timeBudget`（毫秒） |
| `PROPTEST_VERBOSITY` | `quiet`、`normal`、`verbose` 或 `debug` |
| `PROPTEST_REPORT` | 默认 `report`：供 CI 工具使用的 JSON Lines 文件（见下文） |
| `PROPTEST_HANG_TIMEOUT` | 默认 `hangTimeout`（毫秒），建议在 CI 中设置，例如 60000 |

<a id="json-report-for-ci"></a>
### 用于 CI 的 JSON 报告

`PROPTEST_REPORT=proptest-report.jsonl nimble test` 会为每个属性向该文件追加一行 JSON（文件及其目录会自动创建；多个测试程序可以共用一个文件）。每行包含 `format`（1）、`name`、`status`（`passed`、`failed`、`flaky`、`gaveUp`、`generatorError`、`insufficientCoverage`，或来自[看门狗](TROUBLESHOOTING.md#the-test-hangs)的 `hung`，该行字段较少）、`passed`、`seed`（字符串：放不进 JSON 数字）、`program`、`replay`（重放此次运行的命令）、`casesPassed`、`discarded`、`firstFailureAt`、`durationMs`、`message`、`labeledCases`、`labels`（`name`、`kind`、`cases`、`events`，`cover` 还有 `required`）、`targets`（`label`、`best`：每个名称的最佳 `target` 分数）、`warnings`，以及 `failures`：`kind` 和 `location`（失败签名）、`message`、`source`（`explored`、`database`、`example`）、`flaky`、`choices`、`shrinkExecutions`、`shrinkStopped`、`inputs`（`name`、`value`）、状态机的 `machine` 和 `steps`、`stackTrace`。可能会新增字段；若某个字段改变含义或被移除，`format` 会递增。

```sh
jq -r 'select(.passed | not) | "\(.name): \(.status), \(.replay)"' proptest-report.jsonl
```

## 生成器

### 类型，包括你自己的

`x in T` 无需任何代码即可生成以下类型，可任意嵌套：所有宽度的整数（包括 `range` 类型）、`float`/`float32`（包括 NaN、无穷大和 -0.0）、`bool`、`char`、`string`、枚举、`seq`、`array`、`set`、`Option`、元组、`Table`、`OrderedTable`、`HashSet`，以及**你自己的类型**：

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

对象、case object、`distinct` 和 `ref` 对象逐字段推导；case object 某个分支里的 bug 会收缩到该分支并使用最简单的字段，树结构的 bug 会收缩到最小的树。整数会经常取到 `low(T)` 和 `high(T)`，因为 bug 就藏在那里。指南：[GENERATORS.md](GENERATORS.md)。

### 组合子

| 生成器 | 值 | 收缩方向 |
|---|---|---|
| `ints(lo, hi)`、`ints()`、`ints(lo, hi, near = [v])` | `lo .. hi` 内的整数；`near` 会提议 `v-1`、`v`、`v+1` | 最接近 0 的值 |
| `floats(lo, hi)`、`floats(allowNaN, allowInf)` | 浮点数 | 0.0 |
| `bools()` | `bool` | `false` |
| `chars(alphabet)` | `alphabet` 中的字符 | 第一个字符 |
| `strings(alphabet, minLen, maxLen)` | 字符串 | 更短、更靠前的字符 |
| `seqs(g, minLen, maxLen)` | 由 `g` 的值组成的 `seq` | 更短、元素更简单 |
| `tables(k, v, ...)`、`hashSets(g, ...)` | 由生成值组成的容器 | 更少、更简单的条目 |
| `uniqueSeqs(g, ...)`、`sortedSeqs(g, ...)` | 元素互不相同或升序排列的 `seq` | 更短、元素更简单 |
| `sized(proc(n: int): Gen[T] = ...)`、`g.resize(n)` | 依据当前规模构建的生成器，或固定规模 | 更小的规模 |
| `strings(alphanumeric, ...)`、`identifiers(maxLen)`、`unicodeStrings(minLen, maxLen)` | 字母和数字（`alphanumeric` 是一个字母表）、标识符、覆盖所有平面的合法 UTF-8 | 更短、`a` |
| `frequency([(w, g), ...])` | 按权重选出的一个生成器 | 第一项 |
| `recursive(base, extend, maxDepth)` | 树：每一层要么是 `base`，要么再深一层 | `base` |
| `optionals(g)` | `Option` | `none` |
| `elements([a, b, c])` | 其中一个值 | 第一个 |
| `oneOf(g1, g2, ...)` | 来自其中一个生成器的值 | 第一个生成器 |
| `constant(v)` | 总是 `v` | |
| `g.map(f)`、`g.filter(pred)`、`g.flatMap(f)` | 变换后的值 | 通过原始生成器 |
| `gen(T)` | 按类型推断出的生成器，作为一个值 | |

你永远不需要编写收缩器：每个生成器，包括 `map`、`filter` 和 `flatMap` 链，都会自动收缩，收缩后的值仍然满足过滤条件。

### 字段之间必须一致时：编写 `arbitrary`

推导会独立地填充每个字段。当字段之间必须一致（开始早于结束）时，重载 `arbitrary`；它总是优先于推导：

```nim
proc arbitrary(src: ChoiceSource; t: typedesc[Money]): Money =
  Money(cents: src.drawInt(0, 1_000_000),
        currency: elements(["USD", "EUR", "BRL"]).generate(src))
```

或者用 `newGen` 基于抽取原语（`drawInt`、`drawBool`、`drawIndex`、`drawFloat`、`drawFloatRange`、`drawUpTo`）构建一个生成器值。唯一的规则：更小的选择必须对应更简单的值，而所有原语都已经遵守这一点。

```nim
let sortedPairs = newGen(proc(src: ChoiceSource): (int, int) =
  let a = src.drawInt(-100, 100)
  let b = src.drawInt(a, 100)
  (a, b))
```

## 发现更多 bug，并看清测试了什么

通过测试并不能说明从未生成过的输入怎样。检查并引导这一点的方法（设计：[ADR-0012](../../decisions/0012-bug-finding-power.md)；模式：[PATTERNS.md](PATTERNS.md)）：

```nim
forAll(initSettings(cases = 300), xs in seq[int]):
  classify(xs.len == 0, "empty")          # share of cases, printed after the run
  cover(20.0, xs.len >= 10, "ten or more") # fails if confidently below 20%
  label("len " & $min(xs.len, 3))         # cases by a computed text
  check ...
```

- **边界。** 整数会取到 0、1、-1 和类型极限；浮点数会取到 -0.0、NaN、无穷大和次正规数；集合会取到空集合和单元素集合。属性中用到的整数常量（`const openFor = 1000`）以及测试文件中的整数字面量会以 `v - 1`、`v`、`v + 1` 的形式被提议。对于定义在别处的边界：`ints(0, 2000, near = [openFor])`。
- **Swarm testing**（状态机）：一半的序列会省略部分命令，于是其余命令的长串连续执行变得很可能（一个需要连续 12 次递增且中间没有重置的 bug：之前 100 个种子中找到 3 次，启用后 100 个中找到 97 次）。
- **定向探索**，用于随机用例很少能到达的深层状态：给引擎一个可以攀升的分数，在完成一半用例之后，它会扩展目前最好的用例。
  ```nim
  stateMachine Breaker:
    ...
    invariant:
      target(float(model.reopenings), "reopenings")   # climb toward many reopenings
  ```
  熔断器的退避上限（连续五次重新打开）在不使用它时 100 个种子中找到 3 次，使用后找到 20 次。它在进展沿序列累积时有帮助；对于相互独立的值，更适合用 `near` 提示或专门的生成器。
- **截止时间和预算**：`deadline` 让慢用例成为失败，并收缩到导致变慢的输入；`timeBudget` 和 `shrinkTimeBudget` 会提前停止并给出说明。
- **健康检查**会给出警告和修复建议：数据大到超出 `maxChoices`、输入空间小于 `cases`、生成时间占据了大部分运行时间。

库本身发现 bug 的能力是经过度量的：[`benchmarks/b_find.nim`](../../../benchmarks/b_find.nim) 在固定种子上运行埋入的 bug，任何检出率下降都会让 CI 失败。

## 结果与失败

看起来哪里不对（gave up、flaky、某个警告、某个种子无法重放）？[TROUBLESHOOTING.md](TROUBLESHOOTING.md) 从你看到的现象出发。

- **在 unittest 的 `test` 内**：失败的属性会让该测试失败，并只给出一份报告。
- **在其他地方**：`forAll` 抛出 `PropertyError`（带有 `.propertyResult`），而 `forAllResult(...)`（参数相同）返回 `PropertyResult` 而不抛出异常。

| 状态 | 含义 |
|---|---|
| `psPassed` | 所有用例都通过 |
| `psFailed` | 至少有一个反例，并已重新运行两次加以确认 |
| `psFlaky` | 最小反例没有再次失败：属性依赖时间、全局状态、线程或 I/O |
| `psGaveUp` | 被 `assume` 或 `filter` 丢弃的用例过多 |
| `psGeneratorError` | 某个生成器抛出了异常：bug 在生成器里，而不在被测代码里 |
| `psInsufficientCoverage` | 所有用例都通过，但某项 `cover` 要求被可信地判定为未达到 |

在代码中读取结果（`forAllResult`、`stateMachineResult`，或 `PropertyError` 的 `.propertyResult`）：

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

`r.status` 是上表中的某个值；`r.runSeed` 可重放此次运行；`r.casesRun`、`r.discarded`、`r.labels` 和 `r.warnings` 保存报告中打印的统计信息和健康检查。每个失败还包含 `choices`（其最小选择序列）、`shrinkExecutions`、`shrinkStopped`（收缩达到了 `shrinkTimeBudget`）、`flaky` 和 `stackTrace`。

最多 `maxFailures` 个**不同的** bug（异常类型或位置不同）会被分别报告，各自独立收缩；收缩永远不会把一个 bug 变成另一个。

**复现**：每份报告都会打印 `PROPTEST_SEED=<n>`；用它运行同一个二进制文件，就能得到相同的用例和相同的反例。种子还会在第一个用例之前写入 `.proptest/last-run`，所以即使崩溃也能保留。

**失败不会丢失**：每个复现的失败都会保存在 `.proptest/db/` 中，并在后续运行中**先于任何随机用例**重放，因此修复会立即得到验证；某个条目连续通过三次运行后会被遗忘。`PROPTEST_DB=off` 可关闭此功能。把 `.proptest/` 加入你的 `.gitignore`（CI 可以缓存它）。要永久固定某个用例，添加 `example(...)`（每个变量一个值，最先运行），或者把有状态报告中的 `replayCommands` 块粘贴进测试：

```nim
forAll(x in int, s in string, example(0, ""), example(-1, "a")): ...
```

<a id="features"></a>
## 功能

- 支持类型和生成器值的 `forAll` / `forAllResult`
- 内置类型生成器、组合子、自定义 `arbitrary` 和 `newGen`
- 集成收缩、多个不同失败、flaky 检测
- `check`/`require` 改写、`assume`、设置、环境变量
- 与 `std/unittest` 和 `unittest2` 集成；也可独立使用
- 供 CI 工具使用的 JSON 报告（`PROPTEST_REPORT`）
- 种子重放和崩溃线索（CI 覆盖 Linux、macOS 和 Windows）
- 有状态 / 基于模型的测试：`stateMachine`，最短失败序列以 `replayCommands` 代码形式打印
- 为对象、case object、`distinct`、`ref` 和递归类型推导生成器；`Table`、`HashSet`；`frequency`、`recursive`；Unicode 字符串
- 失败数据库（先重放过去的失败）、显式 `example(...)`
- `classify` / `cover` / `label`、有状态统计、详细程度级别
- 边界用例偏好、边界提示（`near`、挖掘出的常量）、swarm testing
- 单用例截止时间、运行和收缩的时间预算、健康检查
- 配置参考和故障排查指南，并在 CI 中与代码核对
- 稳定性策略：同一种子在补丁版本之间可重放，由 golden snapshot 校验（[STABILITY.md](STABILITY.md)）
- `sized`、`resize`、`uniqueSeqs`、`sortedSeqs`、定向探索（`target`）
- 看门狗（可选，`PROPTEST_HANG_TIMEOUT`）：永不返回的用例会被报告（输入、选择、重放方式）并保存，而不是让运行挂住（需要 `--threads:on`，这是 Nim 的默认值）

## 已知限制

- **除非开启看门狗，否则永不返回的用例会让运行挂住**：设置 `PROPTEST_HANG_TIMEOUT=60000`（建议在 CI 中使用；默认关闭）后，用例会在该时长后被报告并保存，然后程序以退出码 1 结束，因为正在运行的用例无法被安全中断。它无法被收缩，其输入会在下一次运行时打印（或者使用 `PROPTEST_VERBOSITY=verbose` 时立即打印）。没有 `--threads:on` 就没有看门狗。
- **深层状态依然困难**：需要一条又长又特定的路径才能到达的状态（熔断器连续五次重新打开，每次都在恰当的等待之后）很少被随机序列触达。当属性能够度量进展时，`target(score)` 会有帮助（熔断器：100 个种子中从 3 次提升到 20 次）；对于你已经知道的路径，把它写成 `replayCommands` 测试。
- **Release 构建只能定位 `check` 失败**：没有 `--stackTrace:on --lineTrace:on` 时（`-d:release`、`-d:danger`），其他异常只按类型区分，所以抛出同一类型的两个 bug 会被报告为一个。编译时会有警告说明这一点；参见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md#two-bugs-reported-as-one-or-location-unknown)。
- **`--panics:on`**：`Defect` 会在第一个失败用例处结束进程，因此无法收缩（编译时会有警告说明这一点）。
- 在属性体内使用宽泛的 `except CatchableError` 也会捕获库的内部信号（`assume`、失败的 `check`）；请重新抛出它们，或捕获更具体的类型。
- 同一种子生成的值只会在次版本中改变，并且总会列在 [CHANGELOG](../../../CHANGELOG.md) 中（[稳定性策略](STABILITY.md)），所以次版本升级后旧种子可能无法重放。

## 有状态测试

随机命令序列同时作用于真实系统和一个简单模型；每一步之后两者必须一致。失败会以**最短**的失败序列报告，并打印为 Nim 代码，可直接粘贴为回归测试。完整教程：[STATEFUL.md](STATEFUL.md)。

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

对于一个在恰好 3 次 push 和 1 次 pop 之后 `pop` 出错的队列：

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

时间也是一个命令（`command advance(ms in ints(0, 2000))` 推进一个假时钟），因此与时间相关的 bug 会收缩到精确的等待时长。`teardown:` 总会执行；参数可以从模型中取（`k in elements(model.keys)`）。

## 质量

- 158 个测试，在 `orc`/`arc` × 线程开/关 × debug/release 下全部通过；ASan、UBSan 和内存泄漏检查均无问题。
- PRNG 和哈希与其作者的 C 参考实现以及 FNV-1a 官方测试向量一致（golden 测试）。
- 值测试：[SPEC](../../SPEC.md) 中的每个参考 bug 都收缩到其精确的最小反例；两个相互独立的 bug 都会被报告，收缩也不会从一个 bug 滑到另一个（在 20 个种子上验证）。
- CI 中的确定性门禁：收缩每个参考 bug 需要 9 到 236 次执行（基线见 `benchmarks/baseline/shrink.json`）；埋入的 bug 必须在不少于基线的种子数上被找到（`benchmarks/baseline/find.json`）；抽取选择和执行有状态步骤从不分配内存，并有测试对静态标签做同样的检查。
- 第一个外部使用者：[`nim-circuit-breaker`](https://github.com/kaio-souza/nim-circuit-breaker) 的模型测试对其熔断器运行 1000 个随机序列。
- 每条需求在 [`TRACEABILITY.md`](../../TRACEABILITY.md) 中都有一行，由 `nimble trace` 校验。设计决策：[`decisions/`](../../decisions/README.md)。

```sh
nimble test     # test suite
nimble gate     # deterministic performance gates
nimble bench    # timings (informational)
nimble trace    # traceability matrix
```

## 许可证

[MIT](../../../LICENSE)
