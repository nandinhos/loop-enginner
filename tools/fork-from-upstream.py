#!/usr/bin/env python3
"""Fork deterministico: ralph.sh/ralph-watch.sh (fontes adaptadas)
-> lib/loop.sh e lib/loop-watch.sh, desacoplados do bc-harness.

Uso:
    python3 tools/fork-from-upstream.py <dir-com-ralph.sh-e-ralph-watch.sh>

Cada substituicao esperada falha alto se o padrao nao for encontrado:
assim um upstream que mudou nunca gera um fork silenciosamente errado.
A lib/ commitada e a fonte canonica; este script serve para re-sincronizar
com as fontes originais quando elas evoluirem (revisar o diff depois).
"""
import os
import stat
import sys

if len(sys.argv) != 2:
    print(__doc__)
    sys.exit(2)

SRC_DIR = sys.argv[1]
DST_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")


def apply(text, pairs, label):
    for old, new in pairs:
        n = text.count(old)
        if n == 0:
            print(f"ERRO [{label}]: padrao nao encontrado: {old[:80]!r}")
            sys.exit(1)
        print(f"[{label}] x{n}: {old[:70]!r} -> {new[:70]!r}")
        text = text.replace(old, new)
    return text


def fork(src, dst, pairs, label):
    with open(os.path.join(SRC_DIR, src), encoding="utf-8") as fh:
        text = fh.read()
    text = apply(text, pairs, label)
    out = os.path.join(DST_DIR, dst)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.chmod(out, os.stat(out).st_mode | stat.S_IEXEC | stat.S_IXGRP | stat.S_IXOTH)
    print(f"[{label}] escrito: {out} ({len(text.splitlines())} linhas)")
    return text


os.makedirs(DST_DIR, exist_ok=True)

loop_pairs = [
    # procedencia no cabecalho (mantem a contagem de linhas do --help ajustada)
    ("# ralph.sh\n",
     "# loop.sh — nucleo do Loop Enginner (fork agnostico; origem e creditos\n"
     "# no NOTICE, licenca MIT no LICENSE da raiz do projeto).\n"),
    # fragmentos de fase sao runtime descartavel: ficam em run/, para o
    # rm -rf do split_phases nunca apagar hook/config/input de .loop-enginner/
    ('PHASES_DIR=".phases"', 'PHASES_DIR=".loop-enginner/run"'),
    ("# Input (primeiro arquivo posicional). Sem argumento, resolve nesta ordem:\n"
     "#   1. .spec/init/project-phases.md      (cadeia init)\n"
     "#   2. .spec/project-phases.md           (repos pre-init, com aviso)",
     "# Input (primeiro arquivo posicional). Sem argumento, resolve nesta ordem:\n"
     "#   1. .loop-enginner/PHASES.md\n"
     "#   2. PHASES.md na raiz\n"
     "#   3. .spec/init/project-phases.md ou .spec/project-phases.md (compat)"),
    ("sed -n '2,82p'", "sed -n '2,83p'"),
    # hook: sai de scripts/ do projeto-alvo para dentro de .loop-enginner/
    ("scripts/ralph-hook.sh", ".loop-enginner/hook.sh"),
    ("(ex: notify-n8n.sh)", "(ex: hook de notificacao)"),
    # resolucao de input agnostica, com compat para layouts .spec legados
    ('  if [ -f ".spec/init/project-phases.md" ]; then\n'
     '    INPUT_FILE=".spec/init/project-phases.md"\n'
     '  elif [ -f ".spec/project-phases.md" ]; then\n'
     '    INPUT_FILE=".spec/project-phases.md"\n'
     '    warn "Usando .spec/project-phases.md (layout pre-init). O padrao atual e .spec/init/project-phases.md."\n'
     '  else\n'
     '    fail "Nenhum documento de fases encontrado."\n'
     '    fail "Esperado .spec/init/project-phases.md (rode /init:project-phases) ou passe o caminho como argumento."',
     '  if [ -f ".loop-enginner/PHASES.md" ]; then\n'
     '    INPUT_FILE=".loop-enginner/PHASES.md"\n'
     '  elif [ -f "PHASES.md" ]; then\n'
     '    INPUT_FILE="PHASES.md"\n'
     '  elif [ -f ".spec/init/project-phases.md" ]; then\n'
     '    INPUT_FILE=".spec/init/project-phases.md"\n'
     '  elif [ -f ".spec/project-phases.md" ]; then\n'
     '    INPUT_FILE=".spec/project-phases.md"\n'
     '  else\n'
     '    fail "Nenhum documento de fases encontrado."\n'
     '    fail "Esperado .loop-enginner/PHASES.md, PHASES.md na raiz, ou passe o caminho como argumento."'),
    # preambulo da sessao: documentos .spec viram exemplo, nao contrato
    ("2. .spec/init/project-description.md — descricao geral do projeto\n"
     "3. .spec/init/user-stories.md — user stories\n"
     "4. .spec/init/database-schema.md — modelo de dados\n"
     "5. os documentos citados no proprio texto da fase (ex: SPEC.md/PLAN.md da feature)",
     "2. README e a documentacao do projeto (ex: docs/, SPEC.md, PLAN.md)\n"
     "3. os documentos citados no proprio texto da fase"),
    ("agent_status_to_ralph", "agent_status_to_loop"),
    ("RALPH-TASK", "LOOP-TASK"),
    ("RALPH_", "LOOP_ENGINNER_"),
    (".phases", ".loop-enginner"),
    ("ralph-watch.sh", "loop-watch.sh"),
    ("ralph.sh", "loop.sh"),
    ("ralph.log", "loop.log"),
    ("ralph", "loop-enginner"),
]

