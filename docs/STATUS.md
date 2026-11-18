# STATUS — Loop Enginner

Atualizado em 2026-11-18 · Versão: **0.1.0** (`VERSION`) · Branch: `main`

## Feito e provado (evidência: `bash tests/run-tests.sh` → 3/3)

| Área | Estado | Prova |
|---|---|---|
| Núcleo `lib/loop.sh` (fork agnóstico) | ✅ | `tests/test-loop-mock.sh`: run mock gera commit por fase |
| Painel `lib/loop-watch.sh` | ✅ | mesmo teste: frame `--once` com banner e caixas |
| CLI install/uninstall reversível | ✅ | `tests/test-install.sh`: árvore limpa antes/depois |
| CLI new/run/watch/status/doctor/version | ✅ | `doctor` executado; `run`/`watch` cobertos pelo mock |
| Sintaxe + shellcheck + desacoplamento | ✅ | `tests/test-syntax.sh` (grep anti-resíduo na lib) |
| Fork reproduzível | ✅ | `tools/fork-from-upstream.py` regerou a lib com hashes idênticos |
| Install global (symlink) | ✅ provado em prefixo descartável | `PREFIX=/tmp/le-prefix ./install-global.sh` + doctor + `--uninstall` |

## Não provado / não feito

- **Run com engine real** (`codex`/`claude`): nunca executado neste fork.
  Exige branch descartável, árvore limpa e quota — decisão manual do humano.
- **Publicação no GitHub:** repo é só local; `README.md` usa
  `<seu-usuario>` como placeholder da URL de clone.
- **Install global nesta máquina:** o symlink em `~/.local/bin` ainda não
  foi criado (proposital; `./install-global.sh` quando o humano quiser).
- **Adapters Antigravity/OpenCode:** planejados, não implementados —
  ver [ROADMAP.md](ROADMAP.md) e a tarefa detalhada em [HANDOFF.md](HANDOFF.md).

## Decisões fechadas (não reabrir sem o humano)

1. Núcleo = **fork completo** no repo (não depende de instalação externa).
2. Instalação em projeto = **clone global + install reversível** por
   manifest; nada copiado para dentro do projeto-alvo além de exemplos.
3. Engines v0.1.0 = **`codex|claude`**, contrato herdado do loop original.
4. Nome/pasta = **`loop-enginner`** (grafia do dono); o banner visual
   continua “Loop Engineer”.
