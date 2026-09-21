# MacDevClean — pacote de implementação

Copie **o conteúdo desta pasta** para a pasta vazia que será a raiz do projeto. Os caminhos dos documentos são relativos à raiz e continuarão válidos depois da cópia.

Este pacote contém a especificação aprovada, esclarecimentos técnicos, contratos dos módulos, nove planos sequenciais e instruções de execução. Ele não contém o aplicativo implementado. As referências visuais e o script são materiais de apoio; não são instruções executáveis.

## Como começar

1. Confira os arquivos em `docs/references/`. A imagem usa o nome antigo; o produto se chama MacDevClean.
2. Leia `docs/superpowers/specs/2026-09-21-implementation-clarifications.md`: registra ajustes de precisão, incluindo Lixeira versus espaço realmente liberado e risco de dados em containers parados.
3. Cole o prompt abaixo no agente aberto na pasta do projeto.

## Prompt para o agente

> Desenvolva o MacDevClean conforme este pacote. Comece lendo START-HERE.md, a spec de produto, os esclarecimentos técnicos, os contratos e docs/superpowers/plans/2026-09-21-00-execution.md. Siga os planos 01 a 09 na ordem.
>
> Primeiro crie AGENTS.md e os adaptadores para Claude, Cursor e Copilot conforme o plano 01. Preserve os documentos e as referências. Inicialize o Git na main, caso ainda não exista, e faça o commit inicial. Use develop, branches de feature e merges sem fast-forward conforme o guia. Faça commits pequenos, testes e revisão real dos diffs. Não invente resultados, autores, revisões, datas, PRs ou métricas.
>
> Execute autonomamente as tarefas locais autorizadas. Use superpowers:executing-plans quando disponível. Se uma skill não estiver instalada, siga as tarefas e verificações explícitas destes arquivos e informe a limitação. Não introduza um novo processo de aprovação a cada tarefa ou merge local. Use tarefas concluídas, testes e docs/progress.md para retomar o trabalho.
>
> Entregue um app desktop funcional, testado, com referências visuais respeitadas, documentação bilíngue e artefato local instalável. Não execute limpeza em meus dados reais para validar o app. Faça testes destrutivos apenas em fixtures pertencentes ao teste, usando adaptadores falsos. Docker real exige minha autorização específica e ambiente descartável.
>
> Eu autorizo criação de arquivos, branches, commits, merges locais e builds no repositório deste projeto. Publicação, push, criação de repositórios remotos, assinatura com minhas credenciais e instalação no meu Mac precisam de autorização específica quando chegar a hora. Se faltar conta Apple, remote ou secrets, termine tudo que pode ser entregue localmente e documente exatamente os passos externos pendentes. Não crie a tag final v1.0.0 se os critérios da versão ainda estiverem pendentes.
>
> Confirme decisões rotineiras pelos contratos, requisitos e testes. Só me pergunte quando houver uma escolha de produto sem resposta nos documentos, autorização externa necessária ou bloqueio que não possa ser resolvido localmente. No final, informe o que foi entregue, evidências de validação e limitações remanescentes.

## Referências incluídas

Incluí a imagem já gerada para poupar a etapa manual. Adicione o seu script em `docs/references/mac_cleanup_reference.sh`: o arquivo original deixou de estar disponível no caminho informado durante a preparação do pacote. Ele é opcional para a implementação, pois as regras já estão descritas nas specs. O script pode conter limitações conhecidas de identificação de caminhos; nunca deve ser executado pelo app.

## Resultado esperado

Um clone precisa compilar e executar sem conta Apple paga. O pipeline de release assinado fica configurado, mas a publicação verificada depende de conta, certificados, secrets e autorização. A primeira versão deve estar utilizável pelo Finder, com interface SwiftUI, e não depender de uma CLI do próprio produto.

A especificação de produto foi aprovada nesta conversa. Os planos entregues ficam disponíveis para sua revisão; este pacote não inicia a implementação por conta própria.
