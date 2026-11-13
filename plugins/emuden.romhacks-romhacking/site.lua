-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Which site this ROM Hacks plugin shows. The flow and the pages are shared/romhacks.

return {
  name = "romhacking.net",
  title = "ROM Hacks: romhacking.net",
  url = "https://www.romhacking.net/",
  formats = ".ips, .bps, .ups, .xdelta, .ppf, .aps, also inside a .zip",
  warning = "Many files on romhacking.net are .7z or .rar archives, which EmuDEN cannot open yet. Download such a file in your own browser, unpack it and use Choose a patch file.",
  about = {
    { "About romhacking.net",
      "The site stopped taking new hacks and translations in August 2024 and is read-only since; its files were also given to the Internet Archive (archive.org), which this plugin may show as well. Hacks and translations cover many consoles (NES, Super Nintendo, Mega Drive, Game Boy, Game Boy Advance, Nintendo 64, PlayStation and more). Most patches are .ips or .bps, .xdelta or .ppf for large games, packed in a .zip, .7z or .rar. A zip is opened and its patch taken; .7z and .rar are not supported yet. An .ips patch does not name its game, so you choose it; each entry's page says which dump it needs (also whether with or without a header)." },
  },
}
