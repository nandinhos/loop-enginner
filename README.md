# Loop Enginner

Loops estruturados e autônomos sobre qualquer repositório Git: você escreve
um documento de fases, o loop alimenta cada fase a uma sessão nova da engine
(`codex`, `claude`, `agy` ou `opencode`), valida o resultado por **4 gates mecânicos** e faz
**1 commit por fase concluída** — sem perguntas do início ao fim e sem tocar
em nenhum arquivo rastreado do seu projeto além do código que a própria
sessão escreve.

Fork agnóstico (MIT) do ralph-loop do bc-harness + painel de terminal
“Loop Engineer” — origem e créditos no [NOTICE](NOTICE).

> **Autonomia é perigosa por desenho.** As sessões rodam sem sandbox de
> escrita (`codex --sandbox danger-full-access` /
> `claude --dangerously-skip-permissions` /
> `agy --dangerously-skip-permissions` /
> `opencode run --auto`). Rode em repo confiável, numa
> **branch descartável**, com a árvore limpa. Um commit por fase significa
> que `git revert`/`git reset` sempre volta atrás.

## Instalação (via GitHub)

Na máquina, uma vez:

```bash
git clone https://github.com/nandinhos/loop-enginner.git
cd loop-enginner
./install-global.sh        # symlink ~/.local/bin/loop-enginner -> este repo
loop-enginner doctor       # checa bash, git e engine no PATH
```

Atualizar é `git pull` (o comando é um symlink, nada é copiado).
Tirar da máquina: `./install-global.sh --uninstall`.

