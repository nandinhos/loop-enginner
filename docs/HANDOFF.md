# HANDOFF — continuação via Antigravity (agy)

Gerado em 2026-11-18, atualizado na Fase A3 (v0.4.0).
Destinatário: próximo agente e o humano que o conduz.

## Como retomar em 2 minutos

```bash
cd loop-enginner
bash tests/run-tests.sh        # baseline: 6 passaram, 0 falharam
```

Após revisar os commits em `dev`, promover para `main` e publicar quando
aprovado (ou abrir nova fase a partir de `dev`).

## Onde paramos

O projeto nasceu como fork agnóstico e desacoplado do `ralph.sh` + `ralph-watch.sh`
(detalhes em [STATUS.md](STATUS.md) e `NOTICE`). Toda a **Fase A** (A1 + A2 + A3)
foi concluída localmente em `dev`, mantendo `main` intacta em `1844d63` até
a revisão final:

- **Fase A1 (`v0.2.0`):** seam `adapters/` + adapter Antigravity (`adapters/agy.sh`).
- **Fase A2 (`v0.3.0`):** adapter OpenCode (`adapters/opencode.sh`).
- **Fase A3 (`v0.4.0`):** cadeia de fallback configurável + vigia de progresso
  por provider (`lib/fallback.sh`, `--fallback-chain` / `LOOP_ENGINNER_FALLBACK_CHAIN`,
  guarda absoluta de exit code), coberta por `tests/test-fallback.sh` (`6/6`).

Repositório remoto publicado em `https://github.com/nandinhos/loop-enginner.git`
(público, topologia Clássico `dev -> main`); ainda sem install global nesta
máquina e sem run com engine real neste fork.

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

### A3 — Cadeia de fallback configurável — ✅ Concluída (v0.4.0)

- Implementada em `lib/fallback.sh` e integrada a `lib/loop.sh` (`--fallback-chain`
  / `LOOP_ENGINNER_FALLBACK_CHAIN`), `lib/loop-watch.sh` (`Provider:` destacado em
  fallback) e `bin/loop-enginner` (`doctor` e `status` com `engine=`/`provider=`).
- Resolução da cadeia (Opção 1): vazio = apenas `--engine`; `auto` = engines
  detectadas em runtime no `PATH`; explícita = fail-closed no preflight se
  algum degrau estiver ausente ou inválido.
- Guarda absoluta pós-falha (`fallback_should_escalate`): `rc == 0` (ou `claude`
  sem `is_error`) nunca escala mesmo que texto do padrão apareça no log.
- Vigia de inatividade por provider (`streaming` vs `batch`): encerra processo
  travado sem matar providers `batch` legítimos (`agy`/`opencode`).
- Coberta por `tests/test-fallback.sh` (`6/6` suítes verdes).

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
