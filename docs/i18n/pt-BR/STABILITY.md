**Idiomas:** [English](../../STABILITY.md) · Português (BR) · [Español](../es/STABILITY.md) · [中文](../zh-CN/STABILITY.md)

> Tradução de [STABILITY.md](../../STABILITY.md). Em caso de divergência, vale a versão em inglês.

# Política de estabilidade

Em que você pode confiar entre versões do proptest, o que pode mudar e como cada mudança é anunciada. Requisito RL15; garantido por golden tests (Q7); motivos na [ADR-0015](../../decisions/0015-stability-policy.md).

**Em resumo:** dentro de uma versão minor (1.0.0, 1.0.1, 1.0.2, ...) a mesma seed produz os mesmos valores, a mesma exploração e o mesmo contraexemplo. Mudanças em qualquer coisa disso só acontecem numa nova versão minor, e cada uma é listada no CHANGELOG em **Generation changes**.

## Por que isso importa para você

Uma seed é uma promessa de que uma execução pode ser repetida. Se a geração mudasse numa versão patch, uma `PROPTEST_SEED` copiada ontem de uma falha no CI poderia repetir outra coisa hoje, depois de uma atualização inocente de dependência. Seus próprios testes de regressão que fixam uma seed (`initSettings(seed = 42)`) começariam a verificar outras entradas sem nada mudar no seu código.

A promessa oposta, "os valores nunca mudam", congelaria a biblioteca: casos de borda melhores, geradores mais rápidos e shrinking mais esperto mudam valores. A política fica no meio: mudanças são permitidas, mas só numa fronteira de versão que você escolhe cruzar, e sempre anunciadas.

<a id="what-stays-the-same-within-a-minor-version"></a>
## O que continua igual dentro de uma versão minor

Com a mesma versão do proptest (incluindo versões patch), o mesmo código de teste e as mesmas configurações:

| O quê | Cobre |
|---|---|
| **Valores gerados** | todo gerador nativo (`x in T` para todo tipo suportado, objetos derivados, case objects, `distinct`, `ref`, contêineres), todo combinador, e as primitivas de sorteio que seus próprios geradores usam (`drawInt`, `drawBool`, `drawIndex`, `drawFloat`, ...) |
| **A execução** | como a seed da execução vira a seed de cada propriedade (a partir do seu `name`), como os tamanhos crescem ao longo da execução, viés de borda, constantes mineradas e dicas `near`, swarm testing, quantos casos são descartados |
| **Sequências stateful** | quais comandos rodam, em que ordem, com quais argumentos |
| **Shrinking** | o caminho que o shrinker percorre e o contraexemplo mínimo relatado, para toda falha encontrada |
| **Banco de falhas** | o formato do arquivo (`proptest-db 1`) e como as entradas são indexadas |
| **Relatório JSON** | o significado de cada campo do `format` 1 |

Isso vale em toda plataforma e build que o CI testa: Linux, macOS e Windows; debug e release; `--mm:orc` e `--mm:arc`; threads ligadas e desligadas; Nim 2.2.4 (o Nim devel também é testado, como falha permitida: uma mudança no compilador poderia quebrá-lo antes que uma versão avise). O gerador aleatório e o hash são próprios da biblioteca, verificados contra vetores de referência, então nada depende do `random` ou do `hash` da biblioteca padrão, que podem mudar entre versões do Nim.

### O que "o mesmo código de teste" significa

Seu código decide parte do que é gerado, então algumas edições suas mudam valores mesmo com a mesma versão da biblioteca e a mesma seed:

- **Mover uma propriedade.** Seu nome padrão é `file:line`, e sua seed vem do nome. Dê a ela um `name` para manter a seed quando as linhas mudam de lugar.
- **Literais inteiros no arquivo de teste.** Eles são propostos como valores de fronteira (`mineConstants`). Acrescentar um literal ao arquivo pode mudar o que outras propriedades dele geram. `mineConstants = false` torna uma propriedade independente do seu arquivo.
- **Seus próprios geradores** e a ordem em que sorteiam.
- **Configurações que moldam as entradas:** `cases`, `maxSize`, `edgeBias`, `maxDepth`, `maxSteps`, `swarm`, `mineConstants`, inclusive vindas do ambiente (`PROPTEST_CASES`).

