#!/bin/sh
# Installs the Ghostty audio visualizer extras (encoder, shaders, SuperCollider
# tap) into their default locations. Never edits your Ghostty config or
# BootSuperDirt.scd, and never replaces an existing file that differs unless
# --force is given.
#
# Usage: extras/ghostty/install.sh [--dry-run] [--force] [--link]
#   --dry-run  show what would happen
#   --force    replace existing files that differ
#   --link     symlink instead of copy (plugin updates apply automatically)
#
# Destinations can be changed with GHOSTTY_CONFIG_DIR and TIDAL_CONFIG_DIR.

set -eu

src=$(cd "$(dirname "$0")" && pwd)
ghostty_dir=${GHOSTTY_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/ghostty}
tidal_dir=${TIDAL_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/tidal}
dry=0 force=0 link=0

for arg in "$@"; do
  case $arg in
    --dry-run) dry=1 ;;
    --force) force=1 ;;
    --link) link=1 ;;
    -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

run() {
  if [ $dry = 1 ]; then echo "  would: $*"; else "$@"; fi
}

install_file() { # <source> <destination>
  from=$1 to=$2
  if [ $link = 1 ] && [ -L "$to" ] && [ "$(readlink "$to")" = "$from" ]; then
    echo "ok       $to"; return
  fi
  if [ -e "$to" ] || [ -L "$to" ]; then
    if [ $link = 0 ] && cmp -s "$from" "$to"; then
      echo "ok       $to"; return
    fi
    if [ $force = 0 ]; then
      echo "skipped  $to (already exists; use --force to replace)"; return
    fi
    # Remove first so a symlinked destination (e.g. dotfiles) isn't written through.
    run rm -f "$to"
  fi
  run mkdir -p "$(dirname "$to")"
  if [ $link = 1 ]; then run ln -s "$from" "$to"; else run cp -p "$from" "$to"; fi
  echo "installed $to"
}

for f in "$src"/bin/*; do install_file "$f" "$ghostty_dir/bin/$(basename "$f")"; done
for f in "$src"/shaders/*.glsl; do install_file "$f" "$ghostty_dir/shaders/$(basename "$f")"; done
install_file "$src/supercollider/ghostty-scope.scd" "$tidal_dir/ghostty-scope.scd"

cat <<EOF

Next steps (not done automatically):
  1. Ghostty config ($ghostty_dir/config):
       custom-shader = shaders/audio-tidal-waves.glsl
       custom-shader-animation = always
  2. BootSuperDirt.scd, after ~dirt.start:
       "$tidal_dir/ghostty-scope.scd".standardizePath.load;
  3. Run: $ghostty_dir/bin/ghostty-audio --blocks --nvim
See extras/ghostty/README.md for details.
EOF
