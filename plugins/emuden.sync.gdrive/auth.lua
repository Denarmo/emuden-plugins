-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- Google sign-in with the OAuth 2.0 device flow ("TVs and Limited Input devices"):
-- https://developers.google.com/identity/protocols/oauth2/limited-input-device
-- The refresh token is kept in den.secrets, and the access token too until it expires, so a
-- script that just started (a game's check before it starts) need not ask Google for one.

local util = den.include("util.lua")

local auth = {}

local DEVICE_URL = "https://oauth2.googleapis.com/device/code"
local TOKEN_URL = "https://oauth2.googleapis.com/token"
local REVOKE_URL = "https://oauth2.googleapis.com/revoke"
local DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"
-- Only the files EmuDEN created; nothing else in the user's Drive.
auth.SCOPE = "https://www.googleapis.com/auth/drive.file"
auth.DEFAULT_VERIFICATION_URL = "https://www.google.com/device"

local SECRET_REFRESH = "google.refresh_token"
local FORM = { ["Content-Type"] = "application/x-www-form-urlencoded" }

local access = nil      -- { token, expires }
local client = nil

-- The OAuth client of EmuDEN's Google Cloud project. It is read from oauth_client.json:
-- the copy in the plugin's data folder wins over the one in the package, so the owner can
-- try a client before it ships. Until client_id is filled in, sync is "not set up".
local function load_client()
  local sources = { "oauth_client.json", "package/oauth_client.json" }
  for _, path in ipairs(sources) do
    local text = (path:sub(1, 8) == "package/" or den.files.exists(path)) and den.files.read(path)
    local value = text and den.json.decode(text)
    if type(value) == "table" and type(value.client_id) == "string"
        and value.client_id:match("%.apps%.googleusercontent%.com$") then
      return { id = value.client_id, secret = type(value.client_secret) == "string"
               and value.client_secret or "" }
    end
  end
  return nil
end

function auth.client()
  client = client or load_client()
  return client
end

function auth.configured()
  return auth.client() ~= nil
end

function auth.signed_in()
  return den.secrets.get(SECRET_REFRESH) ~= nil
end

local function post(url, fields)
  local response, err = den.http.request{ url = url, method = "POST", headers = FORM,
                                          body = util.form(fields) }
  if not response then return nil, err or "no connection" end
  local body = response.body and response.body ~= "" and den.json.decode(response.body) or nil
  return response, type(body) == "table" and body or {}
end

local SECRET_ACCESS = "google.access_token"

local function keep(body)
  access = { token = body.access_token, expires = den.now() + (tonumber(body.expires_in) or 3600) - 60 }
  den.secrets.set(SECRET_ACCESS, access)
end

local function drop_access()
  access = nil
  den.secrets.remove(SECRET_ACCESS)
end

-- Step 1: a code for the user. { device_code, user_code, verification_url, expires_in, interval }
function auth.start()
  local c = auth.client()
  if not c then return nil, "Sync with Google Drive is not set up yet." end
  local response, body = post(DEVICE_URL, { client_id = c.id, scope = auth.SCOPE })
  if not response then return nil, body end
  if response.status ~= 200 or not body.device_code then
    return nil, "Google refused the sign-in: " .. tostring(body.error_description or body.error
                                                           or response.status)
  end
  body.verification_url = body.verification_url or body.verification_uri
                          or auth.DEFAULT_VERIFICATION_URL
  body.interval = tonumber(body.interval) or 5
  body.expires_at = den.now() + (tonumber(body.expires_in) or 1800)
  return body
end

-- Step 2: polls until the user has entered the code. still() returns false to stop.
-- true, or nil and "denied", "expired", "cancelled" or a message.
function auth.wait(device, still)
  local c = auth.client()
  local interval = device.interval
  while true do
    den.sleep(interval * 1000)
    if not still() then return nil, "cancelled" end
    if den.now() >= device.expires_at then return nil, "expired" end
    local response, body = post(TOKEN_URL, { client_id = c.id, client_secret = c.secret,
                                             device_code = device.device_code,
                                             grant_type = DEVICE_GRANT })
    if not still() then return nil, "cancelled" end
    if response and response.status == 200 and body.access_token then
      if not body.refresh_token then return nil, "Google sent no refresh token" end
      den.secrets.set(SECRET_REFRESH, body.refresh_token)
      keep(body)
      return true
    end
    local code = response and (body.error or body.error_code)
    if code == "authorization_pending" then
      -- keep polling
    elseif code == "slow_down" then
      interval = interval + 5
    elseif code == "rate_limit_exceeded" or (response and response.status == 429) then
      interval = math.min(interval * 2, 60)
    elseif code == "access_denied" then
      return nil, "denied"
    elseif code == "expired_token" or code == "invalid_grant" then
      return nil, "expired"
    elseif response then
      return nil, "Google refused the sign-in: " .. tostring(body.error_description or code
                                                             or response.status)
    end
    -- no connection: try again at the next interval until the code expires
  end
end

-- A fresh access token from the refresh token. On invalid_grant (revoked, or expired by
-- Google) the user is signed out.
function auth.refresh()
  local c = auth.client()
  local refresh = den.secrets.get(SECRET_REFRESH)
  if not c then return nil, "Sync with Google Drive is not set up yet." end
  if not refresh then return nil, "Not signed in to Google Drive." end
  local response, body
  for attempt = 1, 3 do
    response, body = post(TOKEN_URL, { client_id = c.id, client_secret = c.secret,
                                       refresh_token = refresh, grant_type = "refresh_token" })
    if response and response.status < 500 and response.status ~= 429 then break end
    if attempt < 3 then den.sleep(attempt * 2000) end
  end
  if not response then return nil, body end
  if response.status == 200 and body.access_token then
    keep(body)
    return access.token
  end
  if body.error == "invalid_grant" then
    den.secrets.remove(SECRET_REFRESH)
    drop_access()
    return nil, "The Google sign-in has ended. Sign in again."
  end
  return nil, "Google refused the token: " .. tostring(body.error_description or body.error
                                                       or response.status)
end

function auth.token()
  if not access then
    local kept = den.secrets.get(SECRET_ACCESS)
    if type(kept) == "table" and type(kept.token) == "string" and tonumber(kept.expires) then
      access = { token = kept.token, expires = tonumber(kept.expires) }
    end
  end
  if access and den.now() < access.expires then return access.token end
  return auth.refresh()
end

function auth.forget_access()
  drop_access()
end

-- Signs out here and revokes the grant at Google (best effort).
function auth.sign_out()
  local refresh = den.secrets.get(SECRET_REFRESH)
  if refresh then post(REVOKE_URL, { token = refresh }) end
  den.secrets.remove(SECRET_REFRESH)
  drop_access()
end

return auth
