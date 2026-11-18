# GEMINI.md — entrada para Antigravity (agy)

As instruções canônicas para agentes neste repo estão em
[AGENTS.md](AGENTS.md). Leia-a primeiro, junto com
[docs/HANDOFF.md](docs/HANDOFF.md) (estado + próxima tarefa) e
[docs/STATUS.md](docs/STATUS.md).

Resumo do resumo: rode `bash tests/run-tests.sh` (baseline verde obrigatória),
não quebre as invariantes de zero-interferência/fail-closed, nunca chame
engine real em teste automatizado (use mock) e commite em pt-BR no padrão
`[feat|fix|docs|test|chore]: descrição`, sem rodapé de atribuição.
