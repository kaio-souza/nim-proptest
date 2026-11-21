**语言：** [English](../../PATTERNS.md) · [Português (BR)](../pt-BR/PATTERNS.md) · [Español](../es/PATTERNS.md) · 中文

> 本文译自 [PATTERNS.md](../../PATTERNS.md)。如有出入，以英文版为准。

# 属性模式手册

基于属性的测试中，难点很少在库本身，而在于：当你无法为随机输入写出预期输出时，决定**检查什么**。这些模式覆盖了大多数真实的属性。每个模式在 [`examples/patterns.nim`](../../../examples/patterns.nim) 中都有一个能通过的版本，并在 CI 中编译运行。

## 往返（round trip）

如果一个函数能撤销另一个函数，把它们组合起来就会得到原输入。适用于序列化、解析、编码、压缩和转换。

```nim
forAll(xs in seq[int]):
  check decode(encode(xs)) == xs
```

它能发现精度丢失、转义 bug，以及手写示例会漏掉的空输入或边界输入（`@[]`、`low(int)`）。

## 预言（参考实现）

把代码与一个更慢但显然正确的版本比较：优化过的函数对比朴素循环，新实现对比旧实现，缓存对比直接计算。

```nim
forAll(xs in seq[int]):
  check fastSum(xs) == oracleSum(xs)
```

有状态测试就是把同一模式应用到一系列操作上：模型就是预言（[STATEFUL.md](STATEFUL.md)）。

## 不变量

即使不知道确切输出，也知道它的某些性质：排序保持长度并使元素有序；平衡树保持平衡；总额保持非负。

```nim
forAll(xs in seq[int]):
  let s = xs.sorted
  check s.len == xs.len
  for i in 1 ..< s.len: check s[i - 1] <= s[i]
```

## 幂等性

执行两次操作与执行一次相同：规范化、去重、格式化、设置标志、HTTP `PUT`。

```nim
forAll(xs in seq[int]):
  check dedupe(dedupe(xs)) == dedupe(xs)
```

## 蜕变关系

你不知道 `f(x)`，但知道 `x` 以已知方式变化时它如何变化。添加一个元素会把它加到总和里，打乱顺序不改变集合，缩放输入会缩放线性输出。

```nim
forAll(xs in seqs(ints(-1000, 1000)), k in ints(-1000, 1000)):
  check oracleSum(xs & @[k]) == oracleSum(xs) + k
```

当关系可能溢出时，限制取值范围：溢出是真实的发现，但不是这个属性关心的那一个。

## 永不崩溃

最弱但往往最有成效的属性：对于任何输入，代码要么返回，要么抛出它在文档中声明的错误。`Defect`（索引越界、溢出、nil 访问）和意外异常都算失败。

```nim
forAll(s in string):
  try: discard parseJson(s)
  except JsonParsingError, ValueError: discard
```

## 边界

bug 藏在定义域发生变化的地方：最后一次重试、恰好 1000 毫秒的超时、容量为 3。整数生成器已经会尝试 `0`、`1`、`-1` 和类型极限。对于你自己的边界：

- **常量会被自动挖掘。** 属性中用到的整数字面量和 `const` 值，以及测试文件中任何位置的整数字面量，会在探索期间以 `v - 1`、`v` 和 `v + 1` 的形式被提议（[ADR-0012](../../decisions/0012-bug-finding-power.md)）。`initSettings(mineConstants = false)` 可将其关闭。
- 当边界来自别处（另一个模块、配置文件）时，用 `ints(lo, hi, near = [...])` **显式说明**：

```nim
forAll(attempt in ints(0, 100, near = [maxRetries])):
  if attempt < maxRetries: check backoffMs(attempt) >= 100
  else: check backoffMs(attempt) == -1
```

两者都不会改变收缩：报告的反例仍然是最简单的那个。

## 覆盖率：确保有意思的用例真的出现

属性通过并不能说明从未生成过的输入怎样。`classify` 显示分布；`cover` 把要求变成检查：

```nim
forAll(initSettings(cases = 300), xs in seq[int]):
  cover(5.0, xs.len == 0, "empty")
  cover(20.0, xs.len >= 10, "ten or more")
  check ...
```

```
Property 'patterns.nim:69' passed 300 cases.
  Statistics (300 cases):
     14.0%  empty  (cover: 5.0% required)
     61.0%  ten or more  (cover: 20.0% required)
```

只有当观察到的比例**可信地**低于要求（95% Wilson 区间的上界）时，`cover` 才会让属性失败。用例太少无法确定时，它会打印警告并建议调高 `cases`。`label($x.kind)` 按计算出的文本统计用例。在状态机中，`cover` 统计的是序列，报告还会列出每个命令运行了多少次、被其前置条件阻止了多少次。

## 难以找到属性时

- 从**永不崩溃**开始，再加上**往返**和**不变量**：它们不需要预期值。
- 如果你有两个实现，或者一个旧版本和一个新版本，用**预言**。
- 如果系统有状态（缓存、队列、连接、熔断器），用**状态机**。
- 如果属性只对某些输入成立，就直接生成这些输入。`assume` 和 `filter` 会丢弃用例，丢弃太多会让运行停止并给出说明。
