# joamag.home

[Home Assistant](https://www.home-assistant.io) in the Omarchy bar: how many lights are on and what the air conditioning is set to, and a popup that switches lights, dims them, sets the thermostat's target and mode, and runs scenes, straight from the bar.

## Signing in

The first time the popup opens it shows a sign-in form: the address of your Home Assistant (`https://home.example.com` or `http://192.168.1.10:8123`), your username and your password. That is the whole setup. The widget runs Home Assistant's own login flow, the one its web page uses, and keeps only the refresh token it hands back, owner-only under `~/.cache/omarchy/home/`; the password is used once and never written anywhere. Access tokens are minted from the refresh token as they expire, and the form comes back by itself if the token is ever revoked.

Accounts with two-factor authentication cannot pass that flow. For those, create a long-lived access token in your Home Assistant profile (Security tab) and put it in the credentials file instead:

```
HOME_ASSISTANT_URL=https://home.example.com
HOME_ASSISTANT_TOKEN=eyJ...
```

The file is `~/.config/omarchy/home.env` (owner-only), parsed rather than sourced, with `KEY=VALUE` lines, whole-line `#` comments and optional wrapping quotes.

## What it shows

With no `entities` setting the widget picks every climate, light and switch Home Assistant has, thermostats first. To curate, list ids in `shell.json`:

```json
{ "id": "joamag.home", "entities": "climate.living_room,light.kitchen,light.office,switch.coffee,scene.movie_night" }
```

`home.sh discover` prints every controllable entity with its name, to pick from. Lights, switches, fans and covers toggle; lights that dim get a brightness slider; scenes and scripts run; thermostats get a target with `-`/`+` and a mode row (off, cool, heat, auto, and whatever else the device offers).

## Finding things in a big house

A real Home Assistant has hundreds of entities, so the popup keeps them out of the way until asked for. **Tabs** above the list split them by kind (All, Climate, Lights, Switches, Covers, Scenes, each with its count); `[` and `]` step through them, the digits jump straight to one, and the chosen tab is remembered. The list **scrolls** inside the popup and stops after sixty rows with a note saying how many more there are. The **filter** field narrows every tab at once: `/` focuses it, every word typed has to appear in the name or the id (so `bedroom radiant` finds the radiant thermostat of any bedroom), Enter or Down lands on the first match ready to act on, and Esc clears it.

## Interactions

- Left click on the bar: open the popup. Middle click: refresh. Right click: open Home Assistant in the browser.
- Click a light, switch, fan or cover row (or its switch) to toggle it, a scene to run it. On a thermostat, `-`/`+` step the target by half a degree (or the device's own step when it is coarser; the result always lands on the device's grid) and the mode row picks the mode.
- `j`/`k` move over rows, Enter toggles or runs the row (cycles the mode on a thermostat), `h`/`l` step a thermostat's target or a light's brightness, `[`/`]` and `1`-`9` change tab, `/` filters, `a` turns every listed light off, `r` refreshes, `o` opens the browser, Esc closes, Tab switches to the neighbouring panel.

## Settings

Inline on the widget entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `entities` | `""` | Comma separated entity ids; empty picks every climate, light and switch |
| `tab` | `"all"` | The tab the popup opens on; remembered as you switch |
| `barMode` | `"both"` | `both` (lights lit and the thermostat's target), `lights`, `climate` or `none` |
| `refreshIntervalSec` | `30` | Refresh cadence; the popup refreshes on open when its data is older than ten seconds |
| `credentialsFile` | `""` | Alternative credentials file |

## IPC

```
omarchy-shell joamag.home toggle
omarchy-shell joamag.home refresh
omarchy-shell joamag.home version
```

## Data source

`home.sh` wraps `curl` around the REST API: one `GET /api/states` per refresh, condensed with `jq` to the entities the widget shows, and `POST /api/services/...` for actions, each answering with the refreshed list so the popup never needs a second round trip. When Home Assistant is unreachable the popup shows the last fetched state, marked CACHED.
