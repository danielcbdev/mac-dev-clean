# MacDevClean

Um aplicativo nativo para macOS que encontra armazenamento de desenvolvimento
que você pode recuperar — `node_modules`, saída de build, caches de pacotes,
dados derivados do Xcode, recursos do Docker, arquivos grandes em pastas que
você escolher —, explica o que cada item custa e move itens do sistema de
arquivos para a Lixeira.

[English](README.md)

> **Situação: build de desenvolvimento sem assinatura publicado; release
> assinado ainda não feito.**
> [`v1.0.1-unsigned`](https://github.com/danielcbdev/mac-dev-clean/releases/tag/v1.0.1-unsigned)
> é um pre-release real, disponível para download no GitHub. Não existe build
> assinado, notarização nem tap do Homebrew ainda. Tudo que foi medido diz
> onde foi medido; tudo que não foi verificado está declarado como não
> verificado.

## Instalar

Baixe a imagem de disco do [último release](https://github.com/danielcbdev/mac-dev-clean/releases/tag/v1.0.1-unsigned)
e rode:

```bash
curl -L -o MacDevClean.dmg \
  https://github.com/danielcbdev/mac-dev-clean/releases/download/v1.0.1-unsigned/MacDevClean-1.0.1-unsigned.dmg
curl -L -o MacDevClean.dmg.sha256 \
  https://github.com/danielcbdev/mac-dev-clean/releases/download/v1.0.1-unsigned/MacDevClean-1.0.1-unsigned.dmg.sha256
shasum -a 256 -c MacDevClean.dmg.sha256   # opcional, confirma o download
open MacDevClean.dmg
```

Arraste `MacDevClean.app` para `/Applications`. Este build é **sem assinatura e
não notarizado**, então a primeira abertura é recusada — **Control-clique no
app → Abrir**, depois confirme. Isso libera só esse aplicativo; não desative o
Gatekeeper. Detalhes completos, incluindo o que o app grava em disco e como
removê-lo: [docs/release/manual-install.md](docs/release/manual-install.md)
(em inglês).

### Compilando você mesmo

O mesmo artefato sem assinatura, compilado a partir do código-fonte em vez de
baixado:

```bash
bash scripts/build-local.sh --version 1.0.1 --output dist/local
bash scripts/verify-artifact.sh --app dist/local/MacDevClean.app --mode unsigned
bash scripts/package-dmg.sh --app dist/local/MacDevClean.app \
    --output dist/MacDevClean-1.0.1-unsigned.dmg
```

| | Sem assinatura, hoje | Assinado, não feito |
|---|---|---|
| Como obter | Baixando o release, ou compilando você mesmo | Um DMG publicado e notarizado |
| Gatekeeper | Recusa a primeira abertura; Control-clique → Abrir | Abre normalmente |
| Verificado por | `verify-artifact.sh --mode unsigned` | `--mode signed`, que nunca aceita assinatura ad hoc |
| Existe? | Sim — o pre-release acima | **Não.** Sem certificado, sem notarização |

O pipeline assinado está escrito e seus modos de falha são testados com
ferramentas falsas — sem credenciais não há assinatura; uma assinatura que falha
ou uma notarização rejeitada não produz artefato —, mas ele **nunca executou
contra a Apple**.
[docs/release/configuration.md](docs/release/configuration.md) (em inglês).

## O que ele não faz

Isso importa mais do que a lista de recursos.

- **Mover para a Lixeira não libera espaço.** O espaço volta quando você esvazia
  a Lixeira pelo Finder, o que este aplicativo nunca faz por você. A interface
  diz "Potencial de limpeza", nunca "recuperável", e mostra bytes movidos para a
  Lixeira, o valor informado pelo Docker e a variação observada de espaço livre
  como três números separados — nunca como um total único.
- **Ele não deixa sua máquina mais rápida.** Um cache limpo é reconstruído. O
  próximo build fica mais lento, não mais rápido. Nada aqui afirma o contrário.
- **Ele nunca esvazia a Lixeira e nunca chama `rm`, `rmdir` ou `removeItem`.**
  A limpeza no sistema de arquivos é `FileManager.trashItem` e nada mais — uma
  verificação estática e uma suíte comportamental garantem isso.
- **Uma varredura não seleciona nada.** Quem seleciona é você. Itens de risco
  alto não podem ser selecionados pela lista: ficam atrás de uma seção que você
  abre deliberadamente, e "selecionar tudo de risco baixo e médio" nunca os
  alcança.
- **Operações do Docker não são recuperáveis.** Elas são rotuladas como tal,
  confirmadas separadamente e restritas a recursos revisados por identificador.
- **Sem telemetria, sem rede, sem exceção de sandbox, sem helper privilegiado,
  sem agente em segundo plano, sem item de início de sessão.** Nenhuma fonte de
  produção usa API de rede, o portão falha se alguma aparecer, e o `otool -L`
  no binário compilado não lista nenhuma biblioteca de rede.

## O que ele detecta

A detecção exige evidência, nunca o nome de um diretório.

| Tipo | Exemplos | Evidência exigida |
|---|---|---|
| Artefatos de projeto | `node_modules`, `.turbo`, `dist`, `build` do Flutter, `.dart_tool` | Um manifesto legível no mesmo diretório; `dist` exige ainda um `tsconfig.json` declarando-o como saída, o Git ignorando-o e o Git não rastreando nada dentro dele |
| Caches globais | npm, yarn, pnpm, bun, pip, Cargo, Gradle, Homebrew, CocoaPods, pub, DerivedData e Archives do Xcode, iOS DeviceSupport, caches do CoreSimulator | Um local exato relativo à pasta pessoal, declarado pela regra. Sem correspondência por padrão, e nenhuma ferramenta é executada para perguntar onde fica seu cache |
| Arquivos grandes | Arquivos acima de um limite | Somente dentro de pastas que você escolheu explicitamente para esse recurso. Sempre risco alto, nunca pré-selecionados |
| Docker | Imagens, containers, volumes, cache de build | Um endpoint local verificado, argumentos em lista de permissão, nunca um shell |

`~/.gradle` inteiro, `~/.cargo/bin`, o Cellar do Homebrew,
`CoreSimulator/Devices` e SDKs são **excluídos deliberadamente**. O motivo de
cada regra, e de cada exclusão, está em
[docs/cleanup-rules.md](docs/cleanup-rules.md) (em inglês).

## Capturas de tela

**Não existem, e nenhuma foi inventada.** As capturas pertencem à suíte de
testes de interface, que compila mas nunca executou nesta máquina: sob o
XCUITest o aplicativo inicia sem expor janela à interface de acessibilidade.
Veja [docs/verification/05-interface.md](docs/verification/05-interface.md) para
a investigação e [docs/demo/README.md](docs/demo/README.md) para como produzi-las
a partir dos dados de fixture.

O ícone do aplicativo, desenhado por `scripts/make-appicon.swift`, está em
[MacDevCleanApp/Resources/Assets.xcassets/AppIcon.appiconset](MacDevCleanApp/Resources/Assets.xcassets/AppIcon.appiconset).

## Arquitetura

As dependências apontam para dentro. `Domain` importa apenas Foundation.

```text
             ┌──────────────────────────────────────────┐
             │              MacDevCleanApp              │
             │  SwiftUI · Observation · AppKit · OSLog  │
             └────────────────────┬─────────────────────┘
                                  │
   ┌───────────┬─────────────┬────┴────────┬──────────────┬─────────────┐
   │ Scanning  │   Cleanup   │ CleanupRules│DockerIntegra.│ Persistence │
   │           │             │             │              │  SwiftData  │
   └─────┬─────┴──────┬──────┴──────┬──────┴───────┬──────┴──────┬──────┘
         │            │             │              │             │
         └────────────┴─────────────┴──────┬───────┴─────────────┘
                                           │
                                    ┌──────┴──────┐
                                    │   Domain    │
                                    │ Foundation  │
                                    └─────────────┘
```

A autoridade de limpeza vive em `Cleanup` e em nenhum outro lugar. O executor
aceita apenas valores `ValidatedCleanupItem`, cujos inicializadores são internos
àquele módulo, de modo que nenhum outro alvo — inclusive a interface — consegue
construir um. Um script compila uma falsificação deliberada e **falha se ela
compilar**:

```bash
bash scripts/check-token-access.sh
```

As decisões, com as alternativas rejeitadas e suas consequências, estão em
[docs/adr/](docs/adr/) (em inglês).

## Stack técnica e práticas de engenharia

**Linguagem e concorrência.** Swift 6 em modo de linguagem estrito
(`.swiftLanguageMode(.v6)` em todos os alvos). Os alvos do core são
`nonisolated` por padrão — o próprio padrão do Swift 6, mantido explícito em
vez de herdado — e só a camada de app opta por `@MainActor`, escrito
explicitamente em vez de assumido.

**Frameworks — zero dependências de terceiros.** `Package.resolved` não tem
nenhuma entrada. Tudo é nativo da Apple: SwiftUI + `Observation` para a
interface (sem Combine, sem `ObservableObject` legado), AppKit só onde o
SwiftUI não tem equivalente, `SwiftData` para persistência local,
`CryptoKit` para hash de conteúdo, `OSLog` para logging.

**Arquitetura modular.** Um pacote Swift local (`Packages/MacDevCleanCore`)
dividido em seis alvos — `Domain`, `CleanupRules`, `Scanning`, `Cleanup`,
`DockerIntegration`, `Persistence` — com dependências apontando só para
dentro; `Domain` importa apenas Foundation. Isso não é só documentado: a
autoridade de limpeza é uma fronteira em nível de tipo
(`ValidatedCleanupItem` tem inicializador interno, então só `Cleanup`
consegue construir um), e `scripts/check-token-access.sh` compila uma
falsificação deliberada e falha o build se ela *compilar*.

**Testes.** Dois frameworks por design — XCTest para testes de app e de
interface, o framework `Testing` (`@Test`) mais novo do Swift para as suítes
do pacote — escritos test-first, vermelho antes de verde, um caso
comportamental de cada vez. Todo caminho destrutivo (Lixeira, Docker) é
exercitado contra fixtures que o próprio teste cria, uma Lixeira falsa e um
cliente Docker falso, então a suíte nunca toca uma máquina real.

**Análise estática, feita à mão.** `scripts/check-policy.sh` prova que o
Swift de produção nunca chama `rm`, `rmdir`, `removeItem` ou uma API de rede
— `grep` POSIX puro, deliberadamente não `ripgrep`, porque uma ferramenta
opcional ausente que silenciosamente zera um portão é pior que nenhum
portão. `scripts/check-localization.swift` é um script Swift avulso (sem
pacote, sem alvo) que verifica se toda chave de string existe nos dois
idiomas com placeholders de plural correspondentes e sem entradas obsoletas.
O `.swift-format` (100 colunas, no máximo uma linha em branco) roda a partir
do próprio toolchain do Xcode fixado — nada baixado, nada flutuante.

**CI/CD — 3 workflows do GitHub Actions, todos fixados, todos com privilégio
mínimo.**
- `CI` — portão completo em todo PR e push para `main`/`develop`,
  `permissions: contents: read`, nenhum segredo ao alcance.
- `Performance` — só manual (`workflow_dispatch`); mede desempenho de
  varredura sem afirmar um limite de tempo de parede, porque um número de um
  runner compartilhado não é comparável ao de um laptop, e um limite
  irreprodutível só vira um teste instável.
- `Release` — três estágios (teste → assinar e notarizar → publicar); o
  estágio de assinatura só roda dentro de um ambiente `release` protegido
  com revisor obrigatório, e o estágio de publicação é o único job de todo o
  pipeline com permissão de escrita. Toda Action de terceiros é fixada num
  commit SHA imutável, nunca uma tag flutuante.

**Engenharia de release.** `scripts/release-preflight.sh` recusa um release
assinado nomeando exatamente quais segredos estão faltando — nunca um valor,
um tamanho ou um prefixo. `scripts/sign-notarize.sh` cria um keychain
descartável por execução e garante sua remoção em qualquer caminho de saída,
inclusive falha. `scripts/render-cask.rb` gera o Cask do Homebrew a partir
de cinco argumentos validados — nunca interpolação de string em código Ruby
— e sua própria suíte de testes de contrato garante que um Cask nunca é
gerado para um artefato que não está de fato publicado.

**Documentação como engenharia, não um apêndice.** 6 ADRs registram as
alternativas *rejeitadas* e suas consequências, não só a decisão tomada. Os
documentos de verificação em `docs/verification/` registram o comando real,
o código de saída e o toolchain usados — uma verificação que não rodou é
registrada como não executada, nunca contada silenciosamente como aprovada.

**Fluxo de Git.** Conventional Commits do início ao fim (80 commits,
`feat:`, `fix:`, `merge:`, `chore:`, `docs:`). O ciclo de vida de branches é
`main → develop → feat/*`, mesclado de volta com `--no-ff` para preservar o
histórico de cada feature em vez de esmagá-lo.

## Requisitos

| | |
|---|---|
| Executa em | macOS 14 ou posterior — **um alvo de implantação, não uma observação**; só havia macOS 27.0 disponível |
| Compilado com | Xcode 27.0 (27A266a), Swift 6.4 |
| Arquiteturas | `arm64` e `x86_64` — a fatia Intel **nunca foi executada em hardware Intel** |
| Dependências | Nenhuma. Somente frameworks da Apple |

## Compilar e testar

```bash
git clone <este repositório>
cd mac-dev-clean
bash scripts/verify.sh
```

O portão executa os testes do pacote, os testes de unidade do aplicativo, os
testes de interface, um build Release sem assinatura, a verificação de
autoridade de limpeza, o verificador de localização e suas fixtures, os
contratos dos scripts de release, a verificação estática de política e suas
fixtures, o linter e uma verificação de espaços em branco. Ele sai com 0 apenas
se tudo que executou passou.

Quando a suíte de interface não puder executar, defina
`MACDEVCLEAN_SKIP_UI_TESTS=1`. O portão então imprime **MISSING GATE**, muda sua
última linha e não é uma aprovação:

```bash
MACDEVCLEAN_SKIP_UI_TESTS=1 bash scripts/verify.sh
```

Suítes individuais:

```bash
swift test --package-path Packages/MacDevCleanCore
swift test --package-path Packages/MacDevCleanCore --filter ScanPerformanceTests
bash scripts/tests/release-contract-tests.sh
```

Todo teste destrutivo roda sobre fixtures que ele mesmo criou, com Lixeira falsa
e Docker falso. Nenhum teste toca seus caches, sua Lixeira ou seus recursos do
Docker.

## Limitações conhecidas

- **A suíte de testes de interface nunca executou.** 21 testes compilam; nenhum
  é apresentado como aprovado. Sem capturas de tela, sem verificação com
  VoiceOver, sem medição de desempenho em execução real.
- **Nunca executado em macOS 14 nem em hardware Intel.**
- **Sem assinatura, sem notarização, sem tap do Homebrew.** Um build de
  desenvolvimento sem assinatura é publicado como pre-release no GitHub,
  [`v1.0.1-unsigned`](https://github.com/danielcbdev/mac-dev-clean/releases/tag/v1.0.1-unsigned).
- **Sem revisão independente.** Ninguém mais revisou este trabalho.
- **A migração de esquema nunca foi exercitada**, porque existe apenas uma
  versão de esquema.
- **Licenciado sob MIT.** Veja `LICENSE`.

Evidências completas, por marco, com comandos e códigos de saída:
[docs/verification/](docs/verification/). O que ainda exige uma pessoa, hardware
real ou credenciais:
[docs/testing/manual-release-checks.md](docs/testing/manual-release-checks.md).

## Documentação

A documentação técnica é mantida em inglês, conforme o contrato de engenharia.

| | |
|---|---|
| Contrato de engenharia | [AGENTS.md](AGENTS.md) |
| Regras de limpeza | [docs/cleanup-rules.md](docs/cleanup-rules.md) |
| Decisões | [docs/adr/](docs/adr/) |
| Segurança | [docs/security/](docs/security/) |
| Layout da interface | [docs/design/layout.md](docs/design/layout.md) |
| Evidências de teste | [docs/testing/](docs/testing/), [docs/verification/](docs/verification/) |
| Release | [docs/release/](docs/release/) |
| Mudanças | [CHANGELOG.md](CHANGELOG.md) |

Copyright © 2026 Daniel Carvalho. O ícone e todo o código-fonte deste
repositório são trabalho original.
