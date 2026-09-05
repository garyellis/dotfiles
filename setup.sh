#!/usr/bin/env bash

set -Eeuo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
stow_packages=(herdr mise neovim starship uv wezterm zsh)
stow_sources=()
stow_targets=()
stow_names=()
backup_archive=''
zshrc_path=''
zshrc_relative=''
verification_errors=0
verification_warnings=0

usage() {
  cat <<'EOF'
Usage: ./setup.sh --check | --apply | --verify

  --check  Validate prerequisites and preview Stow changes without modifying files.
  --apply  Back up managed local configuration, then provision and link dotfiles.
  --verify Validate the installed links, tools, shell setup, and native configs.
EOF
}

build_stow_manifest() {
  local source_config package_relative target_relative

  stow_sources=()
  stow_targets=()
  stow_names=()

  while IFS= read -r source_config; do
    package_relative=${source_config#"$repo_root/stow/"}
    target_relative=${package_relative#*/}

    # Stow ignores Git metadata; it remains useful only inside the repository.
    if [[ "$(basename -- "$target_relative")" == '.gitignore' ]]; then
      continue
    fi

    stow_sources+=("$source_config")
    stow_targets+=("$HOME/$target_relative")
    stow_names+=("$target_relative")
  done < <(find "$repo_root/stow" -type f -print | LC_ALL=C sort)
}

validate_repository() {
  local package required_file
  local -a required_files=(
    stow/neovim/.config/nvim/.gitignore
    stow/neovim/.config/nvim/init.lua
    stow/neovim/.config/nvim/lazy-lock.json
    stow/neovim/.config/nvim/lua/keymaps.lua
    stow/neovim/.config/nvim/lua/plugins.lua
    stow/neovim/.config/nvim/after/queries/toml/injections.scm
    stow/starship/.config/starship.toml
    stow/wezterm/.wezterm.lua
    stow/zsh/.config/zsh/aliases.zsh
    stow/herdr/.config/herdr/config.toml
    stow/mise/.config/mise/config.toml
    stow/uv/.config/uv/uv.toml
  )

  if [[ ! -f "$repo_root/Brewfile" ]]; then
    printf 'Brewfile not found: %s\n' "$repo_root/Brewfile" >&2
    exit 1
  fi

  for package in "${stow_packages[@]}"; do
    if [[ ! -d "$repo_root/stow/$package" ]]; then
      printf 'Stow package not found: %s\n' "$repo_root/stow/$package" >&2
      exit 1
    fi
  done

  for required_file in "${required_files[@]}"; do
    if [[ ! -f "$repo_root/$required_file" ]]; then
      printf 'Required configuration file not found: %s\n' "$repo_root/$required_file" >&2
      exit 1
    fi
  done

  build_stow_manifest

  if ((${#stow_sources[@]} == 0)); then
    printf '%s\n' 'No files found in the Stow packages.' >&2
    exit 1
  fi
}

validate_marker_pair() {
  local target_file="$1"
  local begin_marker="$2"
  local end_marker="$3"
  local begin_count end_count

  [[ -f "$target_file" ]] || return 0

  begin_count=$(grep -Fxc "$begin_marker" "$target_file" || true)
  end_count=$(grep -Fxc "$end_marker" "$target_file" || true)
  if ((begin_count > 1 || end_count > 1 || begin_count != end_count)); then
    printf 'Malformed managed block in %s: %s\n' "$target_file" "$begin_marker" >&2
    exit 1
  fi

  if ((begin_count == 1)) && ! awk -v begin="$begin_marker" -v end="$end_marker" '
    $0 == begin { seen_begin = 1 }
    $0 == end && seen_begin { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$target_file"; then
    printf 'Managed block markers are out of order in %s: %s\n' \
      "$target_file" "$begin_marker" >&2
    exit 1
  fi
}

wezterm_is_unmanaged() {
  [[ -d /Applications/WezTerm.app ]] && ! brew list --cask wezterm >/dev/null 2>&1
}

preflight_setup() {
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups"
  local zsh_dir="${ZDOTDIR:-$HOME}"
  local tool_name physical_home physical_zsh_dir package_symlink
  local -a required_tools=(awk basename brew chmod cmp date find grep mkdir mktemp mv readlink rm rmdir sort stow tar unlink)

  for tool_name in "${required_tools[@]}"; do
    if ! command -v "$tool_name" >/dev/null 2>&1; then
      printf 'Required command not found: %s\n' "$tool_name" >&2
      exit 1
    fi
  done

  validate_repository

  if [[ "$HOME" != /* || "$HOME" == '/' ]]; then
    printf 'HOME must be a non-root absolute path (got %s).\n' "$HOME" >&2
    exit 1
  fi

  if [[ "$config_dir" != "$HOME/.config" ]]; then
    printf 'This Stow layout requires XDG_CONFIG_HOME to be %s (got %s).\n' \
      "$HOME/.config" "$config_dir" >&2
    exit 1
  fi
  if [[ -L "$HOME/.config" ]]; then
    printf 'Refusing to manage a symlinked config root: %s\n' "$HOME/.config" >&2
    exit 1
  fi

  if [[ "$zsh_dir" != /* || "$zsh_dir" == *'/../'* || "$zsh_dir" == *'/..' ]]; then
    printf 'ZDOTDIR must be a normalized absolute path (got %s).\n' "$zsh_dir" >&2
    exit 1
  fi
  if [[ "$zsh_dir" != "$HOME" && "$zsh_dir" != "$HOME/"* ]]; then
    printf 'ZDOTDIR must be inside HOME so it can be safely backed up (got %s).\n' \
      "$zsh_dir" >&2
    exit 1
  fi
  if [[ "$zsh_dir" != "$HOME" ]]; then
    if [[ ! -d "$zsh_dir" ]]; then
      printf 'Custom ZDOTDIR must already exist as a directory: %s\n' "$zsh_dir" >&2
      exit 1
    fi
    physical_home=$(cd -P -- "$HOME" && pwd)
    physical_zsh_dir=$(cd -P -- "$zsh_dir" && pwd)
    if [[ "$physical_zsh_dir" != "$physical_home/"* ]]; then
      printf 'ZDOTDIR resolves outside HOME: %s\n' "$zsh_dir" >&2
      exit 1
    fi
  fi

  zshrc_path="$zsh_dir/.zshrc"
  zshrc_relative=${zshrc_path#"$HOME/"}
  if [[ -L "$zshrc_path" ]]; then
    printf 'Refusing to rewrite symlinked Zsh config: %s\n' "$zshrc_path" >&2
    exit 1
  fi

  if [[ "$state_dir" != "$HOME/"* ]]; then
    printf 'Backup directory must be inside HOME: %s\n' "$state_dir" >&2
    exit 1
  fi

  package_symlink=$(find "$repo_root/stow" -type l -print -quit)
  if [[ -n "$package_symlink" ]]; then
    printf 'Stow packages must not contain source symlinks: %s\n' "$package_symlink" >&2
    exit 1
  fi

  validate_marker_pair "$zshrc_path" \
    '# >>> dotfiles starship >>>' '# <<< dotfiles starship <<<'
  validate_marker_pair "$zshrc_path" \
    '# >>> dotfiles zsh aliases >>>' '# <<< dotfiles zsh aliases <<<'
  validate_marker_pair "$zshrc_path" \
    '# >>> dotfiles mise >>>' '# <<< dotfiles mise <<<'
}

backup_local_config() {
  local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups"
  local timestamp archive partial_archive relative_name
  local -a backup_items=()
  local -a managed_paths=(
    "$zshrc_relative"
    .wezterm.lua
    .config/nvim
    .config/starship.toml
    .config/zsh/aliases.zsh
    .config/herdr/config.toml
    .config/mise/config.toml
    .config/uv/uv.toml
  )

  for relative_name in "${managed_paths[@]}"; do
    if [[ -e "$HOME/$relative_name" || -L "$HOME/$relative_name" ]]; then
      backup_items+=("$relative_name")
    fi
  done

  timestamp=$(date +%Y%m%d%H%M%S)
  archive="$state_dir/dotfiles-config-$timestamp.$$.tar.gz"
  partial_archive="$archive.partial"

  mkdir -p "$state_dir"
  chmod 700 "$state_dir"
  # Preserve symlink topology. Regular pre-existing files are archived with
  # their content, while managed Stow links continue to point at this repo.
  if ((${#backup_items[@]} == 0)); then
    printf '%s\n' 'No existing managed configuration found; creating an empty rollback snapshot.'
    if ! (
      umask 077
      tar -czf "$partial_archive" -T /dev/null
    ); then
      rm -f -- "$partial_archive"
      return 1
    fi
  elif ! (
    umask 077
    tar -C "$HOME" -czf "$partial_archive" "${backup_items[@]}"
  ); then
    rm -f -- "$partial_archive"
    return 1
  fi
  if ! tar -tzf "$partial_archive" >/dev/null; then
    rm -f -- "$partial_archive"
    return 1
  fi
  mv -- "$partial_archive" "$archive"
  backup_archive="$archive"
  printf 'Backed up managed local configuration to %s\n' "$archive"
}

setup_homebrew() {
  local brewfile="$repo_root/Brewfile"
  local cask_skip="${HOMEBREW_BUNDLE_CASK_SKIP:-}"

  printf '%s\n' 'Setting up Homebrew packages...'

  if ! command -v brew >/dev/null 2>&1; then
    printf '%s\n' 'Homebrew is required. Install it from https://brew.sh, then rerun this script.' >&2
    exit 1
  fi

  if [[ ! -f "$brewfile" ]]; then
    printf 'Brewfile not found: %s\n' "$brewfile" >&2
    exit 1
  fi

  if wezterm_is_unmanaged; then
    cask_skip="${cask_skip:+$cask_skip }wezterm"
    printf '%s\n' 'Leaving the existing non-Homebrew WezTerm application unchanged.'
    printf '%s\n' 'To adopt it later: brew install --cask --adopt wezterm'
  fi

  if HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip" \
    brew bundle check --no-upgrade --file "$brewfile" >/dev/null 2>&1; then
    printf '%s\n' 'Homebrew packages are already installed.'
  else
    HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip" \
      brew bundle install --no-upgrade --file "$brewfile"
  fi
}

prepare_stow_target() {
  local source_config="$1"
  local target_config="$2"
  local config_name="$3"
  local backup current_link

  mkdir -p "$(dirname -- "$target_config")"

  if [[ -L "$target_config" ]] && [[ "$target_config" -ef "$source_config" ]]; then
    return
  fi

  if [[ -L "$target_config" ]]; then
    current_link=$(readlink "$target_config")
    if [[ "$current_link" == "$repo_root/"* ]]; then
      unlink "$target_config"
      printf 'Removed legacy %s link: %s\n' "$config_name" "$target_config"
      return
    fi
  fi

  if [[ -e "$target_config" || -L "$target_config" ]]; then
    backup="${target_config}.backup.$(date +%Y%m%d%H%M%S)"
    mv -- "$target_config" "$backup"
    printf 'Backed up existing %s config to %s\n' "$config_name" "$backup"
  fi
}

prepare_stow_directory() {
  local target_config="$1"
  local config_name="$2"
  local backup current_link

  if [[ -L "$target_config" ]]; then
    current_link=$(readlink "$target_config")
    if [[ "$current_link" == "$repo_root/"* ]]; then
      unlink "$target_config"
      printf 'Removed legacy %s directory link: %s\n' "$config_name" "$target_config"
    else
      backup="${target_config}.backup.$(date +%Y%m%d%H%M%S)"
      mv -- "$target_config" "$backup"
      printf 'Backed up existing %s directory to %s\n' "$config_name" "$backup"
    fi
  fi

  if [[ -e "$target_config" && ! -d "$target_config" ]]; then
    backup="${target_config}.backup.$(date +%Y%m%d%H%M%S)"
    mv -- "$target_config" "$backup"
    printf 'Backed up existing %s path to %s\n' "$config_name" "$backup"
  fi

  mkdir -p "$target_config"
}

setup_stow() {
  local stow_dir="$repo_root/stow"
  local config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
  local item_index

  printf '%s\n' 'Setting up dotfile links with GNU Stow...'

  if ! command -v stow >/dev/null 2>&1; then
    printf '%s\n' 'GNU Stow is required but was not installed by Homebrew.' >&2
    exit 1
  fi

  prepare_stow_directory "$config_dir/nvim" Neovim

  for ((item_index = 0; item_index < ${#stow_sources[@]}; item_index++)); do
    prepare_stow_target "${stow_sources[$item_index]}" \
      "${stow_targets[$item_index]}" "${stow_names[$item_index]}"
  done

  stow --dir "$stow_dir" --target "$HOME" --no-folding "${stow_packages[@]}"
  printf '%s\n' 'Dotfile links are managed by GNU Stow.'
}

setup_starship() {
  local zshrc="$zshrc_path"
  local begin_marker end_marker temporary_zshrc

  printf '%s\n' 'Setting up Starship...'

  if ! command -v starship >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      printf '%s\n' 'Installing Starship with Homebrew...'
      brew install starship
    else
      printf '%s\n' 'Starship is required. Install Homebrew or Starship, then rerun this script.' >&2
      exit 1
    fi
  fi

  mkdir -p "$(dirname -- "$zshrc")"
  touch "$zshrc"

  begin_marker='# >>> dotfiles starship >>>'
  end_marker='# <<< dotfiles starship <<<'
  temporary_zshrc=$(mktemp "${TMPDIR:-/tmp}/dotfiles-zshrc.XXXXXX")

  awk '
  /^[[:space:]]*ZSH_THEME=/ {
    if (!theme_disabled) print "ZSH_THEME=\"\""
    theme_disabled = 1
    next
  }
  { print }
  ' "$zshrc" >"$temporary_zshrc"

  if ! grep -Fqx "$begin_marker" "$temporary_zshrc"; then
    cat >>"$temporary_zshrc" <<EOF

$begin_marker
if command -v starship >/dev/null 2>&1; then
  eval "\$(starship init zsh)"
fi
$end_marker
EOF
  fi

  if ! cmp -s "$temporary_zshrc" "$zshrc"; then
    cp "$temporary_zshrc" "$zshrc"
    printf 'Configured Starship in %s\n' "$zshrc"
  else
    printf 'Starship is already configured in %s\n' "$zshrc"
  fi

  rm -f -- "$temporary_zshrc"
}

setup_zsh_aliases() {
  local zshrc="$zshrc_path"
  local begin_marker='# >>> dotfiles zsh aliases >>>'

  printf '%s\n' 'Setting up Zsh aliases...'

  if ! command -v eza >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      printf '%s\n' 'Installing eza with Homebrew...'
      brew install eza
    else
      printf '%s\n' 'eza is required. Install Homebrew or eza, then rerun this script.' >&2
      exit 1
    fi
  fi

  mkdir -p "$(dirname -- "$zshrc")"
  touch "$zshrc"

  if grep -Fqx "$begin_marker" "$zshrc"; then
    printf 'Zsh aliases are already configured in %s\n' "$zshrc"
  else
    cat >>"$zshrc" <<'EOF'

# >>> dotfiles zsh aliases >>>
if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/aliases.zsh" ]]; then
  source "${XDG_CONFIG_HOME:-$HOME/.config}/zsh/aliases.zsh"
fi
# <<< dotfiles zsh aliases <<<
EOF
    printf 'Configured Zsh aliases in %s\n' "$zshrc"
  fi

}

setup_mise() {
  local source_config="$repo_root/stow/mise/.config/mise/config.toml"
  local zshrc="$zshrc_path"
  local begin_marker='# >>> dotfiles mise >>>'

  printf '%s\n' 'Setting up Mise...'

  if [[ ! -f "$source_config" ]]; then
    printf 'Mise config not found: %s\n' "$source_config" >&2
    exit 1
  fi

  if ! command -v mise >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
      printf '%s\n' 'Installing Mise with Homebrew...'
      brew install mise
    else
      printf '%s\n' 'Mise is required. Install Homebrew or Mise, then rerun this script.' >&2
      exit 1
    fi
  fi

  mise trust --quiet --yes "$source_config"
  mise install

  mkdir -p "$(dirname -- "$zshrc")"
  touch "$zshrc"

  if grep -Fqx "$begin_marker" "$zshrc"; then
    printf 'Mise is already configured in %s\n' "$zshrc"
  else
    cat >>"$zshrc" <<'EOF'

# >>> dotfiles mise >>>
if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
# <<< dotfiles mise <<<
EOF
    printf 'Configured Mise in %s\n' "$zshrc"
  fi
}

validate_stow_packages() {
  local temporary_home simulation_status=0

  temporary_home=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-stow-check.XXXXXX")
  stow --dir "$repo_root/stow" --target "$temporary_home" --no-folding \
    --simulate "${stow_packages[@]}" >/dev/null 2>&1 || simulation_status=$?
  rmdir "$temporary_home"

  if ((simulation_status != 0)); then
    printf '%s\n' 'The Stow packages conflict with each other or are invalid.' >&2
    return "$simulation_status"
  fi
}

report_target_plan() {
  local item_index target_config source_config

  printf '%s\n' 'Managed configuration plan:'
  if [[ -L "$HOME/.config/nvim" ]]; then
    printf '  backup directory link: %s\n' "$HOME/.config/nvim"
  fi

  for ((item_index = 0; item_index < ${#stow_sources[@]}; item_index++)); do
    source_config=${stow_sources[$item_index]}
    target_config=${stow_targets[$item_index]}
    if [[ -L "$target_config" ]] && [[ "$target_config" -ef "$source_config" ]]; then
      printf '  already managed: %s\n' "$target_config"
    elif [[ -e "$target_config" || -L "$target_config" ]]; then
      printf '  backup then link: %s\n' "$target_config"
    else
      printf '  create link: %s\n' "$target_config"
    fi
  done

  if wezterm_is_unmanaged; then
    printf '%s\n' '  keep existing application: /Applications/WezTerm.app'
  fi
  printf '%s\n' '  Homebrew will install missing dependencies without routine upgrades.'
  printf '%s\n' '  Mise will install missing configured tool versions.'
}

verification_pass() {
  printf '  ok: %s\n' "$1"
}

verification_fail() {
  printf '  error: %s\n' "$1" >&2
  ((verification_errors += 1))
}

verification_warn() {
  printf '  warning: %s\n' "$1" >&2
  ((verification_warnings += 1))
}

verification_details() {
  local detail

  while IFS= read -r detail; do
    [[ -n "$detail" ]] && printf '    %s\n' "$detail" >&2
  done <<<"$1"
}

verify_managed_links() {
  local item_index

  for ((item_index = 0; item_index < ${#stow_sources[@]}; item_index++)); do
    if [[ -L "${stow_targets[$item_index]}" ]] &&
      [[ "${stow_targets[$item_index]}" -ef "${stow_sources[$item_index]}" ]]; then
      continue
    fi
    verification_fail "managed link is missing or has the wrong target: ${stow_targets[$item_index]}"
  done

  if ((verification_errors == 0)); then
    verification_pass 'all managed links point into this repository'
  fi
}

verify_marker_block() {
  local target_file="$1"
  local block_name="$2"
  local begin_marker="$3"
  local end_marker="$4"
  local begin_count end_count

  begin_count=$(grep -Fxc "$begin_marker" "$target_file" 2>/dev/null || true)
  end_count=$(grep -Fxc "$end_marker" "$target_file" 2>/dev/null || true)
  if ((begin_count == 1 && end_count == 1)); then
    verification_pass "$block_name initialization is present exactly once"
  else
    verification_fail "$block_name initialization must be present exactly once in $target_file"
  fi
}

verify_required_command() {
  local command_name="$1"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi
  verification_fail "required command is unavailable: $command_name"
  return 1
}

verify_installation() {
  local cask_skip="${HOMEBREW_BUNDLE_CASK_SKIP:-}"
  local nvim_file
  local links_errors_before
  local nvim_errors_before
  local verification_output
  local -a expected_commands=(brew eza herdr mise nvim starship stow zsh)

  verification_errors=0
  verification_warnings=0

  preflight_setup
  printf '%s\n' 'Verifying installed dotfiles...'

  links_errors_before=$verification_errors
  verify_managed_links
  if ((verification_errors > links_errors_before)); then
    verification_warn 'run mise run setup to repair managed links'
  fi

  verify_marker_block "$zshrc_path" Starship \
    '# >>> dotfiles starship >>>' '# <<< dotfiles starship <<<'
  verify_marker_block "$zshrc_path" 'Zsh aliases' \
    '# >>> dotfiles zsh aliases >>>' '# <<< dotfiles zsh aliases <<<'
  verify_marker_block "$zshrc_path" Mise \
    '# >>> dotfiles mise >>>' '# <<< dotfiles mise <<<'

  for nvim_file in "${expected_commands[@]}"; do
    verify_required_command "$nvim_file" || true
  done

  if command -v zsh >/dev/null 2>&1 && zsh -n "$zshrc_path"; then
    verification_pass 'Zsh initialization parses successfully'
  else
    verification_fail "Zsh initialization is invalid: $zshrc_path"
  fi

  if wezterm_is_unmanaged; then
    cask_skip="${cask_skip:+$cask_skip }wezterm"
  fi
  if verification_output=$(HOMEBREW_BUNDLE_CASK_SKIP="$cask_skip" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    brew bundle check --verbose --no-upgrade --file "$repo_root/Brewfile" 2>&1); then
    verification_pass 'Homebrew bundle dependencies are satisfied'
  else
    verification_fail 'Homebrew bundle has missing dependencies'
    verification_details "$verification_output"
  fi

  if verification_output=$(MISE_GLOBAL_CONFIG_FILE="$repo_root/stow/mise/.config/mise/config.toml" \
    mise install --dry-run-code 2>&1); then
    verification_pass 'Mise tool versions are installed'
  else
    verification_fail 'Mise reports missing configured tool versions'
    verification_details "$verification_output"
  fi

  if verification_output=$(HERDR_CONFIG_PATH="$HOME/.config/herdr/config.toml" \
    herdr config check 2>&1); then
    verification_pass 'Herdr configuration is valid'
  else
    verification_fail 'Herdr configuration validation failed'
    verification_details "$verification_output"
  fi

  if verification_output=$(STARSHIP_CONFIG="$HOME/.config/starship.toml" \
    starship print-config 2>&1); then
    verification_pass 'Starship configuration is valid'
  else
    verification_fail 'Starship configuration validation failed'
    verification_details "$verification_output"
  fi

  if verification_output=$(mise exec -- uv --offline --config-file "$HOME/.config/uv/uv.toml" \
    python list --only-installed 2>&1); then
    verification_pass 'uv configuration is valid'
  else
    verification_fail 'uv configuration validation failed'
    verification_details "$verification_output"
  fi

  if command -v nvim >/dev/null 2>&1; then
    nvim_errors_before=$verification_errors
    while IFS= read -r nvim_file; do
      if ! NVIM_LOG_FILE=/dev/null nvim --clean --headless -i NONE \
        -c 'lua assert(loadfile(vim.fn.argv(0)))' -c quit -- "$nvim_file" \
        >/dev/null 2>&1; then
        verification_fail "Neovim could not compile $nvim_file"
      fi
    done < <(find "$repo_root/stow/neovim" -type f -name '*.lua' -print | LC_ALL=C sort)
    if ((verification_errors == nvim_errors_before)); then
      verification_pass 'Neovim Lua configuration compiles successfully'
    fi
  fi

  if command -v wezterm >/dev/null 2>&1 ||
    [[ -x /Applications/WezTerm.app/Contents/MacOS/wezterm ]]; then
    verification_pass 'WezTerm executable is available'
  else
    verification_warn 'WezTerm is not installed; its Lua configuration passed static validation only'
  fi

  if ((verification_errors > 0)); then
    printf 'Installation verification failed with %d error(s) and %d warning(s).\n' \
      "$verification_errors" "$verification_warnings" >&2
    return 1
  fi

  printf 'Installation verification passed with %d warning(s).\n' "$verification_warnings"
}

rollback_configuration() {
  local failure_status="$1"
  local failed_suffix

  trap - ERR INT TERM
  set +e

  printf '%s\n' 'Setup failed; restoring managed configuration from the backup.' >&2
  stow --dir "$repo_root/stow" --target "$HOME" --no-folding \
    --delete "${stow_packages[@]}" >/dev/null 2>&1

  failed_suffix="failed.$(date +%Y%m%d%H%M%S).$$"
  if [[ -e "$HOME/.config/nvim" || -L "$HOME/.config/nvim" ]]; then
    mv -- "$HOME/.config/nvim" "$HOME/.config/nvim.$failed_suffix"
  fi
  if [[ -e "$zshrc_path" || -L "$zshrc_path" ]]; then
    mv -- "$zshrc_path" "$zshrc_path.$failed_suffix"
  fi

  if tar -xzf "$backup_archive" -C "$HOME"; then
    printf 'Configuration restored. Failed-run files were preserved with suffix .%s\n' \
      "$failed_suffix" >&2
  else
    printf 'Automatic restore failed. Recover manually from %s\n' "$backup_archive" >&2
  fi

  exit "$failure_status"
}

check_setup() {
  preflight_setup
  validate_stow_packages
  report_target_plan
  printf '%s\n' 'Setup check passed; no files were modified.'
}

apply_setup() {
  preflight_setup
  validate_stow_packages
  report_target_plan
  backup_local_config
  setup_homebrew

  trap 'rollback_configuration $?' ERR
  trap 'rollback_configuration 130' INT
  trap 'rollback_configuration 143' TERM

  setup_stow
  setup_starship
  setup_zsh_aliases
  setup_mise
  verify_installation

  trap - ERR INT TERM

  printf '\n%s\n' 'Dotfiles setup complete. Run exec zsh to start a fresh shell.'
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
  return 0
fi

case "${1:-}" in
  --check)
    if (($# != 1)); then
      usage >&2
      exit 2
    fi
    check_setup
    ;;
  --apply)
    if (($# != 1)); then
      usage >&2
      exit 2
    fi
    apply_setup
    ;;
  --verify)
    if (($# != 1)); then
      usage >&2
      exit 2
    fi
    verify_installation
    ;;
  --help | -h)
    usage
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
