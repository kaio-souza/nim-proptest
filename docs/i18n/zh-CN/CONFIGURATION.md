**语言：** [English](../../CONFIGURATION.md) · [Português (BR)](../pt-BR/CONFIGURATION.md) · [Español](../es/CONFIGURATION.md) · 中文

> 本文译自 [CONFIGURATION.md](../../CONFIGURATION.md)。如有出入，以英文版为准。

# 配置参考

每项设置、环境变量和编译选项，及其默认值、代价和何时修改。问题及其解决方法：[TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

- [配方](#recipes)：复制一个再按需修改
- [取值规则](#how-a-value-is-chosen)：显式设置、环境变量、默认值
- [设置](#settings)，按控制内容分组
- [环境变量](#environment-variables)
- [编译选项](#compile-time-options)：构建模式、`--panics`、栈跟踪
- [库写入的文件](#files-the-library-writes)
- [重放需要什么](#what-a-replay-needs)

<a id="recipes"></a>
## 配方

**日常使用，什么都不用设置。** 每个属性 100 个用例，收缩开启，失败会被保存并在下次运行时优先重放。大多数属性从来不需要任何设置。

```nim
forAll(xs in seq[int]):
  check xs.sorted.sorted == xs.sorted
```

**CI 中比本机跑更多用例。** 用环境变量而不是代码，这样本地运行依然很快：

```sh
PROPTEST_CASES=1000 PROPTEST_HANG_TIMEOUT=60000 PROPTEST_REPORT=proptest-report.jsonl nimble test
```

`PROPTEST_HANG_TIMEOUT` 会开启看门狗：永不返回的用例会带着报告结束运行，而不是一直跑到 CI 任务的时间上限。

自己设置了 `cases` 的属性会忽略 `PROPTEST_CASES`（参见[优先级](#how-a-value-is-chosen)）：希望由 CI 放大的属性就不要写 `cases`。

**夜间深度运行。** 多得多的用例，但用时间加以限制，避免某个慢属性占满整夜：

```sh
PROPTEST_CASES=100000 PROPTEST_TIME_BUDGET=60000 PROPTEST_HANG_TIMEOUT=60000 PROPTEST_VERBOSITY=quiet nimble test
```

`timeBudget` 按属性计算：每个属性在 60 秒后停止，并给出一条说明运行了多少用例的警告。

**重放一次失败。** 复制报告中的 `Replay:` 行。同一个二进制文件，其余环境也相同：

```sh
PROPTEST_SEED=17542877672211577899 ./tests/t_sorting
```

**查看属性生成了什么。** 每个用例的输入，以及所有统计：

```sh
PROPTEST_VERBOSITY=verbose PROPTEST_CASES=20 ./tests/t_sorting
```

**一个开销很大的属性。** 更少但更大的用例，并限制单个用例的时间：

```nim
forAll(initSettings(cases = 30, maxSize = 300, deadline = 2000), doc in Document):
  check parse(render(doc)) == doc
```

**必须始终看到相同输入的属性**（文档中的示例、库自身的测试）：固定种子。此时它会忽略 `PROPTEST_SEED`。

```nim
forAll(initSettings(seed = 42), x in int): ...
```

**许多属性使用同一组设置。** `Settings` 是一个普通对象；构建一次即可：

```nim
let heavy = initSettings(cases = 50, maxSize = 500, deadline = 1000)

test "round trip":
  forAll(heavy, doc in Document):
    check parse(render(doc)) == doc

test "rendering is stable":
  forAll(heavy, doc in Document):
    check render(doc) == render(parse(render(doc)))
```

每个属性仍然有自己的种子（由其 `file:line` 名称派生），所以共享设置不会让两个属性抽到相同的值。因此，共享设置中请把 `name` 留空。

<a id="how-a-value-is-chosen"></a>
## 取值规则

对每项设置，第一个适用的来源生效：

1. 传给 `initSettings(...)` 的**参数**。
2. **环境变量**，仅针对有对应变量的设置（在 `initSettings` 运行时读取）。
3. **内置默认值。**

```nim
# PROPTEST_CASES=1000 in the environment:
forAll(x in int): ...                          # 1000 cases: environment
forAll(initSettings(cases = 20), x in int): ... # 20 cases: argument
```

种子遵循相同顺序：设置中的 `seed`，然后是 `PROPTEST_SEED`，然后是每个进程只选一次的随机种子。这个**运行种子**不会被直接使用：每个属性由它和自己的 `name` 派生出自己的种子，因此一个 `PROPTEST_SEED` 就能重放程序中的所有属性，并且各属性不共享随机流。

无法解析的环境变量是一个错误，而不是被悄悄忽略：`PROPTEST_CASES=abc` 会在第一个属性处抛出 `ValueError: PROPTEST_CASES is not an integer: abc`。无效的设置（`cases = 0`、`edgeBias = 2.0`）会在任何用例运行之前抛出 `ValueError: invalid proptest settings: ...`。

<a id="settings"></a>
## 设置

把它们传给 `initSettings(...)`，放在 `forAll`、`forAllResult` 或 `checkStateMachine` 的参数中。对状态机而言，**一个用例就是一整条**命令序列。

<a id="how-much-to-test"></a>
### 测试多少

| 设置 | 默认值 | 环境变量 | 有效范围 |
|---|---|---|---|
| `cases` | 100 | `PROPTEST_CASES` | >= 1 |
| `maxSize` | 100 | | >= 0 |
| `maxSteps` | 50 | | >= 1 |
| `maxDepth` | 5 | | >= 0 |
| `maxChoices` | 8192 | | >= 1 |

**`cases`**：探索的用例数，无论通过还是失败。成本线性增长；碰到需要罕见输入的 bug 的概率也会增长，但增长得很慢：一个每 1000 个输入才触发 1 次的 bug，100 个用例大约每 10 次运行找到 1 次，1000 个用例大约每 3 次运行找到 2 次。在 CI 中调高它，而不是在代码里。**修改它会改变所有用例的输入**（规模随运行增长，见 `maxSize`），所以种子只有在 `cases` 相同时才能重放。

**`maxSize`**：值能有多大。规模从第一个用例的 0 增长到最后一个用例的 `maxSize`，所以最初的用例又小又简单。被丢弃的用例也会推进规模，所以丢弃小输入的属性（`assume(xs.len > 30)`）仍然能到达更大的输入。在生成器内部，`sized` 读取当前规模，`resize` 固定规模（[GENERATORS.md](GENERATORS.md)）。在 `seq[int]` 上以 100 个用例测得：

| `maxSize` | 平均长度 | 最长 |
|---|---|---|
| 10 | 3 | 16 |
| 100（默认） | 40 | 154 |
| 1000 | 416 | 1927 |

当某个 bug 需要长输入时（一个在 256 个元素时才填满的缓冲区）调高它；当被测代码处理大输入很慢时调低它。嵌套集合比顶层集合短。更大的值收缩也更耗时，但收缩最终总会得到一个最小值。针对单个生成器的规模限制最好写在生成器上：`seqs(ints(), maxLen = 10)`。

**`maxSteps`**（状态机）：最长的命令序列。大多数 bug 只需要很少的步骤，而 swarm testing（见下）让同一命令的长串连续执行在 50 步内就很可能出现。对于需要很多步骤的 bug（计数器在 300 次递增后溢出）调高它；每条序列的成本也随之增长。

**`maxDepth`**：探索时递归数据的深度（树、指向自身类型的 `ref` 对象、嵌套 `seq`）。越深意味着用例越大越慢。0 会给出递归类型的最简单值（`nil` 引用、空的子节点列表）。

**`maxChoices`**：一个用例可以使用的随机选择数（一个 `int` 是一次选择，一个 `seq` 大约每个元素一次再加上元素本身）。需要更多选择的用例会被跳过并计为 "too large"，以防失控的生成器耗尽内存。当[健康检查](TROUBLESHOOTING.md#warning-cases-needed-more-than-maxchoices)提示很多用例被跳过时，先限制生成器的规模；只有当大用例本身就是目的时才调高 `maxChoices`。

<a id="shrinking"></a>
### 收缩

| 设置 | 默认值 | 环境变量 | 有效范围 |
|---|---|---|---|
| `maxShrinks` | 2000 | `PROPTEST_MAX_SHRINKS` | >= 0 |
| `shrinkTimeBudget` | 0（无） | | >= 0 ms |
| `maxFailures` | 3 | | >= 1 |

**`maxShrinks`**：为收缩每个失败而执行属性的次数。库的参考 bug 在 9 到 236 次执行内收缩到精确的最小值，所以 2000 已经很宽裕；当单次执行很慢时，这个预算才重要。0 会按发现时的样子报告第一个失败用例，不做收缩。

**`shrinkTimeBudget`**：每个失败的收缩时间上限，适用于慢属性。达到上限时，报告会写 "Shrinking stopped at its time budget"，并给出目前最小的反例：有效，但不一定是最小的。

**`maxFailures`**：保留并收缩的不同失败（异常类型或位置不同）的数量。第一个失败之后探索仍会继续以寻找其他失败，当已知失败达到这个数量时停止。设为 1 会在第一个 bug 处停止，速度更快，但会把第二个 bug 藏起来，直到第一个被修复。

<a id="finding-bugs"></a>
### 发现 bug

| 设置 | 默认值 | 环境变量 | 有效范围 |
|---|---|---|---|
| `edgeBias` | 0.25 | | 0.0 .. 1.0 |
| `mineConstants` | true | | |
| `swarm` | true | | |
| `maxDiscardRatio` | 10 | | >= 0 |

**`edgeBias`**：抽取中提议边界值而不是均匀值的比例：整数为 0、1、-1 和类型极限；浮点数为 -0.0、NaN、无穷大和次正规数；集合为空集合和单元素集合。bug 往往集中在那里。0.0 只给出均匀值；更高的值会更多地测试边界、更少地测试典型值。修改它会改变所有用例的输入。

**`mineConstants`**：属性体中的整数字面量和常量（以及以较少的抽取次数，整个测试文件中的）会以 `v - 1`、`v`、`v + 1` 的形式被提议。这就是 `x == 1000` 能在 `0 .. 2000` 中被找到的原因。这也意味着提到 `997` 的属性会比随机情况更常看到 996 到 998：通常这正是你想要的。关闭它可以测量纯随机行为。对于定义在其他模块中的边界，用 `ints(lo, hi, near = [v])`。

**`swarm`**（状态机）：一半的序列会省略一个随机的命令子集，于是剩余命令的长串连续执行变得很可能（"连续 12 次递增且没有重置"：不使用 swarm 时 100 个种子中找到 3 次，使用后找到 97 次）。另一半使用所有命令。只在做对比时才关闭它。

**`maxDiscardRatio`**：属性在丢弃 `cases × maxDiscardRatio` 个用例（因为 `assume`、`filter`，或过大）之后放弃。调高它只是掩盖问题；直接生成有效值才能解决问题（[gave up](TROUBLESHOOTING.md#gave-up-after-n-passing-cases)）。

<a id="time"></a>
### 时间

| 设置 | 默认值 | 环境变量 | 有效范围 |
|---|---|---|---|
| `deadline` | 0（关闭） | `PROPTEST_DEADLINE` | >= 0 ms |
| `timeBudget` | 0（无） | `PROPTEST_TIME_BUDGET` | >= 0 ms |
| `hangTimeout` | 0（关闭） | `PROPTEST_HANG_TIMEOUT` | >= 0 ms；0 表示关闭 |

**`deadline`**：耗时更长的用例会以 `DeadlineExceeded` 失败，并像其他失败一样被收缩：收缩到仍然很慢的最小输入。用它来发现性能悬崖（某些输入上的二次复杂度）。探索期间，一个用例允许 1.25 倍的截止时间，这样刚好超出一点的用例不会变成 flaky 报告。权衡：耗时会因机器和负载而变化，所以要把它设得远高于正常用例的耗时，尤其是在 CI 中。它不会终止永不返回的用例：那是 `hangTimeout` 的事。

**`timeBudget`**：按属性计算的探索时间上限。达到上限时，属性停止并报告做了什么：通过的属性会给出警告 "time budget of N ms reached after K of M cases"。它让 CI 时间保持有界，代价是在慢机器上跑的用例更少。

**`hangTimeout`**：超过这个时长仍未返回的用例（死循环、死锁）会由看门狗线程报告，随后看门狗**以退出码 1 结束进程**：正在运行的用例无法被安全中断，所以无法继续本次运行。报告会给出属性名、当时在做什么（探索、收缩、某个已保存的用例）、该用例的选择以及重放命令；该用例会被保存到失败数据库中，所以下一次运行会先重放它并打印其输入。JSON 报告中会追加一行 `hung`。**默认关闭**，这样在调试器中单步执行某个用例，或者某个本来就慢的属性，都不会意外地结束进程。在挂起代价最大的地方开启它，也就是 CI 中，并设得远高于你最慢的正常用例：`PROPTEST_HANG_TIMEOUT=60000`。没有它时，永不返回的用例会让运行一直挂住，直到被手动停止（[之后](TROUBLESHOOTING.md#the-test-hangs)）。看门狗需要 `--threads:on`（Nim 2 的默认值），并且一次只监视一个属性：在其他线程上并发运行的属性不受监视。[它触发时怎么办](TROUBLESHOOTING.md#the-test-hangs)。

<a id="output"></a>
### 输出

| 设置 | 默认值 | 环境变量 | 取值 |
|---|---|---|---|
| `verbosity` | `vNormal` | `PROPTEST_VERBOSITY` | `quiet`、`normal`、`verbose`、`debug` |
| `report` | 空（无） | `PROPTEST_REPORT` | 文件路径 |
| `suppress` | `{}` | | `hcLargeData`、`hcFewDistinct`、`hcSlowGeneration` |

**`verbosity`**：

| 级别 | 打印内容 |
|---|---|
| `quiet` | 只有失败 |
| `normal` | 另加警告，以及使用了 `classify`、`cover` 或 `label` 的属性的统计 |
| `verbose` | 另加每个用例一行及其输入，以及所有统计（有状态命令计数、序列长度） |
| `debug` | 另加每个被接受的收缩步骤 |

在环境变量中，名称没有 `v` 前缀（`PROPTEST_VERBOSITY=verbose`）；在代码中则有（`verbosity = vVerbose`）。

**`report`**：一个 [JSON Lines](https://jsonlines.org) 文件，每个属性的结果都会追加到其中，供 CI 工具使用。文件及其目录会被自动创建；多个测试程序可以共用一个文件。无法写入的路径会抛出带有该路径的 `IOError`。字段：见 [README](README.md#json-report-for-ci)。示例：列出失败以及如何重放。

```sh
jq -r 'select(.passed | not) | "\(.name): \(.status) — \(.replay)"' proptest-report.jsonl
```

**`suppress`**：不在此属性上运行的健康检查。优先修复检查指出的问题；当警告在预期之中时再抑制它（基于 `bool` 的属性确实只有两个输入）。

<a id="identity-and-reproduction"></a>
### 标识与复现

| 设置 | 默认值 | 环境变量 |
|---|---|---|
| `seed` | 随机 | `PROPTEST_SEED` |
| `name` | `file:line` | |

**`seed`**：为该属性固定运行种子；此时它会忽略 `PROPTEST_SEED`。适合文档和库自身的测试；不适合普通测试，因为它们会永远探索同样的 100 个输入。

**`name`**：显示在报告中，并用于两件事：

- **属性的种子**由运行种子和名称派生。使用默认名称（`file:line`）时，在属性上方加一行代码，会让同一个 `PROPTEST_SEED` 得到不同的输入。报告中打印的种子只能重放打印它的那个二进制文件；编辑文件之后，请依靠失败数据库。
- **失败数据库的键。** 没有名称时，键是属性代码的哈希，所以编辑属性会让它保存的失败被遗忘（它们可能已经没有意义了）。有名称时，保存的失败在编辑后依然保留；不再适配生成器的条目会被丢弃。

给你在其他地方引用的属性（缺陷跟踪系统、CI 仪表板）起个名字：代码行移动时它依然稳定。

<a id="environment-variables"></a>
## 环境变量

| 变量 | 设置 | 格式 | 典型用途 |
|---|---|---|---|
| `PROPTEST_SEED` | 运行种子 | 无符号 64 位整数 | 重放一次失败 |
| `PROPTEST_CASES` | 默认 `cases` | 整数 | CI 中更多用例 |
| `PROPTEST_MAX_SHRINKS` | 默认 `maxShrinks` | 整数 | CI 中的慢属性 |
| `PROPTEST_DEADLINE` | 默认 `deadline` | 整数，毫秒 | 在 CI 中捕获慢用例 |
| `PROPTEST_TIME_BUDGET` | 默认 `timeBudget` | 整数，毫秒 | 限制夜间运行时长 |
| `PROPTEST_HANG_TIMEOUT` | 默认 `hangTimeout` | 整数，毫秒；0（默认）表示关闭 | 在 CI 中开启看门狗：挂起会带着报告失败 |
| `PROPTEST_VERBOSITY` | 默认 `verbosity` | `quiet`、`normal`、`verbose`、`debug` | 查看生成的输入 |
| `PROPTEST_REPORT` | 默认 `report` | 文件路径 | 供 CI 工具使用的 JSON |
| `PROPTEST_DB` | 本地文件目录 | 路径，或 `off` | 移动或关闭 `.proptest/` |

没有对应变量的设置（`maxSize`、`edgeBias` 等）改变的是属性测试什么，而不是它运行多久，所以最好写在代码里，让读代码的人能看到。若要为整个测试套件设置它们，共享一个 `Settings` 值（[配方](#recipes)）。

<a id="compile-time-options"></a>
## 编译选项

**构建模式与栈跟踪。** 失败按异常类型以及抛出它的那一行代码来区分。那一行来自栈跟踪，而 `-d:release` 和 `-d:danger` 会关闭栈跟踪：

| 构建 | `check` 失败 | `doAssert`、`raise`、索引错误 | 溢出与索引检查 |
|---|---|---|---|
| debug（默认） | 可定位 | 可定位 | 开 |
| `-d:release` | 可定位 | 仅类型 | 开 |
| `-d:release --stackTrace:on` | 可定位 | 仅文件（`t_sort.nim:0`） | 开 |
| `-d:release --stackTrace:on --lineTrace:on` | 可定位 | 可定位 | 开 |
| `-d:danger` | 可定位 | 仅类型 | **关** |

没有位置信息时，抛出同一异常类型的两个不同 bug 看起来像一个，报告会写 "Location unknown (no stack trace)"。属性测试最好用 debug 构建，或者在 release 构建中加上 `--stackTrace:on --lineTrace:on`（两者都要：只有栈跟踪没有行号）。缺少任意一项时，库会在编译期发出警告：

```
Warning: proptest: built without stack traces (-d:release and -d:danger turn them off). Failures other than `check` are then told apart by exception type only: two bugs that raise the same type are reported as one. Build tests with --stackTrace:on --lineTrace:on, or silence this with -d:proptestTraceWarning=false.
```

**`-d:proptestTraceWarning=false`。** 关闭这条警告，适用于有意以 release 构建、且属性都通过 `check` 失败（在任何构建中都能定位）的测试套件。避免 `-d:danger`：关闭检查后，越界索引是未定义行为，而不是库能够捕获并收缩的失败。

**`--panics:on`。** Defect（`IndexDefect`、`AssertionDefect` 等）会立即结束进程，因此失败用例无法被收缩。库会在编译期发出警告。用默认的 `--panics:off` 构建测试；如果必须开启，运行种子已经在 `.proptest/last-run` 中，可用来重放这次崩溃。

**`-d:proptestDb=<dir>` 或 `-d:proptestDb=off`。** `PROPTEST_DB` 的编译期默认值，适用于绝不应写文件的测试二进制（环境变量仍会覆盖它）。

**内存管理与线程。** `--mm:orc`（默认）和 `--mm:arc`，线程开或关，都在 CI 中于 Linux、macOS 和 Windows 上经过测试。

<a id="files-the-library-writes"></a>
## 库写入的文件

全部位于 `PROPTEST_DB` 下（默认 `.proptest`，相对于工作目录）。把它加入 `.gitignore`。

| 文件 | 写入时机 | 用途 |
|---|---|---|
| `last-run` | 每次运行的第一个用例之前 | 运行种子和命令：用于重放崩溃或挂起的运行 |
| `db/<hash>.txt` | 某个属性失败之后 | 最小的失败用例，在后续运行中优先重放；连续 3 次运行通过后被遗忘 |

写入错误会被忽略：只读目录永远不会让测试失败。`PROPTEST_DB=off` 时什么都不写。

**失败数据库的权衡。** 你刚看到的 bug 会被优先重试，所以修复会立即得到验证，而不必等随机探索再次找到它。代价是：同一二进制用同一种子运行两次，结果可能不同，因为第二次还会重放保存的失败。需要完全相同的运行时（基准测试、比较种子），用 `PROPTEST_DB=off`。在 CI 中，除非你缓存了该目录，它在开始时是空的；缓存它会把失败从一次 CI 运行带到下一次。

<a id="what-a-replay-needs"></a>
## 重放需要什么

当决定输入的其他一切都相同时，`PROPTEST_SEED=<n>` 能精确复现一次运行：

- 同一个编译好的测试（相同代码，因此属性名相同，从中挖掘的常量也相同）；
- 影响输入的相同设置：`cases`、`maxSize`、`edgeBias`、`maxDepth`、`maxSteps`、`swarm`、`mineConstants`，包括 `PROPTEST_CASES`；
- 确定性的属性：没有会改变其结果的时钟、全局状态、线程或 I/O。否则报告会显示 FLAKY。

库的随机生成器和哈希是库自带且固定的（在所有平台上用参考向量测试），所以同一种子在 Linux、macOS 和 Windows 上、在 debug 和 release 下给出相同的值。同一种子生成的值只有在 CHANGELOG 的 **Generation changes** 下有对应条目时，才会在库的版本之间改变。
