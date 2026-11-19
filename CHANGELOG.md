# CHANGELOG

## v0.4.0 — 2026-11-18

Fase A3 — Cadeia de fallback configurável e vigia de progresso por provider:

- `lib/fallback.sh`: resolução de cadeia via `--fallback-chain` /
  `LOOP_ENGINNER_FALLBACK_CHAIN` (vazio = só `--engine`, `auto` = engines
  detectadas no `PATH`, lista explícita = fail-closed no preflight), decisão
  pós-falha com guarda absoluta de exit code e vigia de inatividade por
  provider (`streaming` vs `batch`).
- `lib/loop.sh`: suporte a `--fallback-chain`, `ACTIVE_PROVIDER` sticky no run,
  evento `provider_fallback` em hooks/histórico e Gate 0/`detect_usage_limit`
  orientados ao provider efetivo.
- `lib/loop-watch.sh`: destaque visual em `Provider:` quando há fallback ativo.
- `bin/loop-enginner`: `doctor` valida `lib/fallback.sh`; `status` exibe
  `engine=` e `provider=` do último run.
- `tests/test-fallback.sh` e `tests/test-syntax.sh`: cobertura com mocks de
  troca por quota + sticky, teste negativo (`exit 0` com texto de gatilho),
  vigia por provider (`codex` travado vs `agy` batch), `auto` vs fail-closed,
  cadeia esgotada e erro comum sem fallback.
- `templates/config.env.example`: variáveis `LOOP_ENGINNER_FALLBACK_*` e timeouts
  por provider documentados.

## v0.3.0 — 2026-11-18

Fase A2 — Adapter OpenCode (`opencode`) atrás da seam `adapters/`:

- `adapters/opencode.sh`: adapter de provider para `opencode` com modo `impl`
  (`opencode run --auto`), modo `verify` read-only (`--agent plan`, sem `--auto`),
  prompt via `stdin`, configuração via `LOOP_ENGINNER_OPENCODE_*` e timeout
  `batch` por provider (`LOOP_ENGINNER_OPENCODE_INACTIVITY_TIMEOUT`, default `900s`).
- `lib/loop.sh`: suporte e documentação de `--engine opencode` e variáveis
  `LOOP_ENGINNER_OPENCODE_*` no cabeçalho e `preflight_checks`.
- `lib/loop-watch.sh`: detecção de processos `opencode` em `watch_process_count`.
- `bin/loop-enginner`: `doctor` valida `adapters/opencode.sh` e detecta
  `codex|claude|agy|opencode` no `PATH`; `status` exibe `opencode`.
- `tests/test-adapter-opencode.sh`: cobertura com mock de `impl` + Gate 2 +
  Gate 3 (`--agent plan`), `doctor`/`status`, timeout `batch` e unhappy paths.
- `templates/config.env.example`: variáveis `LOOP_ENGINNER_OPENCODE_*` documentadas.

## v0.2.0 — 2026-11-18

Fase A1 — Adapter Antigravity (`agy`) atrás da seam `adapters/`:

- `adapters/agy.sh`: adapter de provider para `agy` com modo `impl`
  (`--dangerously-skip-permissions`), modo `verify` read-only (`--mode plan --sandbox`),
  configuração via `LOOP_ENGINNER_AGY_*` e metadado de timeout por provider em modo `batch`
  (`LOOP_ENGINNER_AGY_INACTIVITY_TIMEOUT` herdando `LOOP_ENGINNER_AGY_PRINT_TIMEOUT`).
- `lib/loop.sh`: descoberta e carregamento de `adapters/*.sh`, suporte a
  `--engine agy`, guarda de exit code para não disparar espera de limite em
  sessão bem-sucedida e emissão de `provider` / `LOOP_ENGINNER_PROVIDER` em `run.tsv` e hooks.
- `lib/loop-watch.sh`: exibição do campo `Provider:` na caixa `ENGINE` e
  detecção de processos `agy`.
- `bin/loop-enginner`: `doctor` valida `adapters/agy.sh` e detecta `codex|claude|agy`
  no `PATH`; `status` exibe `agy` e o `provider` do último run.
- `tests/test-adapter-agy.sh` e `tests/test-syntax.sh`: cobertura com mock de
  `impl` + Gate 2 + Gate 3, `doctor`/`status`, timeout `batch` e unhappy paths.
- `templates/config.env.example`: variáveis `LOOP_ENGINNER_AGY_*` documentadas.

## v0.1.0 — 2026-11-18

Primeira versão: fork agnóstico do ralph-loop do bc-harness + painel
“Loop Engineer”, empacotados como projeto instalável.

- `lib/loop.sh`: núcleo desacoplado (`LOOP_ENGINNER_*`, `LOOP-TASK`,
  runtime em `.loop-enginner/` com fragmentos isolados em `run/`, hook em
  `.loop-enginner/hook.sh`, input `.loop-enginner/PHASES.md` → `PHASES.md`
  → layouts `.spec/` legados).
- `lib/loop-watch.sh`: painel com banner ANSI Shadow, detecção de
  processos restrita ao loop e às engines `codex|claude`.
- `bin/loop-enginner`: install/uninstall reversíveis por manifest
  (fail-closed, preserva arquivos do usuário, `--purge` explícito),
  `new`, `run`, `watch`, `status`, `doctor`, `version`.
- `install-global.sh`: symlink em `~/.local/bin` a partir do clone.
- Templates, suíte de testes (sintaxe/shellcheck, install, run com mock),
  CI do GitHub Actions e ferramenta de re-sincronização do fork.
