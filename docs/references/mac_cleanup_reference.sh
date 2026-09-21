#!/usr/bin/env bash
# mac_cleanup.sh — Limpeza de artefatos de desenvolvimento e caches do macOS
# Uso: ./mac_cleanup.sh             → simula e mostra o espaço potencial
#      ./mac_cleanup.sh --run       → remove, após confirmar cada categoria

set -u

DRY_RUN=true
EXCLUDE_FILE="${HOME}/.mac_cleanup_exclude"
PROJECT_DIRS=()

usage() {
  cat <<'EOF'
Uso: mac_cleanup.sh [--run] [--projects-dir CAMINHO] [--exclude-file CAMINHO]

Sem --run o script apenas lista os alvos. Com --run, pede confirmação por categoria.

Opções:
  --projects-dir CAMINHO  Adiciona uma raiz onde procurar artefatos de projetos.
  --exclude-file CAMINHO  Arquivo com um caminho absoluto por linha a preservar.
  --run                   Remove os itens confirmados.
  --help                  Exibe esta ajuda.

Variável opcional:
  MAC_CLEANUP_PROJECT_DIRS  Raízes separadas por dois-pontos. Substitui as padrão.

Por padrão, as raízes são ~/Projetos, ~/Developer, ~/Code e ~/Documents.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --run) DRY_RUN=false ;;
    --projects-dir)
      shift
      [ "$#" -gt 0 ] || { echo "Falta um caminho após --projects-dir." >&2; exit 2; }
      PROJECT_DIRS+=("$1")
      ;;
    --exclude-file)
      shift
      [ "$#" -gt 0 ] || { echo "Falta um caminho após --exclude-file." >&2; exit 2; }
      EXCLUDE_FILE="$1"
      ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "${#PROJECT_DIRS[@]}" -eq 0 ]; then
  if [ -n "${MAC_CLEANUP_PROJECT_DIRS:-}" ]; then
    IFS=':' read -r -a PROJECT_DIRS <<< "$MAC_CLEANUP_PROJECT_DIRS"
  else
    PROJECT_DIRS=("${HOME}/Projetos" "${HOME}/Developer" "${HOME}/Code" "${HOME}/Documents")
  fi
fi

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

TMPDIR_CLEAN=$(mktemp -d)
trap 'rm -rf -- "$TMPDIR_CLEAN"' EXIT

if $DRY_RUN; then
  echo -e "${YELLOW}${BOLD}[SIMULAÇÃO] Nenhum arquivo será deletado.${RESET}"
  echo -e "${YELLOW}Execute com --run para remover após confirmar cada categoria.${RESET}\n"
fi

