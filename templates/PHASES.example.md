# Plano de fases — exemplo do Loop Enginner

Contrato validado no preflight:

- pelo menos um heading `## Phase N: <titulo>`;
- `### Phase N.M:` e sub-fase da fase N (nao vira sessao propria);
- qualquer outro `## ` encerra a fase anterior;
- com o gate 3 ligado (default), toda fase precisa de ao menos uma task
  `- [ ]` — sem checkbox a verificacao independente nao tem o que checar;
- cada fase roda numa sessao NOVA da engine: o texto da fase precisa ser
  auto-contido (contexto, criterio de aceite e como testar).

Troque o conteudo abaixo pelo seu plano e rode:

## Phase 1: Fundacao do exemplo

Objetivo: criar a estrutura minima do modulo de exemplo.

- [ ] Criar o arquivo principal do modulo com uma funcao `soma(a, b)`
- [ ] Adicionar teste cobrindo `soma(2, 3) == 5`
- [ ] Rodar a suite do projeto e garantir verde

## Phase 2: Estender o exemplo

Objetivo: evoluir o modulo sem quebrar a fase 1.

- [ ] Adicionar `subtrai(a, b)` com teste
- [ ] Atualizar o README do modulo com os dois exemplos de uso
