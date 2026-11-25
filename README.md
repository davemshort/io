# io

`io` is a Zsh frontend for [Installomator](https://installomator.org/) on macOS. It provides a searchable label catalog, a per-user application registry, and bulk updates. Installomator handles vendor downloads, version checks, signature and Developer Team ID verification, and deployment.

## Requirements

- macOS on Apple Silicon or Intel, with the bundled Zsh and system utilities.
- An independently installed copy of [Installomator](https://github.com/Installomator/Installomator/releases). This release was checked against 10.10. Deployment requires sudo authorization for the configured engine.
- HTTPS access to GitHub when an upstream catalog is needed. A normal catalog read with a supported local engine works offline.

There are no additional runtime dependencies or telemetry in io.

## Install and upgrade

From a trusted copy of this source tree, run:

```sh
sudo ./scripts/install.sh
io doctor
io version
```

The installer copies the executable, library, license, and version to `/opt/io` with `root:wheel` ownership and links `/usr/local/bin/io` to `/opt/io/bin/io`. Ensure `/usr/local/bin` is on your `PATH`. In Zsh, `whence -va io` shows matching aliases, functions, and commands. If an old alias takes precedence, remove it from your shell configuration and start a new shell, or run `unalias io` for the current session.

To upgrade, run the same installer from the newer source tree. It stages the release before replacing managed files. It checks the existing layout and refuses conflicting files, links, and unexpected contents. Registry and cache data live outside the installation prefix.

To remove io:

```sh
sudo ./scripts/uninstall.sh
```

This removes the managed io files and its matching link. Installomator, managed applications, user configuration, and caches are preserved.

## Commands

| Command | Behavior |
| --- | --- |
| `io search <query>` | Find labels containing a literal, case-insensitive substring. |
| `io available` | Print the catalog, one label per line. |
| `io info <label>` | Show the label, catalog source, and registry status. |
| `io install <label> …` | Deploy one or more apps through Installomator and register each confirmed or already-current app. |
| `io <label>` | Shorthand for installation. Use the explicit form if a label is also a command name. |
| `io add <label>` | Register a catalog label without invoking Installomator. |
| `io list` | Show registered labels. Redirected output contains one label per line. |
| `io list --installed` | Show the local presence and version of registered apps where identifiable. |
| `io outdated [label]` | Check all registered apps or one label for a newer stable release without installing it. |
| `io update <label>` | Run Installomator for a registered label. |
| `io update --all` | Process all registered labels, continue after individual failures, and print totals. |
| `io remove <label>` | Deregister a label. Application files and preferences are preserved. |
| `io replace <cask>`, `io replace --all` | Review and confirm replacing Homebrew casks with Installomator deployments. |
| `io upgrade-engine` | Check for and install a newer stable release of the underlying Installomator engine. |
| `io refresh` | Rebuild the catalog from the configured engine or fetch its upstream fallback. |
| `io doctor` | Check the configured engine, path permissions, registry, and cache without downloading or deploying. |
| `io version`, `io --version` | Print the io and locally configured Installomator versions. |
| `io help`, `io --help`, `io -h` | Show usage. |

```sh
io search brave
io add brave
io list
io update --all
```

Run io as your regular user. The wrapper calls sudo only for deployments. With redirected stdin, it uses `sudo -n` so unattended jobs fail promptly if authorization is unavailable. Use ordinary sudo policy for this machine and keep the Installomator script and its resolved parent directories protected from non-root writes. Group/other-writable paths and paths with ACL entries are rejected for privileged execution.

For example, `io install firefox googlechrome` validates every label before deploying anything, then processes each distinct label in the order given. A batch continues after individual failures and prints a summary.

## Replace Homebrew casks

```sh
io replace rectangle
io replace rectangle -y
io replace brave-browser --label brave
io replace firefox obsidian --dry-run
io replace google-chrome firefox --map google-chrome=googlechrome
io replace --all --exclude slack --exclude rectangle --map brave-browser=brave
```

`io replace` uses exact cask-token matches by default. Use `--label <label>` for a single replacement or repeat `--map <cask>=<label>` for batches. Pass multiple cask tokens to select a batch, or use `--all` to consider every installed cask. Repeat `--exclude <cask>` with `--all` to keep casks under Homebrew. Every selected cask needs a match before a selected batch can proceed. With `--all`, unmatched casks stay under Homebrew.

In an interactive terminal, io shows the plan and asks `Proceed with replacement? [Y/n]` once. Press Enter to proceed or enter `n` to cancel. Use `-y` or `--yes` to skip confirmation. Non-interactive runs show the plan and exit unless you pass `-y`.

Use `--dry-run` to review without a deployment prompt. The preview lists app paths, CLI entries, and other uninstall actions declared in Homebrew's metadata when available. Homebrew's installed cask definition and uninstall scripts determine what actually runs.

If a single cask has no exact label, io suggests similar label names. The interactive picker asks you to select one before showing the migration plan for confirmation. If you use `-y` or run without a terminal, provide `--label` to use a suggested match. Bulk migrations use exact matches and explicit mappings.

Replacement uses Homebrew from `/opt/homebrew/bin` or `/usr/local/bin`. Close the apps before proceeding. io checks sudo authorization before removal, calls `brew uninstall --cask` without `--zap`, and registers each replacement after Installomator confirms deployment or reports it is already current. A failed or unconfirmed replacement stops the run. io prints the Homebrew reinstall command if a cask may need recovery. Earlier successful replacements stay registered.

## Upgrade Installomator

```sh
io upgrade-engine --check  # Compare the installed engine with the latest stable release
io upgrade-engine          # Ask before installing a newer release
io upgrade-engine -y       # Install a newer release without the io prompt
```

The upgrade supports the official package installation at the default Installomator path. io verifies the GitHub release checksum and checks Apple's notarization and the expected Developer ID Installer team before invoking macOS Installer with sudo. After installation it verifies the engine version and refreshes the label catalog. With no terminal, pass `-y` to authorize the upgrade. macOS may still require sudo authentication. Use `--check` to compare the version of a custom installation.

## Configuration and registry

| File | Default path |
| --- | --- |
| Engine configuration | `~/.config/io/config` |
| Registry | `~/.config/io/apps.txt` |
| Catalog cache | `~/.cache/io/labels.txt` |

Set `XDG_CONFIG_HOME` or `XDG_CACHE_HOME` to an absolute directory to replace the corresponding base path. The directories are created when their contents are first needed.

The default engine is `/usr/local/Installomator/Installomator.sh`. To override it, create the configuration file with a literal assignment:

```ini
# Spaces in the path are supported.
installomator_path=/Library/Application Support/Installomator/Installomator.sh
```

Use an absolute path without shell quoting or expansion. Blank lines and full-line comments are supported. The file is parsed as data.

The registry is a plaintext manifest with one lowercase label per line. You can copy it to another Mac. A registered label may represent an app that has been removed, was registered manually, or is no longer in the local catalog. Review `io list` for membership. Use `io remove` to remove a stale label even if the catalog has changed. Registry writes are serialized and use atomic replacement. If editing the manifest by hand, do so while io is idle.

`io list --installed` reads literal hints from the local Installomator script and checks app bundles in `/Applications`, `/Applications/Utilities`, and `~/Applications`. `Not found` refers to those locations. `Unknown` indicates unavailable or ambiguous metadata. `Receipt only` indicates a macOS package receipt, which can survive removal of the installed files. The command does not run label code or query vendors.

`io outdated` compares local bundle release versions with stable release metadata. Initial coverage includes BetterDisplay, draw.io, Joplin, Keka, Markdown Preview, Obsidian, Rectangle, Shottr, Sloth, Visual Studio Code, and Vorssaint. Apps without a supported release source, a comparable version, or a usable response show `Unknown`. A successful report exits zero, including when updates are available or some versions are unknown. The command fetches metadata only and makes no registry or application changes.

## Catalog behavior

Released monolithic Installomator builds embed labels in a generated case statement. io reads that table as text and caches the application labels, including simple literal aliases. It excludes Installomator's special arguments. For an installed engine whose table io cannot read, it requests `Labels.txt` from the exact stable release tag matching that engine's version. If the release tag is unavailable, io reports an error. With no installed engine, catalog-only commands can use the [stable release catalog](https://github.com/Installomator/Installomator/blob/release/Labels.txt). That catalog describes upstream availability.

The cache is tied to the configured local engine's path and file identity. A failed refresh preserves the previous cache. io only reuses a cache compatible with the current engine selection. The installed label table describes labels the engine recognizes. Vendors, architecture, OS version, and label-specific requirements can still affect deployment.

## Deployment outcomes and exit codes

io uses `==>` for command status and progress, with amber warning and red error markers on supported terminals. Deployment progress goes to standard error. Set `NO_COLOR=1` to disable color. Redirected output stays free of color codes. Search and catalog results and redirected registry output remain one label per line.

The Installomator engine package download shows a transfer bar in a terminal and a percentage when the server reports the size. App downloads run inside Installomator, which reports download stages to io.

io uses Installomator's documented production mode, silent notifications, version-aware install behavior, and `BLOCKING_PROCESS_ACTION=silent_fail`. Installomator can use label-specific vendor updaters that have their own behavior. See [Installomator configuration](https://github.com/Installomator/Installomator/wiki/Configuration-and-Variables).

io skips the `adobereaderdc`, `adobereaderdc-install`, and `adobereaderdc-update` deployment labels. Installomator 10.10 can terminate Acrobat Updater from that workflow before the normal blocking-process check.

io reports **Deployment completed** or **Already current** when it recognizes the corresponding Installomator log message. It reports **Skipped** for the engine's blocking-process, App Store protection, and active-display deferral codes. Other nonzero engine results are failures. A zero exit with insufficient evidence is **Outcome unknown**. In particular, an updater may exit zero without verifying whether the app changed. See [Installomator exit codes](https://github.com/Installomator/Installomator/wiki/Installomator-Exit-Codes).

| Exit | Meaning |
| --- | --- |
| `0` | Command succeeded. Requested deployments completed or were already current. |
| `1` | Operational failure, invalid catalog membership, no search matches, or a bulk run containing a failure. |
| `2` | Invalid command usage or argument. |
| `3` | At least one deployment was skipped or had an unknown outcome, with no failures. |

## Development and scope

Run the fixture suite as a regular user on macOS:

```sh
./tests/run.zsh
```

The suite uses a mock engine and simulated sudo and network responses. It exercises catalog fallback and cache recovery, concurrent registry changes, deployment outcomes, invalid inputs, and installation and removal in a temporary system layout. It does not require elevated privileges or touch real applications. Read-only checks against a real engine include `io doctor`, `io version`, and `io search` with an isolated cache.

Phase 1 reports registry membership and recognized engine outcomes. Installed-app inventory, version reporting, manifest import/export commands, dry-run, shell completions, and native package distribution are future work. Custom engine layouts, prerelease version strings, and undocumented vendor updater output may require future compatibility work.

Licensed under the [MIT License](LICENSE).