watch_pairs = [
    ("# ralph-watch.sh\n", "# loop-watch.sh — painel do Loop Enginner (fork MIT; ver NOTICE)\n"),
    # deteccao de processos: so o loop e as engines codex|claude
    ('    function direct_ralph(pid) {\n'
     '      return comm[pid] == "ralph-events.sh" || comm[pid] == "ralph.sh" || comm[pid] == "ralph-codex-dispatch.sh" ||\n'
     '        args[pid] ~ /(^|[[:space:]])(bash|sh)[[:space:]]+([^[:space:]]*\\/)?ralph-events\\.sh([[:space:]]|$)/ ||\n'
     '        args[pid] ~ /(^|[[:space:]])(bash|sh)[[:space:]]+([^[:space:]]*\\/)?ralph\\.sh([[:space:]]|$)/ ||\n'
     '        args[pid] ~ /(^|[[:space:]])(bash|sh)[[:space:]]+([^[:space:]]*\\/)?ralph-codex-dispatch\\.sh([[:space:]]|$)/ ||\n'
     '        args[pid] ~ /(^|[[:space:]])(bash|sh)[[:space:]]+[^[:space:]]*ralph-provider-bin\\/(codex|agy)([[:space:]]|$)/\n'
     '    }',
     '    function direct_loop(pid) {\n'
     '      return comm[pid] == "loop.sh" || comm[pid] == "loop-enginner" ||\n'
     '        args[pid] ~ /(^|[[:space:]])(bash|sh)[[:space:]]+([^[:space:]]*\\/)?loop\\.sh([[:space:]]|$)/ ||\n'
     '        args[pid] ~ /(^|[[:space:]])loop-enginner([[:space:]]|$)/\n'
     '    }'),
    ('    function provider_process(pid) {\n'
     '      return (comm[pid] == "codex" || comm[pid] == "agy" ||\n'
     '        args[pid] ~ /(^|[[:space:]])codex([[:space:]]|$)/ ||\n'
     '        args[pid] ~ /codex-linux-x64/ || args[pid] ~ /ralph-provider-bin\\/(codex|agy)/)\n'
     '    }',
     '    function provider_process(pid) {\n'
     '      return (comm[pid] == "codex" || comm[pid] == "claude" ||\n'
     '        args[pid] ~ /(^|[[:space:]])(codex|claude)([[:space:]]|$)/ ||\n'
     '        args[pid] ~ /codex-linux-x64/)\n'
     '    }'),
    ("direct_ralph", "direct_loop"),
    ("has_ralph_parent", "has_loop_parent"),
    ("RALPH_", "LOOP_ENGINNER_"),
    (".phases", ".loop-enginner"),
    ("ralph-watch.sh", "loop-watch.sh"),
    ("ralph.sh", "loop.sh"),
    ("ralph", "loop-enginner"),
]

fork("ralph.sh", "loop.sh", loop_pairs, "loop")
fork("ralph-watch.sh", "loop-watch.sh", watch_pairs, "watch")
print("OK")
