# HANDOFF — continuação via Antigravity (agy)

Gerado em 2026-11-18, atualizado na Fase A2 (v0.3.0).
Destinatário: próximo agente (Antigravity) e o humano que o conduz.

## Como retomar em 2 minutos

```bash
cd loop-enginner
bash tests/run-tests.sh        # baseline: 5 passaram, 0 falharam
agy
```

Primeiro prompt sugerido no agy:

```text
/goal Leia AGENTS.md, docs/STATUS.md e docs/HANDOFF.md. Execute a Fase A3
(cadeia de fallback configurável) respeitando as invariantes do AGENTS.md e
a decisão fechada (sem LOOP_ENGINNER_FALLBACK_CHAIN roda só --engine; 'auto'
detecta engines instaladas em runtime; cadeia explícita é fail-closed no
preflight): baseline verde antes e depois, testes somente com mock, commits
em pt-BR sem Co-Authored-By. Pare e pergunte se alguma decisao fechada
precisar mudar.
```

Se preferir validar o entendimento antes: troque `/goal` por `/grill-me`.

## Onde paramos

O projeto nasceu como fork agnóstico e desacoplado do `ralph.sh` + `ralph-watch.sh`
(detalhes em [STATUS.md](STATUS.md) e `NOTICE`). Na **Fase A1 (v0.2.0)** foi
criada a seam `adapters/` e entregue o adapter **Antigravity (`agy`)** em
`adapters/agy.sh`. Na **Fase A2 (v0.3.0)** foi entregue o adapter
**OpenCode (`opencode`)** em `adapters/opencode.sh`, integrado a `lib/loop.sh`,
`lib/loop-watch.sh`, `bin/loop-enginner` (`doctor` e `status`) e coberto por
`tests/test-adapter-opencode.sh` com mock.

Repositório remoto publicado em `https://github.com/nandinhos/loop-enginner.git`
(público, branches `main` e `dev`, topologia Clássico `dev -> main`); ainda sem
install global nesta máquina e sem run com engine real neste fork.

## Próxima tarefa — Fase A: adapters de provider no fallback

Objetivo (pedido do dono): incluir **Antigravity (`agy`)** e
**OpenCode (`opencode`)** como adapters, trazendo modelos distintos para
a cadeia de fallback do loop. Ordem sugerida, um adapter por vez, cada um
com seus testes antes do próximo:

### A1 — Adapter Antigravity (`agy`) — ✅ Concluída (v0.2.0)

- Seam mínima criada em `adapters/*.sh` com contrato
  `adapter_<nome>_{check,meta,run,gate0}` atrás de `lib/loop.sh` (`is_adapter_engine`,
  `load_adapter`, `run_engine`, `gate0_engine_finished`, `state_init`).
- `adapters/agy.sh` invoca `agy` em modo batch (`--output-format text`,
  `--print-timeout` default `30m`, `--print="<prompt>"`, `--dangerously-skip-permissions`
  em `impl`, `--mode plan --sandbox` em `verify`), com `LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT`
  por provider (herdando `LOOP_ENGINNER_AGY_PRINT_TIMEOUT`) e guarda de exit code
  para não disparar espera por limite em saída 0.
- `bin/loop-enginner` (`doctor`/`status`), `lib/loop-watch.sh` (`Provider:` e
  `provider_process`), `tests/test-syntax.sh` e `tests/test-adapter-agy.sh` verdes (`4/4`).

### A2 — Adapter OpenCode (`opencode`) — ✅ Concluída (v0.3.0)

- Implementado em `adapters/opencode.sh` seguindo o mesmo contrato
  (`check/meta/run/gate0`). Invoca `opencode run --format default` lendo o
  prompt via `stdin`: modo `impl` usa `--auto` (com `--agent`/`--model`
  opcionais), modo `verify` usa `--agent ${LOOP_ENGINNER_OPENCODE_VERIFY_AGENT:-plan}`
  (sem `--auto`, read-only), `--variant` mapeado para `reasoning_effort`,
  timeout batch por provider (`LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT`,
  default `900s`) e guarda de exit code.
- `bin/loop-enginner` (`doctor`/`status`), `lib/loop.sh`, `lib/loop-watch.sh`
  e `tests/test-adapter-opencode.sh` verdes (`5/5`).

### A3 — Cadeia de fallback configurável — próxima

- Decisão fechada (opção 1): sem `LOOP_ENGINNER_FALLBACK_CHAIN`, roda apenas
  `--engine` (sem fallback surpresa); com `LOOP_ENGINNER_FALLBACK_CHAIN=auto`,
  usa as engines instaladas detectadas em runtime; com cadeia explícita
  (ex.: `LOOP_ENGINNER_FALLBACK_CHAIN="codex agy opencode"`), falha alto no
  preflight se faltar algum degrau (fail-closed). A engine primária continua
  vindo de `--engine`.
- **Gatilhos só com prova:** quota, limite de uso, autenticação,
  indisponibilidade, travamento sem progresso. Regra herdada: regex de
  gatilho nova exige reprodução + teste — e o padrão só é consultado
  **depois** de a sessão falhar, nunca sobre texto comum de log (em
  2026-09-06 um fallback disparou porque o agente apenas *leu* um arquivo
  contendo as expressões).

### Critérios de aceite por fase (A1/A2/A3)

1. `bash tests/run-tests.sh` verde, com **teste novo por adapter** usando
   mock no PATH (padrão de `tests/test-loop-mock.sh`): sessão mock escreve,
   gates passam, 1 commit por fase, estado publicado.
2. Teste de fallback (A3) com mock que falha pelo gatilho alvo e prova a
   troca de provider — e um teste negativo provando que log comum contendo
   a expressão do gatilho **não** dispara troca quando a sessão teve sucesso.
3. `loop-enginner doctor`/`status` enxergam o provider novo; painel mostra
   o provider efetivo (o dashboard exibe a *engine*; não confundir).
4. `README.md`, `docs/STATUS.md`, `CHANGELOG.md` e este HANDOFF atualizados
   no mesmo commit; `VERSION` sobe (minor).
5. Nenhum nome de projeto/máquina do dono entra na lib (o teste de
   desacoplamento em `tests/test-syntax.sh` é o guarda — estenda-o se
   surgirem nomes novos a banir).

### Leitura de referência (fora deste repo, na máquina do dono)

Estes projetos são os laboratórios onde o fallback já foi aprendido na
prática; leia antes de desenhar a A3, não copie código sem desacoplar:

- `~/projects/watcher-features/foundation/docs/adr/0010-cadeia-de-provider-por-shim-no-path.md`
  e `scripts/ralph-dispatch.sh` (cadeia, gatilhos, vigia por provider).
- `~/projects/watcher/docs/handoffs/2026-09-06-abstracao-ralph-events.md`
  (origem da abstração; seção 8 = mínimo viável provado por testes).
- `~/projects/events/scripts/ralph-events.sh` + `ralph-codex-dispatch.sh`
  (wrapper mais completo em produção local; específico do projeto events).

## Fora de escopo desta fase

- Rodar run real de validação com engine de verdade (quota + commits reais;
  só manual, em branch descartável, quando o dono pedir).
- Mudar gates, formato de fases ou mensagens de commit do motor.

## Perguntas abertas para o humano

1. `./install-global.sh` nesta máquina agora, ou só após o primeiro run real?
