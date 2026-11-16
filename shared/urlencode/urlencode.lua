-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Percent-encoding of everything but the unreserved characters of RFC 3986, for query values
-- and form fields. Shared by the plugins that name "urlencode" in their .shared file:
-- local urlencode = den.include("urlencode.lua")

return function(text)
  return (tostring(text):gsub("[^%w%-%._~]", function(c)
    return string.format("%%%02X", c:byte())
  end))
end
