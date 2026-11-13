-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Which site this ROM Hacks plugin shows. The flow and the pages are shared/romhacks.

return {
  name = "hackdex.app",
  title = "ROM Hacks: hackdex.app",
  url = "https://www.hackdex.app/discover",
  formats = ".bps and .xdelta",
  credits = "The list of base games comes from the site's source (MIT licence, Copyright (c) 2025 The Hackdex Project; see NOTICE.txt in this plugin).",
  about = {
    { "About hackdex.app",
      "The site lists Pokemon hacks for Game Boy, Game Boy Color, Game Boy Advance and DS games. Its patches are .bps or .xdelta files; a hack's Versions page has Download Patch when its creator allows downloads (others can only be patched on the site itself). No account is needed to download. The site's terms do not allow apps or scripts to read it or download from it, which is why you browse and press the button yourself." },
  },
}
