# joamag's Omarchy plugins

A collection of plugins for the [Omarchy](https://omarchy.org) shell (Omarchy 4.x, `omarchy-shell` on Quickshell). Each plugin lives in its own folder under `plugins/` and follows the standard `manifest.json` contract, so any folder can be dropped into `~/.config/omarchy/plugins/<id>/` or published as its own git repository for `omarchy plugin add`.

## Plugins

| Plugin | Kind | What it does |
|---|---|---|
| [`joamag.sysmon`](plugins/joamag.sysmon/) | bar-widget | CPU / memory / temperature / GPU / disk in the bar, popup with live meters and top processes |
| [`joamag.docker`](plugins/joamag.docker/) | bar-widget | Running container count in the bar, popup to start / stop / restart containers or open lazydocker |
| [`joamag.stocks`](plugins/joamag.stocks/) | bar-widget | S&P 500, NASDAQ, Dow and a stock watchlist in the bar, popup with range charts and sparklines |
| [`joamag.github`](plugins/joamag.github/) | bar-widget | Review requests, your PRs with CI state, assigned issues and unread notifications via the gh CLI |
| [`joamag.isabella`](plugins/joamag.isabella/) | bar-widget | Today's Isabella house checklist: pending and done counts, tick / cancel / delay from the popup |

## Development

Plugins are symlinked into the shell's plugin directory so edits happen in this repo:

```bash
bin/dev-link                      # validate + symlink every plugin, rescan the shell
bin/dev-link joamag.sysmon        # just one
omarchy plugin enable joamag.sysmon --section right
bin/reload                        # after editing QML: restarts the shell (rescanning alone keeps the old compiled code)
bin/reload --rescan               # manifest-only changes, no restart
bin/dev-unlink                    # remove the symlinks again
```

Checks:

```bash
bin/validate-all   # omarchy plugin validate + repo conventions (id namespace, README)
bin/lint           # qmllint syntax pass over every QML file
bin/test           # unit tests with coverage (Node's built-in runner, no dependencies)
```

Tests live in `test/`, one file per plugin (`test/<name>.test.js`) plus `test/helpers.js` and API fixtures under `test/fixtures/`. Each file walks the plugin's `Model.js` functions in declaration order, then drives the plugin's shell script end to end against fakes on `PATH` (`gh`, `docker`, `curl`) or an in-process HTTP server, so no network or credentials are needed. Coverage is measured over the `Model.js` libraries and gated at 90% lines and functions; the QML panels only run inside omarchy-shell and are covered by `bin/lint` plus a manual pass.

Editing `~/.config/omarchy/shell.json` by hand needs `omarchy-shell shell reloadConfig` before widgets see the new settings. Shell log for debugging plugin load errors: `qs log -p /usr/share/omarchy/shell`. Each plugin answers `omarchy-shell <id> version` so you can confirm which build the shell is running.

## Conventions

- Plugin ids use the `joamag.*` namespace and the folder name equals the id.
- Every plugin has a `README.md` describing interactions, settings and IPC.
- Bar-widget plugins extend `qs.Ui` `Panel` and follow the first-party popup pattern (`KeyboardPanel` + `PanelKeyCatcher`), so keyboard navigation, tooltips and theming match the built-in widgets.
- Helper scripts ship inside the plugin folder and are resolved from the QML file location, never from `$OMARCHY_PATH`.
- Plugins never need root and never write outside `~/.config/omarchy/shell.json` (through the shell's own settings API).
- Custom properties on `Item`-derived components avoid the built-in anchor line names (`baseline`, `left`, `top`, ...); those are FINAL and make the whole widget fail to load with "Cannot override FINAL property".

## Publishing a plugin

`omarchy plugin add <git-url>` expects `manifest.json` at the repository root, so a plugin is published by splitting its folder into a standalone repo:

```bash
git subtree split --prefix=plugins/joamag.sysmon -b publish/joamag.sysmon
git push git@github.com:joamag/omarchy-sysmon.git publish/joamag.sysmon:main
```