Pré-requisitos: `bash`, `git` e ao menos uma engine no PATH —
[Codex](https://github.com/openai/codex),
[Claude Code](https://claude.com/product/claude-code),
Antigravity (`agy`) ou OpenCode (`opencode`) — já logada.

## Uso num projeto

```bash
cd meu-projeto
loop-enginner install   # escreve so .loop-enginner/ + .git/info/exclude
loop-enginner new       # cria .loop-enginner/PHASES.md do template; edite-o
loop-enginner run       # arvore limpa, branch descartavel (supervisor ativo por padrao)
loop-enginner pause     # pausa graciosamente ao fim da fase/ciclo atual
loop-enginner resume    # retoma run pausado/falho limpando so a fase incompleta
loop-enginner report    # exibe e salva relatorio detalhado pos-execucao
loop-enginner watch     # (outro terminal) painel ao vivo
```

Opções úteis do `run`: `--engine claude`, `--engine agy` ou `--engine opencode`,
`--fallback-chain auto` (ou `"codex agy opencode"`), `--from 3`, `--max-cycles 5`,
`--test-cmd "npm test"`, `--dashboard` (painel embutido), `--resume`,
`--no-supervise` (desliga retomada automática pós-falha), `--no-verify`.
A lista completa: `loop-enginner run --help`.

### Continuidade, Debug Sistemático, Retomada Segura e Pausa Graciosa

- **Supervisor padrão ativo (`lib/supervisor.sh`):** o `loop-enginner run`
  monitora o loop contra falhas e travas silenciosas (`LOOP_ENGINNER_SUPERVISOR_STALL_TIMEOUT`,
  default `1800s`), acionando retomada automática segura em até **3 tentativas**
  (`LOOP_ENGINNER_MAX_RECOVERIES=3`). Desligue pontualmente com `--no-supervise`
  ou `LOOP_ENGINNER_SUPERVISE=off`.
- **Debug Sistemático e retomada segura (`lib/recovery.sh`):** em ciclos de
  correção e retomadas pós-falha, o prompt injeta protocolo de Debug Sistemático
  com consulta oficial via Context7 (quando disponível) e memória opcional não
  bloqueante. Com `loop-enginner resume` (ou `run --resume`), se uma fase
  incompleta deixou a árvore suja sobre o mesmo `base_head`, o diff parcial é
  arquivado em `.loop-enginner/state/recovery/` e apenas essa fase é reiniciada
  do zero — preservando fases já commitadas e abortando em modo fail-closed diante
  de alterações externas.
- **Pausa graciosa:** `loop-enginner pause` (ou tecla `p` no painel `--dashboard`
  / `watch`) encerra ao fim da fase concluída ou do ciclo vermelho corrente,
  salvando o estado em `.loop-enginner/state/session.tsv` (`status=paused`) sem
  despertar reinício automático do supervisor.

### Cadeia de fallback configurável

Sem `LOOP_ENGINNER_FALLBACK_CHAIN` (ou `--fallback-chain`), o loop executa apenas
a engine pedida em `--engine`. Para habilitar fallback:

- `--fallback-chain auto` / `LOOP_ENGINNER_FALLBACK_CHAIN=auto`: começa em
  `--engine` e encadeia automaticamente as demais engines disponíveis no `PATH`.
- `--fallback-chain "codex agy opencode"`: cadeia explícita (fail-closed no
  preflight se qualquer degrau estiver ausente ou inválido).

A troca de provider só acontece **após falha real** (`rc != 0`, limite/quota,
autenticação, indisponibilidade ou travamento sem progresso), nunca por texto
que apenas ecoe no log de uma sessão bem-sucedida. O vigia de inatividade usa
timeout **por provider** (`streaming` vs `batch`, configurável em
[templates/config.env.example](templates/config.env.example)).

Sem argumento de entrada, o loop resolve nesta ordem:
`.loop-enginner/PHASES.md` → `PHASES.md` na raiz → layouts legados
`.spec/init/project-phases.md` / `.spec/project-phases.md`.
Um caminho explícito também vale: `loop-enginner run docs/PHASES.md`.

## O documento de fases

```markdown
## Phase 1: Fundacao

- [ ] Primeira task verificavel
- [ ] Segunda task, com teste

## Phase 2: Evolucao

- [ ] ...
```

Contrato: heading `## Phase N: <titulo>`; `### Phase N.M:` é sub-fase;
qualquer outro `## ` encerra a fase; com o gate 3 ligado, toda fase precisa
de ao menos uma task `- [ ]`. Cada fase roda em sessão **nova**: o texto
precisa ser auto-contido (contexto, aceite, como testar). Modelo completo
em [templates/PHASES.example.md](templates/PHASES.example.md).

## Os 4 gates (por fase)

| Gate | Pergunta | Quem decide |
|---|---|---|
| 0 | A engine terminou de verdade? | exit code / JSON da sessão |
| 1 | A sessão escreveu código? | sinal, não veredito |
| 2 | A suíte do projeto passa? | o loop, fora da sessão |
| 3 | As tasks foram cumpridas? | sessão verificadora independente, read-only |

Gate vermelho → ciclo de correção com a causa (default: 3). Limite de uso
da engine → espera o reset e re-executa a **mesma** fase, sem consumir
ciclo. Tudo verde → commit `feat(phase-N): <titulo>`; falha final →
`wip(phase-N): incomplete` (formato herdado do loop original).

O gate 2 detecta o comando pelo manifest (Sail, composer, artisan,
package.json, pytest, go, cargo) ou usa `--test-cmd` /
`LOOP_ENGINNER_TEST_CMD`. Referência completa de variáveis em
[templates/config.env.example](templates/config.env.example).

## O que vive no seu projeto (e como sai)

Tudo fica em `.loop-enginner/`, ignorado via `.git/info/exclude`
(**nunca** no seu `.gitignore`):

```text
.loop-enginner/
  install.manifest    registro do que o install criou
  PHASES.md           seu plano (criado por voce ou pelo 'new')
  hook.sh             seu hook de eventos (opcional, chmod +x)
  *.example.*         referencias copiadas pelo install
  run/ state/ logs/ prompts/   runtime dos runs (descartavel)
```

Desinstalar a qualquer momento:

```bash
loop-enginner uninstall            # remove o nosso + runtime; preserva o seu
loop-enginner uninstall --purge    # remove .loop-enginner/ inteiro
```

O uninstall é fail-closed: sem `install.manifest` ele não apaga nada no
escuro (exceto com `--purge` explícito), e só remove a linha do
`.git/info/exclude` se foi ele quem a adicionou. Depois de desinstalar,
`git status` volta exatamente ao que era antes do install.

## Painel e hook

`loop-enginner watch` desenha o painel “Loop Engineer” a partir de
`.loop-enginner/state/` (leitor puro — pode rodar em outro terminal ou
embutido via `run --dashboard`), com rodapé dividido entre **LOGS RECENTES** e
visor detalhado dos **GATES (G0..G3)** e atalho **`p`** para pausa graciosa. O
estado é publicado em todo run, com ou sem painel.

Ao concluir, pausar ou esgotar retomadas, `lib/report.sh` salva
`.loop-enginner/state/report.md` e apresenta relatório estilizado no terminal
com duração, commits, diffstat por fase, provider/modelo efetivo e tokens
observados (`n/d (modo text)` quando o provider em modo texto não informa).

Eventos do run (`run_start`, `phase_done`, `gate_fail`, `limit_wait`,
`provider_fallback`, `supervisor_retry`, `run_paused`, …)
podem chamar `.loop-enginner/hook.sh` — modelo em
[templates/hook.example.sh](templates/hook.example.sh).

## Desenvolvimento

```bash
bash tests/run-tests.sh   # sintaxe+shellcheck, install/uninstall, watch, recovery, supervisor/report
```

- `lib/loop.sh`, `lib/fallback.sh`, `lib/recovery.sh`, `lib/supervisor.sh`,
  `lib/report.sh` e `lib/loop-watch.sh` são a fonte canônica;
  `tools/fork-from-upstream.py` reproduz o fork a partir dos scripts
  originais quando eles evoluírem (falha alto se um padrão sumir).
- `adapters/` concentra os adapters de provider por contrato de sessão
  (`adapters/agy.sh` para `--engine agy`, `adapters/opencode.sh` para `--engine opencode`).
- CI no GitHub Actions roda a mesma suíte.
- Agentes (Antigravity e outros): comecem por [AGENTS.md](AGENTS.md) e
  [docs/HANDOFF.md](docs/HANDOFF.md); estado atual em
  [docs/STATUS.md](docs/STATUS.md), histórico em
  [CHANGELOG.md](CHANGELOG.md) e [docs/ROADMAP.md](docs/ROADMAP.md).

## Licença

MIT — ver [LICENSE](LICENSE) e [NOTICE](NOTICE).
