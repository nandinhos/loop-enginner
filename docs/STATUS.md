# STATUS — Loop Enginner

Atualizado em 2026-11-19 · Versão: **0.6.0** (`VERSION`) · Branches: `main` / `dev`

## Feito e provado (evidência: `bash tests/run-tests.sh` → 10/10)

| Área | Estado | Prova |
|---|---|---|
| Núcleo `lib/loop.sh` (fork agnóstico) | ✅ | `tests/test-loop-mock.sh`: run mock gera commit por fase |
| Adapter Antigravity (`agy`) | ✅ | `tests/test-adapter-agy.sh` + run real validado pelo usuário em `/tmp/loop-enginner-demo` (2 fases, commits `b21898d`, `fb48416`, `606c78e`, `ea12835`) |
| Adapter OpenCode (`opencode`) | ✅ | `tests/test-adapter-opencode.sh` (impl + verify read-only + batch + doctor/status) |
| Cadeia de fallback configurável (`lib/fallback.sh`) | ✅ | `tests/test-fallback.sh` (troca por quota, guarda `exit 0`, vigia por provider, `auto` e fail-closed) |
| Painel dividido, enquadramento responsivo e barras nos gates | ✅ | `tests/test-watch-gates.sh`: W=120, W=100, W=96, W=80, W=140x41 e `--once` |
| Debug Sistemático, `resume`, lock e `pause` (`lib/recovery.sh`) | ✅ | `tests/test-recovery-pause.sh`: limpeza segura restrita à fase incompleta, fail-closed externo, `run.lock`, pausa graciosa e `SIGTERM` |
| Supervisor ativo + Relatório pós-conclusão (`lib/supervisor.sh`, `lib/report.sh`) | ✅ | `tests/test-supervisor-report.sh`: até 3 retomadas, trava silenciosa, `recovery_required`, respeito a pausa e relatório `.md`/terminal com tokens factuais |
| Configuração prévia, modelos/esforço e `config.env` (`bin/loop-enginner config`) | ✅ | `tests/test-config.sh`: geração de config.env, status, run com flags de modelo/esforço e preservação no uninstall |
| CLI install/uninstall reversível | ✅ | `tests/test-install.sh`: árvore limpa antes/depois |
| CLI completa (`install`/`uninstall`/`config`/`new`/`run`/`resume`/`pause`/`supervise`/`report`/`watch`/`status`/`doctor`) | ✅ | `doctor`, `status`, `version`, `config` e `run --help` executados |
| Sintaxe + shellcheck + desacoplamento | ✅ | `tests/test-syntax.sh` (grep anti-resíduo em `lib/` e `adapters/`) |
| Fork reproduzível | ✅ | `tools/fork-from-upstream.py` regerou a lib com hashes idênticos |
| Install global (symlink) | ✅ provado em prefixo descartável | `PREFIX=/tmp/le-prefix ./install-global.sh` + doctor + `--uninstall` |
| Repositório remoto (GitHub) | ✅ | `https://github.com/nandinhos/loop-enginner` (público, `main` e `dev`) |

## Não provado / não feito

- **Run com engine real** em `codex`/`claude`/`opencode` e validação em vivo do novo painel/supervisor v0.5.0: não executados automaticamente (decisão manual do humano em branch descartável).
- **Install global nesta máquina:** o symlink em `~/.local/bin` ainda não foi criado (`./install-global.sh` após revisão final).

## Decisões fechadas (não reabrir sem o humano)

1. Núcleo = **fork completo** no repo (não depende de instalação externa).
2. Instalação em projeto = **clone global + install reversível** por
   manifest; nada copiado para dentro do projeto-alvo além de exemplos.
3. Engines atuais = **`codex|claude|agy|opencode`** (com seam em `adapters/*.sh`).
4. Nome/pasta = **`loop-enginner`** (grafia do dono); o banner visual
   continua “Loop Engineer”.
