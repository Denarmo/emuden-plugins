-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Which site this ROM Hacks plugin shows. The flow and the pages are shared/romhacks.

return {
  name = "whackahack.com",
  title = "ROM Hacks: whackahack.com",
  url = "https://whackahack.com/foro/",
  formats = ".ips, .ups, .bps, .xdelta, .aps, also inside a .zip or .7z",
  warning = "Many threads link to file hosts and some offer already patched games: EmuDEN installs patch files only.",
  about = {
    { "About whackahack.com",
      "Whack a Hack! is a Spanish-language community for Pokemon fan games; ROM hacks are shown in its forum (Exposicion de ROM Hacking). A thread's files are forum attachments on whackahack.com or links to file hosts such as MediaFire, MEGA or Google Drive. For a link to a file host EmuDEN asks before leaving the forum. If the forum wants you to sign in to see a link or an attachment, you sign in yourself in the page; the plugin never sees it. Fan games made with RPG Maker and already patched games are not patches and are refused." },
  },
}
