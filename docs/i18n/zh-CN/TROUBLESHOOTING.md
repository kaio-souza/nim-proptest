**语言：** [English](../../TROUBLESHOOTING.md) · [Português (BR)](../pt-BR/TROUBLESHOOTING.md) · [Español](../es/TROUBLESHOOTING.md) · 中文

> 本文译自 [TROUBLESHOOTING.md](../../TROUBLESHOOTING.md)。如有出入，以英文版为准。下面的报告保持英文，与库实际打印的一致。

# 故障排查

找到你看到的现象，然后阅读原因和处理方法。下面的报告是真实输出（文件名已缩短）。提到的每项设置都在 [CONFIGURATION.md](CONFIGURATION.md) 中有说明。

**属性失败或停止**

- [Gave up after N passing cases](#gave-up-after-n-passing-cases)
- [FLAKY：最小用例没有再次失败](#flaky-the-minimal-case-did-not-fail-again)
- [生成器抛出了异常](#a-generator-raised)
- [未满足覆盖率要求](#missed-its-coverage-requirements)
- [DeadlineExceeded](#deadlineexceeded)
- [测试挂住了](#the-test-hangs)
- [进程结束但没有报告](#the-process-ends-with-no-report)

**报告出乎意料**

- [两个 bug 被报告为一个，或 "Location unknown"](#two-bugs-reported-as-one-or-location-unknown)
- [反例没有尽可能小](#the-counterexample-is-not-as-small-as-it-could-be)
- [从失败数据库重放](#replayed-from-the-failure-database)
- [`PROPTEST_SEED` 无法复现失败](#proptest_seed-does-not-reproduce-the-failure)

**通过了，但它应该通过吗？**

- [属性通过了，但 bug 还在](#the-property-passes-but-the-bug-is-there)
- [警告：only N distinct inputs](#warning-only-n-distinct-inputs)
- [警告：cases needed more than maxChoices](#warning-cases-needed-more-than-maxchoices)
- [警告：generating inputs takes most of the run time](#warning-generating-inputs-takes-most-of-the-run-time)
- [警告：command never ran](#warning-command-never-ran)
- [警告：time budget reached](#warning-time-budget-reached)

**其他**

- [测试套件很慢](#the-test-suite-is-slow)
- [属性的输出刷屏](#output-from-the-property-floods-the-terminal)
- [粘贴的 `replayCommands` 块报 "precondition ... is false"](#a-pasted-replaycommands-block-fails-with-precondition--is-false)
- [编译错误](#compile-errors)

---

<a id="the-property-fails-or-stops"></a>
## 属性失败或停止

<a id="gave-up-after-n-passing-cases"></a>
### Gave up after N passing cases

```
Property 'sorted' gave up after 0 passing cases: 1001 cases discarded (0 by filters, 0 too large).
```

**原因。** 被丢弃的用例太多：被 `assume(...)` 丢弃，被连续拒绝了 100 个值的 `filter` 或 `uniqueSeqs` 丢弃，或者因为对 `maxChoices` 来说太大。丢弃达到 `cases × maxDiscardRatio` 个（默认 1000）后属性停止，因为它已经测不了多少东西了。当大多数丢弃来自过滤器时，消息会补充 "Most discards come from `filter` or `uniqueSeqs` rejecting values: generate valid values directly, or widen the generator."

上面的属性需要至少 5 个元素的有序列表，而这个长度的随机列表几乎从来都不是有序的。

**怎么办。** 生成有效值，而不是拒绝无效值：

```nim
# Gives up: rejects every case.
forAll(xs in seq[int]):
  assume(xs.len >= 5 and xs.isSorted)
  ...

# Passes 100 cases: builds only valid inputs, and still shrinks.
forAll(xs in sortedSeqs(ints(), minLen = 5)):
  ...
```

`sortedSeqs` 和 `uniqueSeqs` 覆盖了最常见的两种形态。对于相互依赖的值（开始早于结束），先抽第一个，再在它的范围内抽第二个，就像 [GENERATORS.md](GENERATORS.md) 中那样。把 `assume` 留给罕见的排除情况（`assume(d != 0)`）。

规模随每次尝试增长，包括被丢弃的尝试，所以只针对规模的条件（`assume(xs.len > 30)`）只会在运行初期造成丢弃：它会通过，伴随几百次丢弃。

**权衡。** 调高 `maxDiscardRatio` 能让消息消失，但代价不会消失：每个被丢弃的用例仍要运行生成器，而通过的用例只是恰好符合条件的少数几个，所以它们可能看起来都差不多。

<a id="flaky-the-minimal-case-did-not-fail-again"></a>
### FLAKY：最小用例没有再次失败

```
Property 'flaky' is flaky at case 3 (67 cases passed, 0 discarded).
  FLAKY: the minimal case did not fail again when re-run.
  Common causes: time, randomness, global state, threads or I/O in the property.
  Counterexample (1 choices, 1 shrink executions):
    x = 0
  Error: [PropertyFailed] check failed: counter mod 3 != 0
        counter mod 3 was 0
```

**原因。** 收缩之后，每个失败都会再运行两次。如果不是两次都失败，说明结果并不只取决于生成的输入。上面的属性读取了一个每次运行都会变化的全局计数器。

**怎么办。** 找出属性除了输入之外还读取了什么：

- **全局或模块状态**：缓存、计数器、单例。在属性体内创建新的状态，或在开头重置它。
- **时间**：`now()`、`epochTime()`、超时。注入一个时钟并在属性中控制它（[有状态测试教程](STATEFUL.md)用假时钟做到了这一点）。
- 被测代码中的**随机性**：用一个生成的值作为种子（`seed in uint64`）。
- **线程、文件、网络**：顺序和时序在不同运行之间会变化。在没有它们的情况下测试逻辑，或者让测试自己拥有资源（每个用例一个临时目录）。

报告仍然会显示反例：bug 可能是真的，只是按现在的写法无法复现。不要反复重跑直到它通过。

<a id="a-generator-raised"></a>
### 生成器抛出了异常

```
Property 'price': a generator raised: [ValueError] invalid integer:
  This is a problem in a generator, not in the code under test.
```

**原因。** 异常来自生成输入的过程，发生在属性体运行之前：这里，`Money` 的 `arbitrary` 对一个随机字符串调用了 `parseInt`。库会立即停止，而不是报告一个不在你代码里的 bug。

**怎么办。** 修复生成器，让每个选择都给出有效值。直接抽取你需要的东西（`src.drawInt(0, 1_000_000)`），而不是生成更宽泛的东西再去转换。

另一个看起来相似的错误：内置生成器在属性开始时、任何用例之前，会对不可能的参数抛出 `ValueError`（`ints: lo > hi`、`seqs: invalid lengths`）。检查一下参数。

<a id="missed-its-coverage-requirements"></a>
### 未满足覆盖率要求

```
Property 'empty lists' passed 100 cases but missed its coverage requirements:
    cover 'empty': 8.0% of 100 cases, 50.0% required
  Statistics (100 cases):
      8.0%  empty  (cover: 50.0% required)
```

**原因。** `cover(50.0, xs.len == 0, "empty")` 要求至少 50% 的用例是空列表，但只有 8% 是。所有用例都通过了，但你说重要的那些用例很少出现，所以属性并没有测到你想测的东西。只有当统计区间中最乐观的一端也低于要求时，要求才会失败；当用例太少无法确定时，它会变成一条警告（"too few cases to be sure; raise `cases`"）。

**怎么办。** 要么让生成器更频繁地产生这些用例（专门的生成器、`frequency`、`near = [...]`），要么就是要求过于严格。把要求设在你真正需要的比例附近（5%、10%）通常是对的；为单一情形要求 50%，说明它值得拥有自己的属性。

<a id="deadlineexceeded"></a>
### DeadlineExceeded

```
Property 'slow' falsified at case 2 (80 cases passed, 0 discarded).
  Counterexample (1 choices, 9 shrink executions):
    x = 16
  Error: [DeadlineExceeded] case took 10.2 ms; deadline 5.0 ms
```

**原因。** 设置了 `deadline`（或 `PROPTEST_DEADLINE`），而某个用例耗时更长。它会像其他失败一样被收缩，收缩到仍然很慢的最小输入：这里代码在 `x > 15` 时会休眠，16 正是那个边界。

**怎么办。** 如果慢是 bug（某些输入上的二次复杂度），反例会给出那个输入。如果是噪声（负载很高的 CI 机器、debug 构建），就调高截止时间：设得远高于正常用例的耗时。探索阶段已经允许 1.25 倍的截止时间，但收缩和重跑使用的是截止时间本身，所以处在边缘的用例也可能被报告为 FLAKY。

<a id="the-test-hangs"></a>
### 测试挂住了

```
proptest: property 'hangs on 42' did not return: a case has run for more than 300 ms (hangTimeout) while exploring (case 1), running the property.
  Inputs: not recorded while exploring (formatting them would cost time on every case).
  The case was saved in the failure database: the next run replays it first and
  prints its inputs here if it still does not return.
  Choices (1): 42
  Replay: PROPTEST_SEED=1 ./t_hang
  The process stops here (exit code 1): a running case cannot be interrupted safely.
```

**原因。** 某个用例永不返回：死循环、死锁、等待一个永远不会到来的事件。`deadline` 抓不到它，因为它是在用例返回之后才测量。看门狗默认关闭，所以运行就这样挂住了。设置了 `PROPTEST_HANG_TIMEOUT`（上面是 300 毫秒）后，到时看门狗线程会报告该用例并结束进程：没有任何办法能安全地中断正在运行的用例，所以本次运行无法继续，该用例也无法收缩。

**怎么办。**

1. 如果运行只是挂住而没有报告，停止它，然后开启看门狗再运行一次，例如 `PROPTEST_HANG_TIMEOUT=10000 nimble test`（同一个种子来自 `.proptest/last-run`：`PROPTEST_SEED=<它>`）。然后再运行一次测试。该用例已被保存，所以它会最先运行，并记录下它的输入：
   ```
   proptest: property 'hangs on 42' did not return: ... while replaying a case that hung in an earlier run (case 1), running the property.
     Inputs:
       x = 42
   ```
   状态机则会显示步骤，最后一步就是不返回的那一步。使用 `PROPTEST_DB=off` 时什么都不会保存：用种子加 `PROPTEST_VERBOSITY=verbose` 重放，它会记录每个用例的输入。
2. 把这个输入变成一个普通测试或一个 `example(...)`，然后修复循环。当保存的用例通过后，它会在三次运行后被遗忘。
3. 在 CI 中保持看门狗开启，这样挂起会以这份报告失败，而不是撞上任务的时间上限：`PROPTEST_HANG_TIMEOUT=60000`。

没有 `--threads:on`（Nim 2 默认开启）就没有看门狗：停止进程，然后用 `.proptest/last-run` 中的种子加 `PROPTEST_VERBOSITY=verbose` 重放；最后打印出来的用例就是挂住的那个用例的前一个。

<a id="the-process-ends-with-no-report"></a>
### 进程结束但没有报告

**原因。** 通常是 `--panics:on`：Defect（`IndexDefect`、`AssertionDefect`、溢出）会结束进程而不是被抛出，所以库既无法收缩它，也无法报告它。编译器会警告："proptest: compiled with --panics:on"。其他原因：段错误（在 `-d:danger` 下访问 `nil`，或在 C 代码中），或被测代码调用了 `quit()`。

**怎么办。** 用 `--panics:off`（默认值）且不用 `-d:danger` 来构建测试。种子在 `.proptest/last-run` 中，可以在调试器里重放这次崩溃。

<a id="the-report-is-surprising"></a>
## 报告出乎意料

<a id="two-bugs-reported-as-one-or-location-unknown"></a>
### 两个 bug 被报告为一个，或 "Location unknown"

debug 构建：两个 bug，两个失败。

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

同一个属性用 `-d:release` 构建：一个失败，第二个 bug 被隐藏。

```
Property 'two bugs' falsified at case 8 (53 cases passed, 0 discarded).
  Counterexample (2 choices, 17 shrink executions):
    x = 51
    y = 0
  Error: [ValueError] x too big
  Location unknown (no stack trace): failures are told apart by type only.
```

**原因。** 当两个失败具有相同的异常类型，并且在你代码的同一行抛出时，它们被视为同一个 bug。那一行来自栈跟踪，而 `-d:release` 会关闭栈跟踪。`check` 失败在任何构建中都保留行号，因为行号是在写 `check` 的地方记录的。

**怎么办。** 用 debug 构建运行属性测试，或者给 release 构建加上 `--stackTrace:on --lineTrace:on`（[表格](CONFIGURATION.md#compile-time-options)）。这样的构建在编译时会通过警告 "proptest: built without stack traces" 告知你。相反的情况，即一个 bug 被报告为多个，发生在同一个 bug 根据输入不同在不同的行抛出时；此时反例看起来很像，修复一个就修复了其他的。

<a id="the-counterexample-is-not-as-small-as-it-could-be"></a>
### 反例没有尽可能小

**原因**，从最常见到最少见：

- **自定义生成器违反了收缩规则**：更小的选择必须给出更简单的值。`src.drawInt(0, 100)` 遵守这一点；`100 - src.drawInt(0, 100)` 把它反过来了，于是收缩会朝 100 方向走。把简单的选择映射到简单的值。
- **收缩提前停止了**：报告写着 "Shrinking stopped at its time budget"（`shrinkTimeBudget`），或者显示的执行次数等于 `maxShrinks`。调高预算，或者让单次执行更快。
- **最小值不在你预期的地方**：收缩最小化的是*选择*，对于内置生成器而言意味着更短的集合、更接近 0 的值、第一个枚举值、`oneOf` 的第一个分支。当 `x = 1` 通过时，`x = -1` 可能就是最简单的失败值。
- **上面套了一个 `filter`**：收缩后的值仍必须通过过滤，这可能挡住更简单的值。直接生成有效值在这里同样有帮助。

<a id="replayed-from-the-failure-database"></a>
### 从失败数据库重放

```
  Replayed from the failure database: it failed in an earlier run.
```

**原因。** 早先运行中发现的失败被保存在 `.proptest/db/` 中，并在任何随机用例之前重放，以便立即验证修复。这个失败依然存在。

**怎么办。** 不需要特别处理：这是一个真实的失败，报告与发现它时相同。某个条目连续通过 3 次运行后会被遗忘；不再适配生成器的条目（你改了类型）会被丢弃。要从头开始，删除 `.proptest/db/`；要关闭它，用 `PROPTEST_DB=off`。

<a id="proptest_seed-does-not-reproduce-the-failure"></a>
### `PROPTEST_SEED` 无法复现失败

**原因。** 只有当决定输入的其他一切都相同时，种子才能复现一次运行。按顺序检查：

1. **代码改了。** 属性的种子来自它的名称，默认是它的 `file:line`：在它上方加一行会改变它的输入。从文件中挖掘的常量也会变化。用打印该种子的那个二进制文件来使用它，或者给属性一个 `name`。
2. **设置不同。** `cases` 决定规模如何增长，所以用 100 个用例的运行打印出的种子配合 `PROPTEST_CASES=1000`，会得到不同的输入。`maxSize`、`edgeBias`、`maxDepth`、`maxSteps`、`swarm` 和 `mineConstants` 同理。
3. **属性设置了 `seed`。** 设置中的固定种子优先于 `PROPTEST_SEED`。
4. **属性不是确定性的。** 如果报告显示 FLAKY，参见[上文](#flaky-the-minimal-case-did-not-fail-again)。

平台和构建模式无关紧要：同一种子在 Linux、macOS 和 Windows 上、debug 和 release 下给出相同的值。

<a id="it-passes-but-should-it"></a>
## 通过了，但它应该通过吗？

<a id="the-property-passes-but-the-bug-is-there"></a>
### 属性通过了，但 bug 还在

属性通过只说明它尝试过的输入没问题。看看它尝试了什么：

1. **统计你关心的用例。** 为 bug 所需的情形加上 `classify`，如果它们必须出现，再加上 `cover`：
   ```nim
   forAll(xs in seq[int]):
     classify(xs.len == 0, "empty")
     classify(xs.len > 100, "long")
     cover(1.0, low(int) in xs, "has low(int)")
     check ...
   ```
   统计会在一次通过的运行之后打印。
2. **查看输入**，用 `PROPTEST_VERBOSITY=verbose PROPTEST_CASES=20`。
3. 然后，根据缺了什么：

| 缺少 | 解决办法 | 代价 |
|---|---|---|
| 某个特定值（定义在其他模块中的极限） | `ints(lo, hi, near = [limit])` | 无：其他值仍会被抽到 |
| 长输入 | 调高 `maxSize`，或 `seqs(g, minLen = ...)` | 用例更慢 |
| 罕见的组合 | 更多 `cases`（在 CI 中：`PROPTEST_CASES`） | 时间线性增长 |
| 整个一类情形 | 专门的生成器，或 `frequency` | 需要维护更多代码 |
| 状态机的深层状态 | 调高 `maxSteps`；保持 `swarm` 开启 | 序列更长 |

属性体中的整数常量已经会以 `v - 1`、`v`、`v + 1` 的形式被提议（`mineConstants`）；定义在其他模块中的常量则不会。

<a id="warning-only-n-distinct-inputs"></a>
### 警告：only N distinct inputs

```
Property 'few inputs' passed 100 cases.
  Warnings:
    only 2 distinct inputs in 100 passing cases: the input space is small, so a plain loop over it would be exhaustive
```

**原因。** 属性运行了 100 个用例，但不同的输入少得多（不同输入不到十分之一）。这里的输入是一个 `bool`，只有两个值。

**怎么办。** 如果输入空间确实这么小，遍历所有值的循环更短也更完整：

```nim
for b in [false, true]:
  check ...
```

如果它本应更大，说明生成器太窄了（你想要 `ints(0, 3000)` 却写成了 `ints(0, 3)`）。如果这条警告在预期之中，用 `initSettings(suppress = {hcFewDistinct})`。

<a id="warning-cases-needed-more-than-maxchoices"></a>
### 警告：cases needed more than maxChoices

```
Property 'too large' passed 100 cases.
  Warnings:
    440 cases needed more than maxChoices (8192) choices and were skipped: bound collection sizes (`seqs(g, maxLen = ...)`) or raise maxChoices
```

**原因。** 嵌套集合增长得很快：`maxSize = 1000` 时，一个 `seq[seq[string]]` 产生的值需要数万次选择。这些用例被跳过了，通过的 100 个是较小的那些：大输入没有得到测试。

**怎么办。** 在要紧的地方限制规模，或者调低 `maxSize`。同样的结构加上限制后，即使 `maxSize = 1000` 也不会产生警告：

```nim
let bounded = seqs(seqs(strings(alphanumeric, 0, 20), maxLen = 10), maxLen = 100)
forAll(initSettings(maxSize = 1000), v in bounded): ...
```

只有当大输入本身就是目的时才调高 `maxChoices`，并且要知道每个用例的运行和收缩都会更久。

<a id="warning-generating-inputs-takes-most-of-the-run-time"></a>
### 警告：generating inputs takes most of the run time

**原因。** 超过 80% 的时间花在了生成输入上，而不是运行属性：通常是一个拒绝了大部分值的 `filter`，或者一个构建大值又丢掉大部分的自定义生成器。

**怎么办。** 直接生成有效值，或者限制规模。如果属性本身很便宜，生成确实就是主要工作，用 `suppress = {hcSlowGeneration}`。

<a id="warning-command-never-ran"></a>
### 警告：command never ran

```
Property 'CounterSpec' passed 100 cases.
  Warnings:
    command 'reset' never ran in 100 sequences; its precondition was false 1934 times
```

**原因。** 在状态机中，前置条件从不成立的命令永远不会被测试。这里 `reset` 需要超过 1000 次递增，而序列最多只有 50 步。

**怎么办。** 让该状态可达（调高 `maxSteps`，或添加一个能更快到达那里的命令），或者在模型允许的情况下放宽前置条件。`PROPTEST_VERBOSITY=verbose` 下的统计会显示每个命令运行了多少次，以及它的前置条件有多少次为假。

<a id="warning-time-budget-reached"></a>
### 警告：time budget reached

```
Property 'budget' passed 173 cases.
  Warnings:
    time budget of 200 ms reached after 173 of 100000 cases
```

**原因。** `timeBudget`（或 `PROPTEST_TIME_BUDGET`）提前停止了探索。属性通过了它所运行的用例。

**怎么办。** 如果目标就是限制时间，什么都不用做。否则，调高预算、调低 `cases`，或者让属性更快。

<a id="other"></a>
## 其他

<a id="the-test-suite-is-slow"></a>
### 测试套件很慢

大致按影响大小排序：

1. **构建模式。** debug 构建中的生成比 release 慢好几倍。如果你以 release 构建测试，加上 `--stackTrace:on --lineTrace:on` 以保留失败位置（[原因](#two-bugs-reported-as-one-or-location-unknown)）。
2. **本地少跑，CI 多跑。** 代码中保持默认值，在 CI 中设置 `PROPTEST_CASES`。
3. **更小的输入。** 对于被测代码处理大输入很慢的属性，用更小的 `maxSize` 或有界的生成器。
4. **限制时间。** 每个属性用 `timeBudget`；用 `deadline` 找出让单个用例变慢的输入。

要看时间花在哪里，`PROPTEST_REPORT=report.jsonl` 会记录每个属性的 `durationMs`：

```sh
jq -r '"\(.durationMs)\t\(.name)"' report.jsonl | sort -rn | head
```

<a id="output-from-the-property-floods-the-terminal"></a>
### 属性的输出刷屏

**原因。** 属性体在每个用例和每个收缩步骤都会运行一次：其中的一个 `echo` 会打印几百次。在默认详细程度下，库本身不会为每个用例打印任何东西。

**怎么办。** 调试完后删掉调试输出。要看输入，用 `PROPTEST_VERBOSITY=verbose`；要看分布，用 `classify` 和 `label`。用来解释失败的文本应该放在 `check` 本身里：比较操作已经会打印两边的值（`x was 500`）。

<a id="a-pasted-replaycommands-block-fails-with-precondition--is-false"></a>
### 粘贴的 `replayCommands` 块报 "precondition ... is false"

```
replayCommands: precondition of step 3 (pop()) is false, so this sequence cannot happen
```

**原因。** 该序列是由状态机的早期版本打印的。模型或前置条件已经改变，所以这个序列不再可能发生。

**怎么办。** 如果改动是有意为之，删除这个回归测试，或者从一次新的失败运行中重新生成它。如果不是，那就是改动破坏了模型。

<a id="compile-errors"></a>
### 编译错误

| 错误 | 原因 | 解决办法 |
|---|---|---|
| `forAll(x: int)` 处的 `type expected` | Nim 在宏看到之前就把 `name: value` 形式的参数解析成对象构造 | 写成 `forAll(x in int)` |
| `declare variables as `name in Type` or `name in generator`` | `forAll(x = ints(0, 1))` | `forAll(x in ints(0, 1))` |
| `forAll needs a body: forAll(x in int): ...` | 调用没有主体，或者被当作表达式使用 | 加上主体；若要以值的形式获得结果，用 `let r = forAllResult(...): ...` |
| `proptest cannot generate field 'f' of P: overload `arbitrary` for its type, or for P` | 某个字段的类型没有生成器（`proc`、指针、来自 C 的类型） | 为该字段的类型或为 `P` 编写 `arbitrary`（[GENERATORS.md](GENERATORS.md)） |
| `proptest cannot derive T: its discriminant 'k' is a range type` | Nim 2.2.4 的限制 | 用枚举作为判别字段，或为 `T` 编写 `arbitrary` |
| `example(...) needs one value per variable (N)` | 某个示例的值太少或太多 | 每个 `name in source` 一个值，按顺序 |
| `classify is only valid inside forAll or a stateMachine` | `classify`、`cover` 或 `label` 位于属性之外 | 把它移到属性体内 |
| 警告 `proptest: compiled with --panics:on` | 参见[上文](#the-process-ends-with-no-report) | 用 `--panics:off` 构建测试 |
| 警告 `proptest: built without stack traces`，或 `... without --lineTrace:on` | release 构建：参见[上文](#two-bugs-reported-as-one-or-location-unknown) | `--stackTrace:on --lineTrace:on`，或者如果你的属性通过 `check` 失败，用 `-d:proptestTraceWarning=false` |
