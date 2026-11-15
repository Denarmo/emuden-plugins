# RetroAchievements (`emuden.retroachievements`)

Achievements from [RetroAchievements.org](https://retroachievements.org) in EmuDEN. The plugin
is the switch, the sign-in, the settings and the pages; EmuDEN's player runs the achievements
with rcheevos 12.5.0 (`den.achievements`, section 4.3 of the app's `docs/feature-plugins.md`).

| What | Where |
|---|---|
| Sign-in | The user types their own RetroAchievements user name and password on the device. The password goes to RetroAchievements once (`r=login2`, https) and is not kept; the token that comes back is kept in this plugin's `den.secrets` (`login`). Sign-out, or removing the plugin with its data, deletes it |
| While a game plays | The app hashes the game as RetroAchievements does, loads its achievements, checks them against the core's memory every frame, and shows pop-ups for unlocks, progress, challenges and leaderboard attempts |
| Hardcore | Off by default. On: loading states, rewind and the resume state are off, as RetroAchievements requires (EmuDEN has no cheats or slow motion). Turning it on while a game runs starts the game again |
| Unlock sound, screenshot | A chime (on by default) and a PNG in `<data>/screenshots/achievements/<console>/` (off by default) |
| Pages | Profile (points, messages), each library game's progress (the running game's from the runtime), an achievement's details |
| Sync | None through EmuDEN: RetroAchievements keeps the progress |

Consoles: those of `feature.systems` with a libretro core. A game run by an engine app (ECP)
has no memory EmuDEN can read, so it has no achievements here.

Permissions: `achievements` (the runtime), `library.read` (the list of games), `http` to
`media.retroachievements.org` (badges, avatars and game icons shown on the pages).

Not affiliated with RetroAchievements.org.
