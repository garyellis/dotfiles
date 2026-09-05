#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd -- "$BATS_TEST_DIRNAME/.." && pwd)
  TEST_HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$TEST_HOME"

  export HOME="$TEST_HOME"
  export XDG_CONFIG_HOME="$TEST_HOME/.config"
  export XDG_STATE_HOME="$TEST_HOME/.local/state"
  export ZDOTDIR="$TEST_HOME"
  export PATH="$BATS_TEST_DIRNAME/fixtures/bin:$PATH"
  unset BATS_BREW_BUNDLE_STATUS BATS_MISE_INSTALL_STATUS BATS_MISE_VERIFY_STATUS
}

@test "check is read-only in an isolated home" {
  run "$REPO_ROOT/setup.sh" --check

  [ "$status" -eq 0 ]
  [[ "$output" == *"Setup check passed; no files were modified."* ]]
  [ -z "$(find "$HOME" -mindepth 1 -print -quit)" ]
}

@test "apply links configuration and verifies the result" {
  run "$REPO_ROOT/setup.sh" --apply

  [ "$status" -eq 0 ]
  [[ "$output" == *"Installation verification passed"* ]]
  [ "$HOME/.config/starship.toml" -ef "$REPO_ROOT/stow/starship/.config/starship.toml" ]
  [ "$HOME/.config/nvim/init.lua" -ef "$REPO_ROOT/stow/neovim/.config/nvim/init.lua" ]
  [ "$(grep -Fxc '# >>> dotfiles mise >>>' "$HOME/.zshrc")" -eq 1 ]
}

@test "apply is idempotent" {
  "$REPO_ROOT/setup.sh" --apply >/dev/null
  run "$REPO_ROOT/setup.sh" --apply

  [ "$status" -eq 0 ]
  [ "$(grep -Fxc '# >>> dotfiles starship >>>' "$HOME/.zshrc")" -eq 1 ]
  [ "$(grep -Fxc '# >>> dotfiles zsh aliases >>>' "$HOME/.zshrc")" -eq 1 ]
  [ "$(grep -Fxc '# >>> dotfiles mise >>>' "$HOME/.zshrc")" -eq 1 ]
}

@test "check rejects malformed managed markers" {
  printf '%s\n%s\n' \
    '# >>> dotfiles mise >>>' '# >>> dotfiles mise >>>' >"$HOME/.zshrc"

  run "$REPO_ROOT/setup.sh" --check

  [ "$status" -ne 0 ]
  [[ "$output" == *"Malformed managed block"* ]]
}

@test "apply restores configuration after a provisioner failure" {
  printf '%s\n' 'original zsh configuration' >"$HOME/.zshrc"
  export BATS_MISE_INSTALL_STATUS=1

  run "$REPO_ROOT/setup.sh" --apply

  [ "$status" -ne 0 ]
  [[ "$output" == *"Setup failed; restoring managed configuration"* ]]
  [ "$(cat "$HOME/.zshrc")" = 'original zsh configuration' ]
  [ ! -e "$HOME/.config/starship.toml" ]
}

@test "verify detects a broken managed link" {
  "$REPO_ROOT/setup.sh" --apply >/dev/null
  unlink "$HOME/.config/starship.toml"

  run "$REPO_ROOT/setup.sh" --verify

  [ "$status" -ne 0 ]
  [[ "$output" == *"managed link is missing or has the wrong target"* ]]
  [[ "$output" == *"Installation verification failed"* ]]
}

@test "apply rolls back when post-install verification fails" {
  printf '%s\n' 'original zsh configuration' >"$HOME/.zshrc"
  export BATS_MISE_VERIFY_STATUS=1

  run "$REPO_ROOT/setup.sh" --apply

  [ "$status" -ne 0 ]
  [[ "$output" == *"Mise reports missing configured tool versions"* ]]
  [[ "$output" == *"Setup failed; restoring managed configuration"* ]]
  [ "$(cat "$HOME/.zshrc")" = 'original zsh configuration' ]
  [ ! -e "$HOME/.config/starship.toml" ]
}
