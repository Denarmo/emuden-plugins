-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- The one Helix SR release this plugin installs. Upstream has replaced assets under one tag
-- before, so the ZIP is pinned by size and SHA-256: the asset's digest in GitHub's release API
-- and the release's SHA256SUMS.txt, which agreed on 2026-11-17. The library's path and size are
-- from the ZIP's central directory.
return {
  version = "3.4.0",
  url = "https://github.com/lonewolf0622/HelixSR/releases/download/v3.4.0/HelixSR-3.4.0.zip",
  name = "HelixSR-3.4.0.zip",
  size = 290684780,
  sha256 = "c82dcb88f789a6b0d2b6ae54b4e9fa94289da3c5e9c8167318284aa18d67e2b9",
  -- The prebuilt HLX FSR 4 library, upstream's "FSR drop-in".
  library = "HelixSR-3.4.0/HLX-FSR4/amd_fidelityfx_upscaler_dx12.dll",
  library_size = 58185808,
}
