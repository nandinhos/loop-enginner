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

## Proxima fase (planejado, NAO implementado)

Pacote de adapters de provider para o processo de fallback, trazendo
modelos distintos para a mesma cadeia do loop:

- **Antigravity (`agy`)** como adapter de provider;
- **OpenCode (`opencode`)** como adapter de provider;
- cadeia de fallback configurável (ex.: `codex -> agy -> opencode`),
  com gatilhos provados (quota, limite, indisponibilidade, travamento
  sem progresso) — cada gatilho novo exige reprodução + teste, para não
  disparar fallback por texto que apenas aparece no log.

Desenho esperado (a detalhar quando a fase abrir): adapters moram em
`adapters/`, um por provider, atrás do mesmo contrato de sessão das
engines atuais; o núcleo do loop não muda. Nada disso existe ainda —
este arquivo registra a intenção, não uma promessa de interface.
