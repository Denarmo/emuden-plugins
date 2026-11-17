-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- The one lsfg-vk build this plugin installs, from the project's own build server. lsfg-vk is
-- CC BY-NC-ND 4.0: it is downloaded as published and never part of this package.
return {
  version = "2.0.0",
  url = "https://builds.lsfg-vk.dev/lsfg-vk-2.0.0.tar.xz",
  name = "lsfg-vk-2.0.0.tar.xz",
  -- Downloaded and read on 2026-11-17 (file dated 2026-09-05): plain LZMA2 with CRC64, the
  -- four layer files below, and a manifest with DISABLE_LSFGVK as its disable_environment.
  -- builds.lsfg-vk.dev publishes no checksum of its own.
  size = 561348,
  sha256 = "08bdbdf373a111022df87dac7aa87e3b564bb841f961552e3ca85fea12b5aa74",
  layers = {
    { manifest = "share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json",
      library = "lib/liblsfg-vk-layer.so" },
    -- For 32-bit games. Left out when the build has none.
    { manifest = "share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.x86.json",
      library = "lib/liblsfg-vk-layer.x86.so", optional = true },
  },
}