is_excluded() {
  local candidate="$1" excluded
  [ -f "$EXCLUDE_FILE" ] || return 1
  while IFS= read -r excluded || [ -n "$excluded" ]; do
    [ -n "$excluded" ] || continue
    case "$excluded" in \#*) continue ;; esac
    case "$candidate" in "$excluded"|"$excluded"/*) return 0 ;; esac
  done < "$EXCLUDE_FILE"
  return 1
}

add_path() {
  local path="$1" destination="$2"
  [ -e "$path" ] && ! is_excluded "$path" && printf '%s\n' "$path" >> "$destination"
}

collect_find() {
  local name="$1" destination="$2" root path
  for root in "${PROJECT_DIRS[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r path; do add_path "$path" "$destination"; done < <(find "$root" -type d -name "$name" -prune 2>/dev/null)
  done
}

collect_flutter_plugin_files() {
  local destination="$1" root path
  for root in "${PROJECT_DIRS[@]}"; do
    [ -d "$root" ] || continue
    while IFS= read -r path; do add_path "$path" "$destination"; done < <(find "$root" -maxdepth 4 -type f \( -name '.flutter-plugins' -o -name '.flutter-plugins-dependencies' \) 2>/dev/null)
  done
}

sort_by_size() {
  local input="$1" output="$2" path
  : > "$output"
  while IFS= read -r path; do
    [ -e "$path" ] || continue
    printf '%s\t%s\n' "$(du -sk "$path" 2>/dev/null | awk '{print $1}')" "$path"
  done < "$input" | sort -rn | cut -f2- > "$output"
}

calc_size_file() {
  local file="$1" total=0 path kb
  while IFS= read -r path; do
    [ -e "$path" ] || continue
    kb=$(du -sk "$path" 2>/dev/null | awk '{print $1}')
    total=$((total + kb))
  done < "$file"
  echo $((total / 1024))
}

run_category() {
  local title="$1" pathfile="$2" count size path sz answer
  count=$(wc -l < "$pathfile" | tr -d ' ')
  if [ "$count" -eq 0 ]; then
    echo -e "\n${BOLD}━━━ $title${RESET}  ${GREEN}nada encontrado${RESET}"
    return
  fi
  size=$(calc_size_file "$pathfile")
  echo -e "\n${BOLD}━━━ $title${RESET}  ${YELLOW}~${size} MB${RESET}"
  while IFS= read -r path; do
    [ -e "$path" ] || continue
    sz=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
    echo -e "  ${CYAN}${sz}${RESET}  $path"
  done < "$pathfile"
  if ! $DRY_RUN; then
    echo -e "\n${RED}${BOLD}Remover esta categoria? [s/N]${RESET} \c"
    read -r answer
    if [[ "$answer" =~ ^[sS]$ ]]; then
      while IFS= read -r path; do
        [ -e "$path" ] || continue
        rm -rf -- "$path"
        echo -e "  ${GREEN}[removido]${RESET} $path"
      done < "$pathfile"
    else
      echo -e "  ${YELLOW}[pulado]${RESET}"
    fi
  fi
}

: > "$TMPDIR_CLEAN/flutter.txt"
collect_find build "$TMPDIR_CLEAN/flutter.txt"
collect_find .dart_tool "$TMPDIR_CLEAN/flutter.txt"
collect_flutter_plugin_files "$TMPDIR_CLEAN/flutter.txt"
: > "$TMPDIR_CLEAN/node_modules.txt"; collect_find node_modules "$TMPDIR_CLEAN/node_modules.txt"
: > "$TMPDIR_CLEAN/dist.txt"; collect_find dist "$TMPDIR_CLEAN/dist.txt"
: > "$TMPDIR_CLEAN/turbo.txt"; collect_find .turbo "$TMPDIR_CLEAN/turbo.txt"

for category in pub npm yarn pnpm bun gradle pip cargo homebrew pods derived archives simulators devices; do : > "$TMPDIR_CLEAN/$category.txt"; done
add_path "${HOME}/.pub-cache/hosted" "$TMPDIR_CLEAN/pub.txt"
add_path "${HOME}/.npm/_cacache" "$TMPDIR_CLEAN/npm.txt"
add_path "${HOME}/.cache/yarn" "$TMPDIR_CLEAN/yarn.txt"; add_path "${HOME}/Library/Caches/Yarn" "$TMPDIR_CLEAN/yarn.txt"
add_path "${HOME}/Library/pnpm/store" "$TMPDIR_CLEAN/pnpm.txt"; add_path "${HOME}/Library/Caches/pnpm" "$TMPDIR_CLEAN/pnpm.txt"
add_path "${HOME}/.bun/install/cache" "$TMPDIR_CLEAN/bun.txt"
add_path "${HOME}/.gradle/caches" "$TMPDIR_CLEAN/gradle.txt"
add_path "${HOME}/Library/Caches/pip" "$TMPDIR_CLEAN/pip.txt"; add_path "${HOME}/.cache/pip" "$TMPDIR_CLEAN/pip.txt"
add_path "${HOME}/.cargo/registry" "$TMPDIR_CLEAN/cargo.txt"; add_path "${HOME}/.cargo/git" "$TMPDIR_CLEAN/cargo.txt"
add_path "${HOME}/Library/Caches/Homebrew" "$TMPDIR_CLEAN/homebrew.txt"
add_path "${HOME}/Library/Caches/CocoaPods" "$TMPDIR_CLEAN/pods.txt"
add_path "${HOME}/Library/Developer/Xcode/DerivedData" "$TMPDIR_CLEAN/derived.txt"
add_path "${HOME}/Library/Developer/Xcode/Archives" "$TMPDIR_CLEAN/archives.txt"
add_path "${HOME}/Library/Developer/CoreSimulator/Caches" "$TMPDIR_CLEAN/simulators.txt"
add_path "${HOME}/Library/Developer/Xcode/iOS DeviceSupport" "$TMPDIR_CLEAN/devices.txt"

for category in flutter node_modules dist turbo pub npm yarn pnpm bun gradle pip cargo homebrew pods derived archives simulators devices; do sort_by_size "$TMPDIR_CLEAN/$category.txt" "$TMPDIR_CLEAN/$category.sorted"; done
TOTAL_MB=0
for category in flutter node_modules dist turbo pub npm yarn pnpm bun gradle pip cargo homebrew pods derived archives simulators devices; do category_mb=$(calc_size_file "$TMPDIR_CLEAN/$category.sorted"); TOTAL_MB=$((TOTAL_MB + category_mb)); done
echo -e "${BOLD}Total potencial a liberar: ${YELLOW}~${TOTAL_MB} MB${RESET}"

run_category "Flutter — build/, .dart_tool/, .flutter-plugins*" "$TMPDIR_CLEAN/flutter.sorted"
run_category "Node — node_modules/" "$TMPDIR_CLEAN/node_modules.sorted"
run_category "Builds Node — dist/ (confira se não são artefatos de deploy)" "$TMPDIR_CLEAN/dist.sorted"
run_category "Turborepo — .turbo/" "$TMPDIR_CLEAN/turbo.sorted"
run_category "Pub cache — ~/.pub-cache/hosted/" "$TMPDIR_CLEAN/pub.sorted"
run_category "npm cache — ~/.npm/_cacache/" "$TMPDIR_CLEAN/npm.sorted"
run_category "Yarn cache" "$TMPDIR_CLEAN/yarn.sorted"
run_category "pnpm cache/store" "$TMPDIR_CLEAN/pnpm.sorted"
run_category "Bun cache" "$TMPDIR_CLEAN/bun.sorted"
run_category "Gradle cache — ~/.gradle/caches/" "$TMPDIR_CLEAN/gradle.sorted"
run_category "pip cache" "$TMPDIR_CLEAN/pip.sorted"
run_category "Cargo cache — crates e repositórios Git" "$TMPDIR_CLEAN/cargo.sorted"
run_category "Homebrew cache" "$TMPDIR_CLEAN/homebrew.sorted"
run_category "CocoaPods cache" "$TMPDIR_CLEAN/pods.sorted"
run_category "Xcode DerivedData" "$TMPDIR_CLEAN/derived.sorted"
run_category "Xcode Archives — builds arquivados" "$TMPDIR_CLEAN/archives.sorted"
run_category "Cache de simuladores Apple" "$TMPDIR_CLEAN/simulators.sorted"
run_category "Xcode iOS DeviceSupport" "$TMPDIR_CLEAN/devices.sorted"

echo -e "\n${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
if $DRY_RUN; then echo -e "${YELLOW}Simulação concluída. Execute com --run para remover o que confirmar.${RESET}"; else echo -e "${GREEN}Limpeza concluída.${RESET}"; fi
