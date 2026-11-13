-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Which site this ROM Hacks plugin shows. The flow and the pages are shared/romhacks.

return {
  name = "pokeharbor.com",
  title = "ROM Hacks: pokeharbor.com",
  url = "https://www.pokeharbor.com/",
  formats = ".ips, .ups, .bps, .xdelta, .aps, also inside a .zip",
  warning = "pokeharbor.com says its games are pre-patched: those downloads are full game files and EmuDEN refuses them. Only an entry that links to a patch file can be installed here.",
  about = {
    { "About pokeharbor.com",
      "The site lists Pokemon hacks and states that all its games are pre-patched: its download buttons lead to full game files on file hosts (MediaFire, MEGA). EmuDEN does not download games, so such a file is refused with the message \"EmuDEN only installs patch files; this is a full game file\", also when it comes inside a zip. You can still browse the site here, and where an entry links to a patch (.ips, .ups, .bps, .xdelta), that patch installs on your own copy of the base game. For a link to a file host EmuDEN asks before leaving the site.", "warning" },
  },
}
