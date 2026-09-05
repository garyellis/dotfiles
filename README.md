# dotfiles

Dev workstation configuration management.

## Validation

install validation tools and run the validator.

```sh
mise install
mise run check
```

The Mise checks combine static and native configuration validation with Bats
tests of setup, idempotency, and rollback in isolated home directories.

## Setup

Check the local environment and preview link changes first:

```sh
./setup.sh --check
```

Then explicitly apply the setup:

```sh
mise run setup
exec zsh
```

To preview link changes without applying them:

```sh
stow --dir ./stow --target "$HOME" --no-folding --simulate --verbose \
  herdr mise neovim starship uv wezterm zsh
```

Use `stow --delete` with the same directory, target, and package names to remove
the managed links without deleting the source files in this repository.

## Restoring a configuration backup

Inspect an archive before restoring it:

```sh
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups"
tar -tzf "$backup_dir/dotfiles-config-YYYYMMDDHHMMSS.PID.tar.gz"
```

Remove the Stow-managed links, then extract the selected archive into the home
directory:

```sh
stow --dir ./stow --target "$HOME" --no-folding --delete \
  herdr mise neovim starship uv wezterm zsh
if [[ -e "$HOME/.config/nvim" || -L "$HOME/.config/nvim" ]]; then
  mv "$HOME/.config/nvim" "$HOME/.config/nvim.before-restore.$(date +%Y%m%d%H%M%S)"
fi
tar -xzf "$backup_dir/dotfiles-config-YYYYMMDDHHMMSS.PID.tar.gz" -C "$HOME"
```

Extraction replaces matching managed paths, so select and inspect the archive
carefully first.
