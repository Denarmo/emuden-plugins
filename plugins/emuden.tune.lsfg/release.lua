-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- The one lsfg-vk build this plugin installs, from the project's own build server. lsfg-vk is
-- CC BY-NC-ND 4.0: it is downloaded as published and never part of this package.
return {
  version = "2.0.0",
  url = "https://builds.lsfg-vk.dev/lsfg-vk-2.0.0.tar.xz",
  name = "lsfg-vk-2.0.0.tar.xz",
  -- The Content-Length builds.lsfg-vk.dev gave on 2026-11-17 (file dated 2026-09-05).
  size = 561348,
  -- NOT VERIFIED, EMPTY ON PURPOSE: builds.lsfg-vk.dev publishes no checksum for its builds.
  -- While this is empty the plugin downloads nothing and its page says so. Fill in the
  -- SHA-256 (64 hex digits) of the reviewed lsfg-vk-2.0.0.tar.xz before publishing.
  sha256 = "",
  -- NOT VERIFIED against the tarball itself: the names follow lsfg-vk 2.0.0's CMake install
  -- rules (lsfg-vk-layer/CMakeLists.txt), with nothing in front of lib/ and share/.
  layers = {
    { manifest = "share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.json",
      library = "lib/liblsfg-vk-layer.so" },
    -- For 32-bit games. Left out when the build has none.
    { manifest = "share/vulkan/implicit_layer.d/VkLayer_LSFGVK_frame_generation.x86.json",
      library = "lib/liblsfg-vk-layer.x86.so", optional = true },
  },
}
