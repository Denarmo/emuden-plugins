-- SPDX-FileCopyrightText: Copyright 2026 EmuDEN contributors
-- SPDX-License-Identifier: GPL-3.0-or-later

-- The provider over Google Drive API v3. Remote files live in a visible "EmuDEN" folder in
-- My Drive, one subfolder per category, then the folders of the portable name
-- ("saves/gba/Game.srm" is EmuDEN/saves/gba/Game.srm). rev is the file's Drive `version`.
-- With the drive.file scope Drive shows this app only the files it created, so one listing
-- of every visible file is the whole remote side.

local util = den.include("util.lua")

return function(auth)
  local drive = {}

  local API = "https://www.googleapis.com/drive/v3"
  local UPLOAD = "https://www.googleapis.com/upload/drive/v3"
  local FOLDER = "application/vnd.google-apps.folder"
  local ROOT_NAME = "EmuDEN"
  local FILE_FIELDS = "id,name,mimeType,parents,size,modifiedTime,version,md5Checksum,trashed"
  drive.MULTIPART_LIMIT = 5 * 1024 * 1024
  local RETRIES = 6
  local RATE_REASONS = { rateLimitExceeded = true, userRateLimitExceeded = true,
                         backendError = true }

  local root = nil       -- id of the EmuDEN folder
  local folders = {}     -- "saves/gba" -> folder id ("" is the root)
  local files = {}       -- portable name -> { id, version, size, modified }

  local function decode(response)
    local body = response and response.body
    if type(body) ~= "string" or body == "" then return {} end
    local value = den.json.decode(body)
    return type(value) == "table" and value or {}
  end

  local function reason(body)
    local e = type(body.error) == "table" and body.error or {}
    local first = type(e.errors) == "table" and e.errors[1] or {}
    return first.reason or e.status, e.message
  end

  local function backoff(attempt, response)
    local wait = tonumber(util.header(response, "Retry-After"))
    if not wait then wait = math.min(2 ^ (attempt - 1), 32) + math.random() end
    den.sleep(math.floor(wait * 1000))
  end

  -- One Drive call with the access token: refreshes once on 401, backs off on 429, 5xx and
  -- 403 rate limits. Returns the response, or nil and a message. plain: no retries but the
  -- refresh, for the upload steps that ask Google how far they got instead.
  local function call(request, plain)
    local refreshed = false
    local response, err
    for attempt = 1, RETRIES do
      local token, why = auth.token()
      if not token then return nil, why end
      local sent = {}
      for k, v in pairs(request) do sent[k] = v end
      sent.headers = {}
      for k, v in pairs(request.headers or {}) do sent.headers[k] = v end
      sent.headers["Authorization"] = "Bearer " .. token
      response, err = den.http.request(sent)
      if not response then
        if plain or attempt >= 3 then return nil, err or "no connection" end
        backoff(attempt)
      else
        local status = response.status
        if status == 401 and not refreshed then
          refreshed = true
          auth.forget_access()
        elseif status == 429 or status >= 500
            or (status == 403 and RATE_REASONS[reason(decode(response)) or ""]) then
          if plain or attempt == RETRIES then return response end
          backoff(attempt, response)
        else
          return response
        end
      end
    end
    return response, err
  end
  drive.call = call

  local function failure(response, what)
    if not response then return what end
    local why, message = reason(decode(response))
    if response.status == 403 and why == "storageQuotaExceeded" then
      return "Your Google Drive is full"
    end
    return string.format("%s: Google Drive answered %d%s", what, response.status,
                         message and (" (" .. message .. ")") or "")
  end

  -- den.json.encode of an empty table is "[]"; Drive wants an object.
  local function object()
    return den.json.decode("{}")
  end

  local function json_call(method, url, value)
    local response, err = call{ url = url, method = method, body = den.json.encode(value),
                                headers = { ["Content-Type"] = "application/json; charset=UTF-8" } }
    return response, err
  end

  local function search(q, fields, each)
    local token = nil
    repeat
      local params = { q = q, spaces = "drive", pageSize = 1000,
                       fields = "nextPageToken,files(" .. fields .. ")" }
      if token then params.pageToken = token end
      local response, err = call{ url = API .. "/files" .. util.query(params) }
      if not response then return nil, err end
      if response.status ~= 200 then return nil, failure(response, "Listing failed") end
      local body = decode(response)
      for _, file in ipairs(body.files or {}) do each(file) end
      token = body.nextPageToken
    until not token or token == den.json.null
    return true
  end

  local function find_child(parent, name, folder)
    local q = "name = " .. util.quote(name) .. " and " .. util.quote(parent) .. " in parents"
        .. " and trashed = false and mimeType " .. (folder and "=" or "!=") .. " '" .. FOLDER .. "'"
    local found = nil
    local ok, err = search(q, FILE_FIELDS, function(file)
      if not found or (file.modifiedTime or "") > (found.modifiedTime or "") then found = file end
    end)
    if not ok then return nil, err end
    return found
  end

  local function create_folder(name, parent)
    local meta = { name = name, mimeType = FOLDER }
    if parent then meta.parents = { parent } end
    local response, err = json_call("POST", API .. "/files?fields=id", meta)
    if not response then return nil, err end
    if response.status ~= 200 then return nil, failure(response, "Creating " .. name .. " failed") end
    return decode(response).id
  end

  -- The EmuDEN folder: remembered, else found in My Drive, else made.
  local function ensure_root()
    if root then return root end
    local known = den.storage.get("root_id")
    if type(known) == "string" then
      local response = call{ url = API .. "/files/" .. known .. "?fields=id,trashed" }
      if response and response.status == 200 and not decode(response).trashed then
        root = known
      elseif response and response.status ~= 404 and response.status ~= 200 then
        return nil, failure(response, "Opening the EmuDEN folder failed")
      elseif not response then
        return nil, "no connection"
      end
    end
    if not root then
      local found, err = find_child("root", ROOT_NAME, true)
      if err then return nil, err end
      root = found and found.id
      if not root then
        local id, why = create_folder(ROOT_NAME, nil)
        if not id then return nil, why end
        root = id
        for _, category in ipairs(util.CATEGORIES) do
          folders[category] = create_folder(category, root)
        end
      end
      den.storage.set("root_id", root)
    end
    folders[""] = root
    return root
  end
  drive.ensure_root = ensure_root

  local function split(path)
    local dir, name = path:match("^(.*)/([^/]+)$")
    return dir or "", name or path
  end

  -- The folder id of dir ("saves/gba"), made when create is set; nil when it is not there.
  local function folder_of(dir, create)
    local id, err = ensure_root()
    if not id then return nil, err end
    if dir == "" then return id end
    if folders[dir] then return folders[dir] end
    local key = ""
    for part in dir:gmatch("[^/]+") do
      key = key == "" and part or key .. "/" .. part
      if not folders[key] then
        local found, why = find_child(id, part, true)
        if why then return nil, why end
        if found then
          folders[key] = found.id
        elseif create then
          local made, failed = create_folder(part, id)
          if not made then return nil, failed end
          folders[key] = made
        else
          return nil
        end
      end
      id = folders[key]
    end
    return id
  end

  local function entry_of(file)
    return { id = file.id, version = file.version and tostring(file.version),
             size = tonumber(file.size) or 0, modified = util.parse_time(file.modifiedTime) }
  end

  -- The file at a portable name now: { id, version, ... } or nil when there is none.
  local function lookup(path)
    local dir, name = split(path)
    local parent, err = folder_of(dir, false)
    if err then return nil, err end
    if not parent then return nil end
    local found, why = find_child(parent, name, false)
    if why then return nil, why end
    files[path] = found and entry_of(found) or nil
    return files[path]
  end

  function drive.list(prefix)
    local id, err = ensure_root()
    if not id then return nil, err end
    local by_id = {}
    local ok, why = search("trashed = false", FILE_FIELDS, function(file) by_id[file.id] = file end)
    if not ok then return nil, why end
    local paths = { [id] = "" }
    local function path_of(file_id, depth)
      if paths[file_id] then return paths[file_id] end
      local file = by_id[file_id]
      if not file or depth > 32 or type(file.parents) ~= "table" then return nil end
      local parent = path_of(file.parents[1], depth + 1)
      if not parent then return nil end
      paths[file_id] = parent == "" and file.name or parent .. "/" .. file.name
      return paths[file_id]
    end
    folders, files = { [""] = id }, {}
    local out, seen = {}, {}
    for file_id, file in pairs(by_id) do
      local path = path_of(file_id, 0)
      if path and file.mimeType == FOLDER then
        folders[path] = file_id
      elseif path and not util.refused(path) then
        local entry = entry_of(file)
        local before = seen[path]
        if before then
          den.log("two remote files are named " .. path .. "; using the newer one")
        end
        if not before or (entry.modified or 0) > (before.modified or 0) then
          seen[path] = entry
          files[path] = entry
        end
      end
    end
    for path, entry in pairs(seen) do
      if not prefix or path:sub(1, #prefix) == prefix then
        out[#out + 1] = { path = path, size = entry.size, modified = entry.modified,
                          rev = entry.version }
      end
    end
    table.sort(out, function(a, b) return a.path < b.path end)
    return out
  end

  local function known(path)
    if files[path] then return files[path] end
    return lookup(path)
  end

  -- progress(done, total) is the host's; it takes den.http.request's fraction as well.
  function drive.get(path, local_path, progress)
    local file, err = known(path)
    if not file then return nil, err or "not found" end
    local response, why = call{ url = API .. "/files/" .. file.id .. "?alt=media",
                                to_file = local_path, on_progress = progress }
    if not response then return nil, why end
    if response.status == 404 then
      files[path] = nil
      return nil, "not found"
    end
    if response.status ~= 200 then return nil, failure(response, "Download failed") end
    return true
  end

  -- The host builds the multipart/related body: the metadata, then the file itself.
  local function multipart(url, method, meta, mime, local_path)
    return call{ url = url .. "uploadType=multipart&fields=" .. FILE_FIELDS, method = method,
                 multipart_type = "related",
                 multipart = { { content_type = "application/json; charset=UTF-8",
                                 value = den.json.encode(meta) },
                               { content_type = mime, file = local_path } } }
  end

  local function done(response)
    return response and (response.status == 200 or response.status == 201)
  end

  local function gone(response)
    return response and (response.status == 404 or response.status == 410)
  end

  -- How much of the upload Google has. The next offset; or the finished upload's answer;
  -- or nil and the answer when the session is lost or the question failed.
  local function uploaded(session, size)
    local response = call({ url = session, method = "PUT",
                            headers = { ["Content-Range"] = "bytes */" .. size } }, true)
    if done(response) then return nil, response end
    if not response or response.status ~= 308 then return nil, nil, response end
    local last = tonumber((util.header(response, "range") or ""):match("^bytes=0%-(%d+)$"))
    return last and last + 1 or 0
  end

  -- Resumable, in chunks: a session from the metadata, then the file CHUNK bytes at a time,
  -- each answered with how much Google has. The session is kept in the plugin's storage
  -- (Google keeps one a week), so an upload cut by the app closing, a game starting or the
  -- network goes on from there in a later run instead of from the start. progress(done, total)
  -- moves after every chunk; den.sync.status().stopping ends the call between two chunks.
  drive.CHUNK = 16 * 1024 * 1024 -- a multiple of 256 KiB, as Drive asks

  local function stopping()
    local status = den.sync.status()
    return type(status) == "table" and status.stopping == true
  end

  local function next_offset(response)
    local last = tonumber((util.header(response, "range") or ""):match("^bytes=0%-(%d+)$"))
    return last and last + 1 or 0
  end

  local function resumable(url, method, meta, mime, local_path, size, key, modified, progress)
    local stamp = tostring(modified or 0)
    for _ = 1, 2 do
      local session, offset = nil, 0
      local kept = den.storage.get(key)
      if type(kept) == "table" and kept.size == size and kept.modified == stamp
          and type(kept.session) == "string" then
        local at, finished, lost = uploaded(kept.session, size)
        if finished then
          den.storage.remove(key)
          return finished
        end
        if at then
          session, offset = kept.session, at
        elseif not gone(lost) then
          return nil, "no connection" -- kept for the next run
        end
      end
      if not session then
        den.storage.remove(key)
        local response, err = call{ url = url .. "uploadType=resumable&fields=" .. FILE_FIELDS,
                                    method = method, body = den.json.encode(meta),
                                    headers = { ["Content-Type"] = "application/json; charset=UTF-8",
                                                ["X-Upload-Content-Type"] = mime,
                                                ["X-Upload-Content-Length"] = tostring(size) } }
        if not response then return nil, err end
        session = util.header(response, "location")
        if response.status ~= 200 or not session then return response end
        den.storage.set(key, { session = session, size = size, modified = stamp })
      end
      local failures = 0
      local lost = false
      while not lost do
        if progress then progress(offset, size) end
        if stopping() then return nil, "cancelled" end
        local length = math.min(drive.CHUNK, size - offset)
        local response = call({ url = session, method = "PUT", body_file = local_path,
                                body_offset = offset, body_length = length,
                                headers = { ["Content-Type"] = mime,
                                            ["Content-Range"] = string.format("bytes %d-%d/%d", offset,
                                                                              offset + length - 1, size) } },
                              true)
        local status = response and response.status or 0
        if done(response) then
          den.storage.remove(key)
          if progress then progress(size, size) end
          return response
        elseif gone(response) then
          lost = true
        elseif status == 308 then
          offset, failures = next_offset(response), 0
        elseif status >= 400 and status < 500 and status ~= 403 and status ~= 408 and status ~= 429 then
          den.storage.remove(key)
          return response
        else
          failures = failures + 1
          if failures > 4 then return response or nil, "no connection" end
          backoff(failures, response)
          local at, finished, gone_now = uploaded(session, size)
          if finished then
            den.storage.remove(key)
            return finished
          end
          if gone(gone_now) then lost = true end
          offset = at or offset
        end
      end
      den.storage.remove(key) -- the session ran out: once more with a new one
    end
    return nil, "Upload failed: Google Drive dropped the upload twice"
  end

  -- modified (Unix seconds) is optional; the host may pass the local file's time so the
  -- remote copy carries it.
  function drive.put(path, local_path, rev, modified, progress)
    local refused = util.refused(path)
    if refused then return nil, refused end
    local current, err = lookup(path)
    if err then return nil, err end
    if current and (rev == nil or tostring(rev) ~= current.version) then
      return nil, "conflict"
    end
    local dir, name = split(path)
    local meta = object()
    if tonumber(modified) then meta.modifiedTime = util.format_time(tonumber(modified)) end
    local url, method
    if current then
      url, method = UPLOAD .. "/files/" .. current.id .. "?", "PATCH"
    else
      local parent, why = folder_of(dir, true)
      if not parent then return nil, why or "no folder" end
      meta.name, meta.parents = name, { parent }
      url, method = UPLOAD .. "/files?", "POST"
    end
    local mime = util.mime(name)
    local size, why = den.files.size(local_path)
    if not size then return nil, why end
    local response
    if size < drive.MULTIPART_LIMIT then
      response, why = multipart(url, method, meta, mime, local_path)
    else
      response, why = resumable(url, method, meta, mime, local_path, size, "upload:" .. path, modified,
                                progress)
    end
    if not response then return nil, why end
    if response.status ~= 200 and response.status ~= 201 then
      return nil, failure(response, "Upload failed")
    end
    local file = decode(response)
    if not file.id then return nil, "Upload failed: Google Drive sent no file" end
    files[path] = entry_of(file)
    return files[path].version
  end

  -- Moves the file to the Drive trash (Google keeps it 30 days), not a permanent delete.
  function drive.delete(path)
    local file, err = known(path)
    if err then return nil, err end
    if not file then return true end
    local response, why = json_call("PATCH", API .. "/files/" .. file.id .. "?fields=id",
                                    { trashed = true })
    if not response then return nil, why end
    files[path] = nil
    if response.status == 200 or response.status == 404 then return true end
    return nil, failure(response, "Delete failed")
  end

  -- { account, name, used, total, free } (total and free nil for unlimited storage)
  function drive.status()
    local response, err = call{ url = API .. "/about" .. util.query{
      fields = "user(displayName,emailAddress),storageQuota(limit,usage)" } }
    if not response then return nil, err end
    if response.status ~= 200 then return nil, failure(response, "Account check failed") end
    local body = decode(response)
    local user, quota = body.user or {}, body.storageQuota or {}
    local used, total = tonumber(quota.usage), tonumber(quota.limit)
    return { account = user.emailAddress, name = user.displayName, used = used, total = total,
             free = total and used and math.max(total - used, 0) or nil }
  end

  function drive.forget()
    root, folders, files = nil, {}, {}
    den.storage.remove("root_id")
  end

  return drive
end
