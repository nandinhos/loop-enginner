#!/usr/bin/env bash
#
# install-global.sh — instala o comando `loop-enginner` NESTA MAQUINA.
#
# Cria um symlink $PREFIX/bin/loop-enginner -> <este repo>/bin/loop-enginner.
# Nada e copiado: `git pull` neste repo atualiza a ferramenta.
#
#   ./install-global.sh              instala (PREFIX padrao: ~/.local)
#   ./install-global.sh --uninstall  remove o symlink (so se apontar p/ ca)
#   PREFIX=/usr/local ./install-global.sh
#
# Isto e diferente de `loop-enginner install`, que instala DENTRO de um
# projeto-alvo (sem symlink, so .loop-enginner/ + .git/info/exclude).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFIX="${PREFIX:-$HOME/.local}"
BIN_DIR="$PREFIX/bin"
LINK="$BIN_DIR/loop-enginner"
TARGET="$REPO_DIR/bin/loop-enginner"

die() { printf 'install-global: erro: %s\n' "$*" >&2; exit 1; }

case "${1:-}" in
  --uninstall)
    if [ -L "$LINK" ] && [ "$(readlink -f "$LINK")" = "$TARGET" ]; then
      rm -f "$LINK"
      printf 'install-global: removido %s\n' "$LINK"
    elif [ -e "$LINK" ]; then
      die "$LINK existe mas nao aponta para este repo; nao removido"
    else
      printf 'install-global: nada a remover (%s ausente)\n' "$LINK"
    fi
    ;;
  ''|--install)
    [ -x "$TARGET" ] || die "bin/loop-enginner nao executavel em $REPO_DIR"
    mkdir -p "$BIN_DIR"
    if [ -L "$LINK" ] && [ "$(readlink -f "$LINK")" = "$TARGET" ]; then
      printf 'install-global: ja instalado: %s -> %s\n' "$LINK" "$TARGET"
      exit 0
    fi
    [ -e "$LINK" ] && die "$LINK ja existe e nao e deste repo; remova manualmente"
    ln -s "$TARGET" "$LINK"
    printf 'install-global: instalado: %s -> %s\n' "$LINK" "$TARGET"
    case ":$PATH:" in
      *":$BIN_DIR:"*) ;;
      *) printf 'install-global: aviso: %s nao esta no PATH\n' "$BIN_DIR" >&2 ;;
    esac
    printf 'install-global: teste com: loop-enginner doctor\n'
    ;;
  *)
    die "uso: ./install-global.sh [--uninstall]"
    ;;
esac
