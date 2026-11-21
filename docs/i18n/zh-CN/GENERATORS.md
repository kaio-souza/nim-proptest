**语言：** [English](../../GENERATORS.md) · [Português (BR)](../pt-BR/GENERATORS.md) · [Español](../es/GENERATORS.md) · 中文

> 本文译自 [GENERATORS.md](../../GENERATORS.md)。如有出入，以英文版为准。

# 编写生成器

大多数属性不需要生成器代码：类型会根据其定义自动生成。本指南介绍哪些是自动的、何时需要编写生成器，以及每个生成器都必须遵守的唯一规则。所有代码片段都在 [`examples/generators.nim`](../../../examples/generators.nim) 中，并在 CI 中编译运行。设计：[ADR-0013](../../decisions/0013-derived-generators.md)。

## 1. 什么都不用写

`forAll(x in T)` 适用于：

| `T` | 生成内容 | 收缩方向 |
|---|---|---|
| 整数、`range`、浮点数、`bool`、`char`、枚举 | 整个取值域，经常取边界值 | 0、`false`、第一个值 |
| `string`、`seq`、`array`、`set`、元组、`Option` | 逐个元素 | 更短、元素更简单、`none` |
| `Table`、`OrderedTable`、`HashSet` | 由其类型生成的条目 | 更少、更简单的条目 |
| **对象** | 逐字段，**包括私有字段** | 每个字段都取最简单值 |
| **case object** | 一个分支，然后是它的字段 | 第一个分支 |
| **`distinct` 类型** | 由其基类型生成 | 基类型的最简单值 |
| **`ref` 对象** | `nil` 或一个新对象 | `nil` |
| **递归类型** | 由 `maxDepth`（默认 5）限定的树 | 最小的树 |

```nim
type
  Currency = enum usd, eur, brl
  Payment = object
    id: int64
    amount: int
    currency: Currency
    note: string
  EventKind = enum paid, refunded, cancelled
  Event = object
    at: int
    case kind: EventKind
    of paid: payment: Payment
    of refunded: refundOf: int64
    of cancelled: reason: string
  Expr = ref object
    case op: char
    of '+', '*': lhs, rhs: Expr
    else: value: int

forAll(p in Payment, e in Event, x in Expr): ...
```

其他模块中的类型无需导出字段也能使用。如果某个字段的类型没有生成器（`proc`、`ptr`、锁），编译会停止，并给出指明该字段的消息。判别字段为 `range` 类型的 case object 在 Nim 2.2.4 下无法推导，编译器消息会说明这一点：改用枚举，或编写 `arbitrary`。

探索期间递归数据是有界的：`ref` 字段越深越常为 `nil`，嵌套集合也会变短，所以树保持较小（`initSettings(maxDepth = ...)` 可改变这个界限）。收缩不受影响。

## 2. 随机字段会构成无效对象时：编写 `arbitrary`

推导会独立地填充每个字段。当字段之间必须一致（开始早于结束、总额等于各行之和、某个 ID 必须存在于列表中）时，为该类型编写 `arbitrary`。它总是优先于推导，所有使用该类型的属性都会用到它。

```nim
type DateRange = object
  first, last: int            # invariant: first <= last

proc arbitrary(src: ChoiceSource; t: typedesc[DateRange]): DateRange =
  let first = src.drawInt(0, 36_500)
  let length = src.drawInt(0, 365)
  DateRange(first: first, last: first + length)
```

**构造有效值；不要过滤无效值。** `filter` 和 `assume` 会丢弃用例。拒绝率稍高一点，运行就会变慢，然后会停止并给出建议这样做的消息。抽取 `length` 而不是 `last`，就能让每个值都有效。

## 3. 唯一的规则：更小的选择必须对应更简单的值

生成器从不直接看到随机数，只看到**选择**：从选择源抽取的无符号整数。收缩会让记录下来的选择变得更小、更短，然后重放它们（[ADR-0001](../../decisions/0001-integrated-shrinking-on-choice-sequences.md)）。要让这样得到更简单的值，选择 0 必须对应最简单的值，更小的选择对应更简单的值。每个抽取原语都已遵守这条规则：

| 原语 | 选择 0 给出 |
|---|---|
| `drawInt(lo, hi)` | `lo .. hi` 中最接近 0 的值 |
| `drawBool()` | `false` |
| `drawIndex(n)` | 0：把最简单的备选放在第一位 |
| `drawFloat`、`drawFloatRange` | 0.0 |
| `initMany` + `more` | 不再有元素 |
| `drawRune()` | `'a'` |

所以这条规则归结为你的两个选择：

- **把最简单的备选放在第一位**：`elements([common, rare])`、`frequency([(9, usual), (1, unusual)])`、第一个值就是默认值的枚举。
- **抽取能让值有效的东西**，就像上面的 `length`，而不是随意抽取然后再修正：一次"修正"可能把更小的选择变成更大的值。

