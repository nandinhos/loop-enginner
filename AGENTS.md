# AGENTS.md — Loop Enginner (instruções para agentes: Antigravity/agy, Claude Code, Codex, Muse)

## Comece por aqui

1. Leia [docs/HANDOFF.md](docs/HANDOFF.md) — estado atual, decisões fechadas
   e a próxima tarefa detalhada.
2. Leia [docs/STATUS.md](docs/STATUS.md) — o que está feito e provado.
3. Rode `bash tests/run-tests.sh` antes de mudar qualquer coisa: a linha de
   base tem que estar verde (3 suítes). Se não estiver, pare e reporte.

## O que este projeto é

Runner de loops estruturados e autônomos sobre qualquer repo Git:
`lib/loop.sh` (núcleo, fork agnóstico do ralph-loop do bc-harness) +
`lib/loop-watch.sh` (painel “Loop Engineer”) atrás da CLI
`bin/loop-enginner` (install/uninstall reversíveis, run/watch/status/doctor).

## Invariantes — não quebre

- **Zero interferência no projeto-alvo.** O install escreve somente
  `.loop-enginner/` e a linha `/.loop-enginner/` em `.git/info/exclude`
  (nunca no `.gitignore`, nunca em arquivo rastreado). O uninstall remove
  somente o que está no `install.manifest` + runtime, preserva arquivos do
  usuário e é fail-closed sem manifest.
- **Runtime isolado.** Fragmentos de fase vivem em `.loop-enginner/run/`
  porque o split de fases faz `rm -rf` nesse diretório; nunca aponte esse
  `rm` para a raiz de `.loop-enginner/` (apagaria `PHASES.md` e `hook.sh`).
- **Contrato do loop é estável.** 4 gates mecânicos, sessão nova por fase,
  1 commit por fase, formato `## Phase N:` com tasks `- [ ]`, marcadores
  `LOOP-TASK`, estado TSV em `.loop-enginner/state/`.
- **Nada de reacoplar.** `tests/test-syntax.sh` falha se voltarem para a
  lib: `RALPH_*`, `ralph.sh`, `.phases/`, `bc-harness`, `claude-profiles`
  ou nomes de projetos específicos. Origem e créditos ficam só no `NOTICE`.
- **`lib/` é a fonte canônica.** `tools/fork-from-upstream.py` só serve
  para re-sincronizar com os scripts originais; depois de rodá-lo, revise
  o diff inteiro e rode a suíte. Nunca edite a lib "pelo script" sem revisar.
- **Teste automatizado nunca chama engine real.** Runs de teste usam mock
  no PATH (ver `tests/test-loop-mock.sh`). Run real é manual, em branch
  descartável, e consome quota — não faça sem o humano pedir.

## Convenções

- **Shell estrito:** `set -euo pipefail` (o watch usa `-uo` por desenho),
  `bash -n` e `shellcheck -S error` limpos, mensagens de erro fail-closed
  (na dúvida, aborta explicando — nunca segue no escuro).
- **Commits (pt-BR, sem `Co-Authored-By`):**
  `[feat|fix|refactor|docs|test|style|perf|chore] (escopo opcional): descrição`,
  1ª linha ≤ 72 caracteres. Ex.: `feat (adapters): adiciona adapter do agy`.
  Exceção herdada e documentada: os commits emitidos pelo próprio motor
  (`feat(phase-N): …`, `wip(phase-N): incomplete`) são do loop, não seus.
- **Documentação acompanha o código:** mudou comportamento → atualize
  `README.md`, `docs/STATUS.md` e `CHANGELOG.md` no mesmo commit.
- **Evidência antes de afirmar:** nunca diga "testado/sem regressão" sem
  comando, exit code e saída registrados na resposta.

## Mapa rápido

| Caminho | O que é |
|---|---|
| `bin/loop-enginner` | CLI (install/uninstall/new/run/watch/status/doctor) |
| `adapters/` | Adapters de provider por contrato de sessão (`agy.sh`, `opencode.sh`, …) |
| `lib/loop.sh` | Núcleo do loop (preflight, gates 0–3, sessões, commits) |
| `lib/loop-watch.sh` | Painel de terminal (leitor puro do estado TSV) |
| `install-global.sh` | Symlink em `~/.local/bin` (máquina), com `--uninstall` |
| `templates/` | `PHASES`, `config.env` e `hook` de exemplo copiados no install |
| `tests/run-tests.sh` | Suíte completa (sintaxe, install, run com mock) |
| `tools/fork-from-upstream.py` | Re-sincroniza a lib com as fontes originais |
| `docs/ROADMAP.md` | Direção futura (adapters Antigravity/OpenCode) |
