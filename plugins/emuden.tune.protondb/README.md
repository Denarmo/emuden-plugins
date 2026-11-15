# Tune: ProtonDB

Sets a Steam game up from the ProtonDB reports of machines closest to this one.

1. The page lists the Steam games installed on this computer (not non-Steam shortcuts).
2. Pick a game. The page shows the ProtonDB rating and the closest reports: device, whether
   it worked, how long ago, the Proton version, launch options, problems and notes.
3. The suggestion is the Proton version most of the closest working reports used, and the
   launch options of the closest working report that gives some. Choosing a report uses its
   settings instead.
4. Apply. EmuDEN asks first and lists every change; the old values are kept, and Undo puts
   them back.

## How close a report is

0 to 100, from the report's machine against `den.device.info()`:

| Points | When |
|---|---|
| 40 | the same handheld (Steam Deck, Z2 Go such as the Legion Go S, Z1 / Z1 Extreme, Z2 Extreme), told by processor, graphics or kernel |
| 18 | another handheld |
| 12 + 10 | the same graphics maker, + the same graphics model or codename |
| 4 + 6 | the same processor maker, + the same model |
| 10 | SteamOS on both |
| 4 | memory within 25 % |
| up to 10 | newer than three years, more the newer |
| 4 | the report says it works |

Launch options with shell syntax are never suggested, nor NVIDIA-only variables
(`PROTON_ENABLE_NVAPI`, `__GL_...`) to a device with other graphics. EmuDEN checks them again
before it sets them.

## Where it applies

- **SteamOS, or Linux with Steam's local debugging port on** (Decky Loader turns it on): Proton
  and launch options are set on the game in the running Steam client. Steam downloads an
  official Proton the game is set to the first time it starts. A custom Proton (GE-Proton)
  must be installed first.
- **Windows**: games run without Proton. The page shows the reports, and the game's own
  arguments (what comes after `%command%`) to enter in the game's Properties.

Starting a game is Steam's: nothing is offered before a first start, because EmuDEN does not
start Steam games on these systems.

## Data

- Reports: [Denarmo/protondb-reports](https://github.com/Denarmo/protondb-reports), one small
  file per game made from ProtonDB's monthly data dump
  ([bdefore/protondb-data](https://github.com/bdefore/protondb-data)) under the Open Database
  License, without contributor data, at most 60 reports a game (handhelds and SteamOS first).
  Read from raw.githubusercontent.com, cached for a week.
- Rating: ProtonDB's public summary, `www.protondb.com/api/v1/reports/summaries/<appid>.json`,
  cached for a day.
- The individual reports on protondb.com itself are served under obfuscated addresses
  meant for its own pages; this plugin does not read them.

Data from ProtonDB (protondb.com), made available under the
[Open Database License](https://opendatacommons.org/licenses/odbl/1-0/).

## Test

`lua tests/emuden.tune.protondb/test.lua` (plain Lua 5.4, from the repository root).
