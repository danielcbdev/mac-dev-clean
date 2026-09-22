# MacDevClean

Um aplicativo nativo para macOS que encontra armazenamento de desenvolvimento
que você pode recuperar — `node_modules`, saída de build, caches de pacotes,
dados derivados do Xcode, recursos do Docker, arquivos grandes em pastas que
você escolher —, explica o que cada item custa e move itens do sistema de
arquivos para a Lixeira.

[English](README.md)

> **Situação: desenvolvimento concluído, nunca publicado.** Não existe release,
> build assinado, tap do Homebrew nem tag. Tudo que foi medido diz onde foi
> medido; tudo que não foi verificado está declarado como não verificado.

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

## Instalar

Compile você mesmo e abra o artefato sem assinatura:
[docs/release/manual-install.md](docs/release/manual-install.md).

```bash
bash scripts/build-local.sh --version 1.0.0 --output dist/local
bash scripts/verify-artifact.sh --app dist/local/MacDevClean.app --mode unsigned
bash scripts/package-dmg.sh --app dist/local/MacDevClean.app \
    --output dist/MacDevClean-1.0.0-unsigned.dmg
```

| | Sem assinatura, hoje | Assinado, não feito |
|---|---|---|
| Como obter | Compilando você mesmo | Um DMG publicado e notarizado |
| Gatekeeper | Recusa a primeira abertura; Control-clique → Abrir | Abre normalmente |
| Verificado por | `verify-artifact.sh --mode unsigned` | `--mode signed`, que nunca aceita assinatura ad hoc |
| Existe? | Sim | **Não.** Sem certificado, sem notarização, sem release |

O pipeline assinado está escrito e seus modos de falha são testados com
ferramentas falsas — sem credenciais não há assinatura; uma assinatura que falha
ou uma notarização rejeitada não produz artefato —, mas ele **nunca executou
contra a Apple**.
[docs/release/configuration.md](docs/release/configuration.md).

## Limitações conhecidas

- **A suíte de testes de interface nunca executou.** 21 testes compilam; nenhum
  é apresentado como aprovado. Sem capturas de tela, sem verificação com
  VoiceOver, sem medição de desempenho em execução real.
- **Nunca executado em macOS 14 nem em hardware Intel.**
- **Sem assinatura, sem notarização, sem release, sem tap do Homebrew, sem tag.**
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