## 4. 生成器值：组合子

当类型不够用时（一个范围、一个字母表、一种分布），传入生成器值而不是类型：

```nim
let prices = frequency([(8, ints(1, 10_000)), (1, constant(0)), (1, ints(1_000_000, 10_000_000))])
let usernames = identifiers(maxLen = 12)
let labels = tables(identifiers(8), ints(0, 99), maxLen = 5)

forAll(price in prices, user in usernames, l in labels): ...
```

| 组合子 | 值 |
|---|---|
| `ints(lo, hi, near = [...])` | 整数；`near` 列出你领域中需要经常尝试的边界 |
| `frequency([(w, g), ...])` | 按权重选出的某个生成器 |
| `elements([...])`、`oneOf(...)`、`constant(v)` | 固定的选择 |
| `strings(alphabet, ...)`（例如 `strings(alphanumeric, ...)`）、`identifiers(...)`、`unicodeStrings(...)` | 文本，包括覆盖所有平面的合法 UTF-8 |
| `seqs`、`tables`、`hashSets`、`optionals` | 由生成值组成的容器 |
| `uniqueSeqs(g, ...)`、`sortedSeqs(g, ...)` | 元素互不相同或升序排列的序列 |
| `sized(proc(n: int): Gen[T] = ...)`、`g.resize(n)` | 依赖当前规模的生成器，或固定规模 |
| `g.map(f)`、`g.filter(p)`、`g.flatMap(f)` | 变换（收缩会穿过它们） |
| `recursive(base, extend, maxDepth)` | 树：每一层要么是 `base`，要么再深一层 |
| `newGen(proc(src: ChoiceSource): T = ...)` | 任何东西，基于抽取原语构建 |

递归生成器接收下一层的生成器：

```nim
let exprs = recursive(leaf(), proc(inner: Gen[Expr]): Gen[Expr] =
  newGen(proc(src: ChoiceSource): Expr =
    let times = src.drawBool()           # false ('+') is the simpler one
    let (l, r) = (inner.generate(src), inner.generate(src))
    if times: Expr(op: '*', lhs: l, rhs: r) else: Expr(op: '+', lhs: l, rhs: r)))
```

### 元素互异的集合与有序集合

有两种形态出现得足够频繁，所以有专门的生成器。两者的收缩方式都与 `seqs` 相同，并在收缩过程中保持其形态：

```nim
forAll(ids in uniqueSeqs(ints(1, 10_000), maxLen = 20)):   # no duplicates
  check buildIndex(ids).len == ids.len

forAll(xs in sortedSeqs(ints(), minLen = 1)):              # ascending
  check lowerBound(xs, xs[0]) == 0                        # std/algorithm
```

当某个值与之前的值重复时，`uniqueSeqs` 会重新抽取，每个元素最多 `maxTries`（100）次，之后像 `filter` 一样丢弃该用例。不同值太少时（`uniqueSeqs(bools(), minLen = 3)`），属性会放弃并说明原因。`sortedSeqs` 在生成后排序，所以从不丢弃。优先使用它们，而不是会[放弃](TROUBLESHOOTING.md#gave-up-after-n-passing-cases)的 `assume(xs.isSorted)`。

### 规模：`sized` 和 `resize`

规模从第一个用例的 0 增长到最后一个用例的 `maxSize`。内置集合和整数已经遵循它；`sized` 把它交给你自己的生成器，`resize` 为某个生成器固定它：

```nim
# A square matrix whose side follows the size.
let matrices = sized(proc(n: int): Gen[seq[seq[int]]] =
  let side = max(1, n div 10)
  seqs(seqs(ints(0, 9), side, side), side, side))

# Short lists, whatever the size of the case.
let shortLists = gen(seq[int]).resize(3)
```

`sized` 看到的规模会随用例一起记录，因此收缩和重放看到的是同一个规模（收缩可能会降低它，从而让值更简单）。像上面那样，把它用作上界或比例。

## 5. 固定已知用例

`example(...)` 在任何随机用例之前运行固定的值，每个变量一个。把它用于绝不能再出现的回归，或者规格中点名的用例：

```nim
forAll(user in usernames, example("root"), example("a")):
  check user.len >= 1
```

失败也会被保存在 `.proptest/db/` 中，并在后续运行中优先重放，直到连续通过三次为止（[ADR-0014](../../decisions/0014-failure-database-and-examples.md)）。

## 6. 打印值

报告在存在 `$` 时用它打印输入，有状态报告则把命令参数打印为 Nim 代码（`showCode`）：对象打印为 `Payment(id: 0, amount: 0, ...)`，表打印为 `{1: "a"}.toTable`，`ref` 值在为空处打印 `nil`。如果某个类型的 `$` 不可读，或者在报告将被粘贴的地方看不到它的构造器，就为它重载 `show` 或 `showCode`。
