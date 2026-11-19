# STATUS — Loop Enginner

Atualizado em 2026-11-18 · Versão: **0.3.0** (`VERSION`) · Branches: `main` / `dev`

## Feito e provado (evidência: `bash tests/run-tests.sh` → 5/5)

| Área | Estado | Prova |
|---|---|---|
| Núcleo `lib/loop.sh` (fork agnóstico) | ✅ | `tests/test-loop-mock.sh`: run mock gera commit por fase |
| Adapter Antigravity (`agy`) | ✅ | `tests/test-adapter-agy.sh` (impl + verify + batch + doctor/status) |
| Adapter OpenCode (`opencode`) | ✅ | `tests/test-adapter-opencode.sh` (impl + verify read-only + batch + doctor/status) |
| Painel `lib/loop-watch.sh` | ✅ | mesmo teste: frame `--once` com banner, caixas e `Provider:` |
| CLI install/uninstall reversível | ✅ | `tests/test-install.sh`: árvore limpa antes/depois |
| CLI new/run/watch/status/doctor/version | ✅ | `doctor` executado; `run`/`watch`/`status` cobertos pelos mocks |
| Sintaxe + shellcheck + desacoplamento | ✅ | `tests/test-syntax.sh` (grep anti-resíduo na lib e adapters) |
| Fork reproduzível | ✅ | `tools/fork-from-upstream.py` regerou a lib com hashes idênticos |
| Install global (symlink) | ✅ provado em prefixo descartável | `PREFIX=/tmp/le-prefix ./install-global.sh` + doctor + `--uninstall` |
| Repositório remoto (GitHub) | ✅ | `https://github.com/nandinhos/loop-enginner` (público, `main` e `dev`) |

## Não provado / não feito

- **Run com engine real** (`codex`/`claude`/`agy`/`opencode`): nunca executado neste fork.
  Exige branch descartável, árvore limpa e quota — decisão manual do humano.
- **Install global nesta máquina:** o symlink em `~/.local/bin` ainda não
  foi criado (proposital; `./install-global.sh` quando o humano quiser).
- **Cadeia de fallback configurável (Fase A3):** planejada, não implementada —
  ver [ROADMAP.md](ROADMAP.md) e a tarefa detalhada em [HANDOFF.md](HANDOFF.md).

## Decisões fechadas (não reabrir sem o humano)

1. Núcleo = **fork completo** no repo (não depende de instalação externa).
2. Instalação em projeto = **clone global + install reversível** por
   manifest; nada copiado para dentro do projeto-alvo além de exemplos.
3. Engines atuais = **`codex|claude|agy|opencode`** (com seam em `adapters/*.sh`).
4. Nome/pasta = **`loop-enginner`** (grafia do dono); o banner visual
   continua “Loop Engineer”.