[CONFIGURATION.md](CONFIGURATION.md#what-a-replay-needs) lista o que uma repetição precisa.

## O que pode mudar em qualquer versão

Estes itens não são cobertos: depender deles num teste tornaria o teste frágil.

- **O relatório em texto**: redação, layout, quais estatísticas e avisos são impressos. Leia o [relatório JSON](README.md#json-report-for-ci) em vez disso.
- **Como os valores são impressos** (`show`, `showCode`) quando a mudança os torna mais claros ou mais corretos. Um bloco `replayCommands` impresso por uma versão mais antiga continua sendo Nim válido, mas uma versão mais nova pode imprimi-lo de outra forma.
- **Health checks e avisos**: novos checks, outros limiares.
- **Tudo o que depende de tempo**: `deadline`, `timeBudget`, `shrinkTimeBudget`, o check de geração lenta. Uma máquina mais rápida roda mais casos dentro de um orçamento de tempo.
- **Desempenho**: o número de execuções de shrinking para chegar ao mesmo contraexemplo pode cair (o contraexemplo em si continua o mesmo dentro de uma versão minor).
- **API nova**: novos geradores, combinadores, configurações, campos em `PropertyResult` e novos campos no relatório JSON. Acrescentar um campo nunca muda `format`.

## Como as mudanças são anunciadas

A entrada de cada versão no CHANGELOG agrupa as mudanças por tipo:

| Título | Contém | Permitido em |
|---|---|---|
| **Added**, **Fixed**, **Changed** | API nova, correções de bugs, mudanças no relatório ou na documentação | qualquer versão |
| **Generation changes** | qualquer coisa de [O que continua igual](#what-stays-the-same-within-a-minor-version): valores, exploração, shrinking, formatos de arquivo | uma versão minor (x.y.0) |
| **Breaking** | mudanças de API que fazem o código parar de compilar ou mudar de significado | uma versão major (x.0.0) |

Uma entrada em **Generation changes** diz o que muda, para quais geradores ou configurações, e se as seeds salvas e as entradas do banco de falhas continuam se repetindo. As mudanças de geração são agrupadas: várias entram juntas numa versão minor, para que as seeds parem de se repetir uma vez só, e não a cada melhoria.

Uma mudança **Breaking** de API é precedida, quando possível, por uma versão `{.deprecated.}` da API antiga por pelo menos uma versão minor, com uma mensagem que nomeia a substituta.

Uma correção de bug que muda valores (um gerador que nunca conseguia produzir algum valor que deveria) continua sendo uma mudança de geração: ela espera a próxima versão minor, a menos que o bug torne a biblioteca inutilizável, caso em que a versão patch diz isso em **Generation changes**.

## Quando você atualiza

- **Versão patch (1.0.1 → 1.0.2):** nada a fazer. Seeds, testes fixados e falhas salvas continuam funcionando.
- **Versão minor (1.0 → 1.1):** leia **Generation changes**. Seeds impressas pela versão antiga repetem outras entradas: repita falhas antigas do CI com a versão antiga. Propriedades com `seed` fixa passam a verificar outras entradas, o que normalmente está tudo bem; revise qualquer teste que afirme os valores exatos que uma seed produz. O banco de falhas não precisa de nada: entradas que não cabem mais nos geradores são descartadas, entradas que agora passam são esquecidas depois de três execuções, e um bug real continua falhando.
- **Para manter uma entrada específica para sempre**, não dependa de uma seed: escreva-a com `example(...)` ou, para máquinas de estado, cole o bloco `replayCommands` num teste. Esses não dependem da geração.

## Como isso é garantido

- **Golden snapshot** (`tests/t_golden.nim`, `tests/golden/snapshot.txt`): roda 51 propriedades pelo pipeline inteiro (todo tipo e combinador, tipos derivados, constantes mineradas, viés de borda, tamanhos, swarm, shrinking de vários bugs de referência, uma máquina de estado, o arquivo do banco de falhas) e compara um hash de todo valor gerado e de todo candidato de shrinking, além de amostras legíveis, com o snapshot commitado. O CI o roda em toda plataforma e modo de build acima.
- **Vetores de referência** (`tests/t_prng.nim`): o gerador aleatório e o hash contra o código de referência de seus autores e os vetores oficiais do FNV-1a.
- **Processo**: quando o teste do snapshot falha, a mensagem diz isso. Uma mudança intencional é registrada com `nimble golden` e uma entrada no CHANGELOG em **Generation changes** no mesmo commit; qualquer outra coisa é uma regressão a corrigir.

O teste do snapshot é a prova de que uma versão patch cumpre sua promessa: se ele passa no commit da versão, a versão gera exatamente o que a anterior da mesma versão minor gerava.
