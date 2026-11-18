# CHANGELOG

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
