# Roadmap

## Feito (v0.1.0)

- Fork agnóstico do loop (`lib/loop.sh`) e do painel (`lib/loop-watch.sh`),
  sem dependência de instalação externa nem de nomes/projetos de origem.
- CLI `loop-enginner` com `install`/`uninstall` reversíveis por manifest,
  runtime inteiro dentro de `.loop-enginner/` e zero escrita em arquivo
  rastreado do projeto-alvo.
- Engines `codex` (default) e `claude`, contrato de fases `## Phase N:`,
  4 gates mecânicos e 1 commit por fase, como no loop original.
- Hook de eventos, estado observável em TSV e dashboard ao vivo.

## Concluído após a v0.1.0 (v0.2.0 – v0.4.0)

Pacote de adapters de provider e cadeia de fallback configurável:

- **v0.2.0 — Antigravity (`agy`)** em `adapters/agy.sh`: adapter em modo batch
  (`--output-format text`, `--print-timeout`) atrás da seam `adapters/`.
- **v0.3.0 — OpenCode (`opencode`)** em `adapters/opencode.sh`: adapter em modo
  batch (`opencode run --auto` no `impl` e `--agent plan` no `verify`).
- **v0.4.0 — Cadeia de fallback configurável** em `lib/fallback.sh`:
  `--fallback-chain` / `LOOP_ENGINNER_FALLBACK_CHAIN` (vazio, `auto` ou lista
  explícita fail-closed), gatilhos pós-falha com guarda absoluta de exit code e
  vigia de inatividade por provider (`streaming` vs `batch`).
- **v0.5.0 — Observabilidade dos gates, Debug Sistemático, Retomada Segura, Pausa, Supervisor e Relatório:**
  rodapé dividido (`LOGS RECENTES` | `GATES`), `lib/recovery.sh` (Context7 +
  memória opcional, `--resume`, `run.lock`, `pause`), `lib/supervisor.sh`
  (ativo por padrão, 3 tentativas, trava silenciosa) e `lib/report.sh`
  (`.loop-enginner/state/report.md` e visualização estilizada com métricas
  de tempo, modelo e tokens observados).
