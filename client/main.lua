local state = {}
local serverOffset = 0

SSF = {}

local function notify(kind, text) Bridge.notify(kind, text) end

local function call(name, ...) return lib.callback.await(name, false, ...) end

local function serverNow() return GetCloudTimeAsInt() + serverOffset end

local function salePrice(sale)
    local t = math.min(1.0, math.max(0.0, (serverNow() - sale.startAt) / math.max(1, sale.endAt - sale.startAt)))
    return math.floor((sale.from + (sale.to - sale.from) * t) / 10 + 0.5) * 10
end

local function isPolice()
    local name, grade = Bridge.job()
    local min = Config.PoliceJobs[name or '']
    return min ~= nil and grade >= min
end

local DoorById, Interiors, MainDoors = {}, {}, FacilityData.mainDoors
for _, d in ipairs(FacilityData.doors or {}) do
    DoorById[d.id] = d
    if d.interior and (d.id == d.unit or not Interiors[d.unit]) then Interiors[d.unit] = d.interior end
end

local function doorOpen(id) return GlobalState['ssf_door_' .. id] == true end

local function mainOpen(unit)
    for _, id in ipairs(MainDoors[unit] or {}) do
        if doorOpen(id) then return true end
    end
    return false
end

local function gateOpen(key)
    local s = GlobalState['ssf_gate_' .. key]
    if s == nil then return Config.Doors.gateOpenAtStart end
    return s
end

local function axes(heading)
    local r = math.rad(heading)
    return vector3(math.cos(r), math.sin(r), 0.0), vector3(-math.sin(r), math.cos(r), 0.0)
end

local function inwardOf(d)
    local right, inw = axes(d.heading)
    if d.kind == 'cdoor' then return -right end
    return inw
end

local function insideOf(d)
    local inw = inwardOf(d)
    local rel = GetEntityCoords(cache.ped) - d.coords
    return rel.x * inw.x + rel.y * inw.y > 0.4
end

local function showHints(title, keys)
    local lines = { ('**%s**'):format(title) }
    for _, k in ipairs(keys) do lines[#lines + 1] = ('[%s] %s'):format(k.key, k.text) end
    Bridge.showText(table.concat(lines, '  \n'))
end

local function hideHints() Bridge.hideText() end

RegisterNetEvent('ssf:state', function(s, t)
    state = s or {}
    if t then serverOffset = t - GetCloudTimeAsInt() end
end)

local zones = {}

local function buildZone(pts)
    if type(pts) ~= 'table' or #pts < 3 then return nil end
    local z = { pts = pts, minX = math.huge, minY = math.huge, maxX = -math.huge, maxY = -math.huge }
    for _, p in ipairs(pts) do
        z.minX, z.minY = math.min(z.minX, p.x), math.min(z.minY, p.y)
        z.maxX, z.maxY = math.max(z.maxX, p.x), math.max(z.maxY, p.y)
    end
    return z
end

local function setZones(value)
    local out = {}
    for key, pts in pairs(type(value) == 'table' and value or {}) do out[key] = buildZone(pts) end
    zones = out
end
setZones(GlobalState.ssf_zones)
AddStateBagChangeHandler('ssf_zones', 'global', function(_, _, value) setZones(value) end)

local function insidePoly(pts, x, y)
    local inside, j = false, #pts
    for i = 1, #pts do
        local a, b = pts[i], pts[j]
        if (a.y > y) ~= (b.y > y) and x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x then inside = not inside end
        j = i
    end
    return inside
end

local function edgeDistance(pts, x, y)
    local best, j = math.huge, #pts
    for i = 1, #pts do
        local a, b = pts[j], pts[i]
        local dx, dy = b.x - a.x, b.y - a.y
        local t = math.max(0.0, math.min(1.0, ((x - a.x) * dx + (y - a.y) * dy) / math.max(1e-6, dx * dx + dy * dy)))
        local ex, ey = a.x + dx * t - x, a.y + dy * t - y
        best = math.min(best, math.sqrt(ex * ex + ey * ey))
        j = i
    end
    return best
end

local function inZone(key, pos, wasIn)
    local z = zones[key]
    if not z then
        local s = FacilityData.siteByKey[key]
        return s ~= nil and #(pos - (s.lot.min + s.lot.max) / 2) < (wasIn and 190.0 or 140.0)
    end
    local m = wasIn and Config.Zone.exitMargin or 0.0
    if pos.x < z.minX - m or pos.x > z.maxX + m or pos.y < z.minY - m or pos.y > z.maxY + m then return false end
    if insidePoly(z.pts, pos.x, pos.y) then return true end
    return wasIn and edgeDistance(z.pts, pos.x, pos.y) <= m
end

SSF.call, SSF.notify, SSF.state, SSF.inZone = call, notify, function() return state end, inZone
SSF.serverNow, SSF.salePrice, SSF.axes = serverNow, salePrice, axes
SSF.Interiors, SSF.DoorById, SSF.doorOpen, SSF.mainOpen = Interiors, DoorById, doorOpen, mainOpen
SSF.showHints, SSF.hideHints = showHints, hideHints

local function withCode(title, run)
    CreateThread(function()
        local pin = Bridge.askCode(title)
        if pin then run(pin) end
    end)
end

local function storageOptions(p)
    local d = Config.InteractDistance
    local main = MainDoors[p.id] ~= nil
    local box = p.size == 'container'
    local function st() return state[p.id] end
    return {
        { name = 'ssf_rent_' .. p.id, label = locale('opt_rent', p.id), icon = 'rent', distance = d,
          canInteract = function() return st() == nil end,
          onSelect = function() SSF.openUnit(p.id) end },
        { name = 'ssf_sale_' .. p.id, label = locale('opt_view_sale'), icon = 'sale', distance = d + 2.0,
          canInteract = function() local s = st() return s ~= nil and s.sale ~= nil end,
          onSelect = function() SSF.openUnit(p.id) end },
        { name = 'ssf_open_' .. p.id, label = locale('opt_open_stash'), icon = 'stash', distance = d,
          canInteract = function() local s = st() return s ~= nil and s.access and not s.sale end,
          onSelect = function() call('ssf:open', p.id) end },
        { name = 'ssf_panel_' .. p.id, label = locale('opt_panel'), icon = 'panel', distance = d,
          canInteract = function() local s = st() return s ~= nil and (s.mine or s.access) and not s.sale end,
          onSelect = function() SSF.openUnit(p.id) end },
        { name = 'ssf_code_' .. p.id, label = locale('opt_code'), icon = 'code', distance = d,
          canInteract = function() local s = st() return s ~= nil and not s.access and not s.sale end,
          onSelect = function() withCode(locale('code_title', p.id), function(pin) call('ssf:open', p.id, pin) end) end },
        { name = 'ssf_raise_' .. p.id, label = locale(box and 'opt_cdoor_open' or 'opt_raise'), icon = box and 'open' or 'raise',
          distance = d,
          canInteract = function() local s = st() return main and not mainOpen(p.id) and s ~= nil and s.access and not s.sale end,
          onSelect = function() call('ssf:door', p.id, true) end },
        { name = 'ssf_lower_' .. p.id, label = locale(box and 'opt_cdoor_close' or 'opt_lower'), icon = box and 'close' or 'lower',
          distance = d,
          canInteract = function() local s = st() return main and mainOpen(p.id) and not (s and s.sale) end,
          onSelect = function() call('ssf:door', p.id, false) end },
        { name = 'ssf_police_' .. p.id, label = locale('opt_police'), icon = 'police', distance = d,
          canInteract = function() local s = st() return s ~= nil and not s.sale and not s.access and isPolice() end,
          onSelect = function()
              if Bridge.progress(locale('progress_search'), Config.PoliceSearchTime,
                  { dict = 'anim@gangops@facility@servers@bodysearch@', clip = 'player_search', flag = 49 }) then
                  call('ssf:police', p.id)
              end
          end },
        { name = 'ssf_pick_' .. p.id, label = locale('opt_lockpick'), icon = 'lockpick', distance = d,
          canInteract = function()
              local s = st()
              return Config.Lockpick.enabled and s ~= nil and not s.access and not s.sale and not isPolice()
          end,
          onSelect = function()
              if Bridge.progress(locale('progress_lockpick'), Config.Lockpick.time,
                  { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 }) then
                  call('ssf:lockpick', p.id)
              end
          end },
    }
end

local DoorUi = {
    shutter = { radius = 1.3, open = 'opt_raise', close = 'opt_lower', fromOutside = false, closeOutside = false, code = false },
    door = { radius = 0.9, open = 'opt_door_open', close = 'opt_door_close', fromOutside = true, closeOutside = true, code = true },
    cdoor = { radius = 1.0, open = 'opt_cdoor_open', close = 'opt_cdoor_close', fromOutside = false, closeOutside = false,
              code = false, group = true, at = function(d) return d.inside end },
    hatch = { radius = 0.9, open = 'opt_hatch_open', close = 'opt_hatch_close', free = true,
              at = function(d) local _, inw = axes(d.heading) return d.coords - inw * (d.d / 2) end,
              openAt = function(d)
                  local _, inw = axes(d.heading)
                  return d.coords - inw * 0.06 + vector3(0.0, 0.0, d.d / 2)
              end },
}
local function uiOf(d) return DoorUi[d.kind] or DoorUi.shutter end

local function doorOptions(dr, closeOnly)
    local id, ui = dr.id, uiOf(dr)
    local ref = ui.group and dr.unit or id
    local function isOpen() if ui.group then return mainOpen(dr.unit) end return doorOpen(id) end
    local function st() return state[dr.unit] end
    local opts = {
        { name = 'ssf_dopen_' .. id, label = locale(ui.open), icon = 'open', distance = 2.5,
          canInteract = function()
              local s = st()
              if isOpen() or (s and s.sale) then return false end
              if ui.free or insideOf(dr) then return true end
              return ui.fromOutside and s ~= nil and s.access
          end,
          onSelect = function() call('ssf:door', ref, true) end },
        { name = 'ssf_dclose_' .. id, label = locale(ui.close), icon = 'close', distance = 2.5,
          canInteract = function()
              local s = st()
              return isOpen() and not (s and s.sale) and (ui.free or ui.closeOutside or insideOf(dr))
          end,
          onSelect = function() call('ssf:door', ref, false) end },
    }
    if closeOnly then return { opts[2] } end
    if ui.code then
        opts[#opts + 1] = { name = 'ssf_dcode_' .. id, label = locale('opt_code'), icon = 'code', distance = 2.5,
            canInteract = function()
                local s = st()
                return not isOpen() and not insideOf(dr) and s ~= nil and not s.access and not s.sale
            end,
            onSelect = function() withCode(locale('code_title', dr.unit), function(pin) call('ssf:door', id, true, pin) end) end }
    end
    return opts
end

local function gateOptions(key, n)
    return {
        { name = 'ssf_gate_close_' .. n, label = locale('opt_gate_close'), icon = 'close', distance = 3.0,
          canInteract = function() return gateOpen(key) end, onSelect = function() call('ssf:gate', key, false) end },
        { name = 'ssf_gate_open_' .. n, label = locale('opt_gate_open'), icon = 'open', distance = 3.0,
          canInteract = function() return not gateOpen(key) end, onSelect = function() call('ssf:gate', key, true) end },
    }
end

local targetZones = {}

local function zone(name, coords, radius, options)
    targetZones[#targetZones + 1] = Bridge.addZone(name, coords, radius, options)
end

CreateThread(function()
    if not Bridge.waitTarget() then return end
    for _, p in ipairs(FacilityData.units) do zone('ssf_' .. p.id, p.coords, 1.4, storageOptions(p)) end
    for _, p in ipairs(FacilityData.containers) do zone('ssf_' .. p.id, p.coords, 1.6, storageOptions(p)) end
    for _, site in ipairs(FacilityData.sites) do
        local key = site.key
        if site.reception then
            zone('ssf_reception_' .. key, site.reception.coords, 1.8, {
                { name = 'ssf_reception_open_' .. key, label = locale('opt_reception'), icon = 'reception', distance = 3.0,
                  onSelect = function() SSF.openReception(key) end } })
        end
        if site.trade then
            zone('ssf_trade_' .. key, site.trade.coords, 2.5, {
                { name = 'ssf_trade_open_' .. key, label = locale('opt_trade'), icon = 'trade', distance = 3.5,
                  onSelect = function() SSF.openTrade(key) end } })
        end
        local g = site.gate
        if g and not Config.Doors.gateAuto then
            local right = axes(g.heading)
            for i, s in ipairs({ g.closeOffset, g.closeOffset + g.length }) do
                local n = ('%s_%d'):format(key, i)
                zone('ssf_gate_' .. n, g.coords + right * s + vector3(0.0, 0.0, 1.0), 1.5, gateOptions(key, n))
            end
        end
    end
    for _, dr in ipairs(FacilityData.doors or {}) do
        local ui, at = uiOf(dr), nil
        if ui.at then at = ui.at(dr) else at = dr.coords + vector3(0.0, 0.0, math.min(1.2, dr.h / 2)) end
        if at then zone('ssf_door_' .. dr.id, at, ui.radius, doorOptions(dr)) end
        if ui.openAt then zone('ssf_door_' .. dr.id .. '_open', ui.openAt(dr), ui.radius, doorOptions(dr, true)) end
    end
    local s, t = call('ssf:getState')
    state = s or {}
    if t then serverOffset = t - GetCloudTimeAsInt() end
end)

if Config.Blip.enabled then
    CreateThread(function()
        for _, site in ipairs(FacilityData.sites) do
            local c = site.reception and site.reception.coords
            if c then
                local b = AddBlipForCoord(c.x, c.y, c.z)
                SetBlipSprite(b, Config.Blip.sprite)
                SetBlipColour(b, Config.Blip.color)
                SetBlipScale(b, Config.Blip.scale)
                SetBlipAsShortRange(b, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(locale('blip'))
                EndTextCommandSetBlipName(b)
            end
        end
    end)
end

local BARRIER_POST, BARRIER_ARM = `prop_sec_barier_base_01`, `prop_sec_barrier_ld_02a`
local OPEN_ANGLE, ARM_HEIGHT, ARM_SIDE, ARM_LENGTH = 85.0, 0.95, 0.32, 4.87
local UP = vector3(0.0, 0.0, 1.0)
local SHUTTER_ROLLED = 0.07
local movers = {}

local function calibrate(ent, heading, lv, want)
    local target = want(60.0)
    local best, bestErr = nil, math.huge
    for order = 0, 5 do
        for _, c in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            SetEntityRotation(ent, c[1] * 60.0, c[2] * 60.0, heading, order, false)
            local got = GetOffsetFromEntityInWorldCoords(ent, lv.x, lv.y, lv.z) - GetEntityCoords(ent)
            local err = #(got - target)
            if err < bestErr then bestErr, best = err, { order, c[1], c[2] } end
        end
    end
    return function(angle, h) return best[2] * angle, best[3] * angle, h, best[1] end
end

local function vehicleAt(m, vehicles)
    for _, veh in ipairs(vehicles) do
        local rel = GetEntityCoords(veh) - m.hinge
        local along, across = rel.x * m.right.x + rel.y * m.right.y, rel.x * m.inw.x + rel.y * m.inw.y
        if along > -0.5 and along < m.span + 0.5 and math.abs(across) < Config.Barriers.detect
            and math.abs(rel.z) < 4.0 and not IsVehicleSeatFree(veh, -1) then
            return true
        end
    end
    return false
end

local function playerAtGate(m, peds)
    local a = math.min(m.closeOffset, m.closeOffset + m.length) - 1.5
    local b = math.max(m.closeOffset, m.closeOffset + m.length) + 1.5
    for _, ped in ipairs(peds) do
        local rel = GetEntityCoords(ped) - m.coords
        local along, across = rel.x * m.right.x + rel.y * m.right.y, rel.x * m.inw.x + rel.y * m.inw.y
        if along > a and along < b and math.abs(across) < Config.Doors.gateDetect and math.abs(rel.z) < 4.0 then
            return true
        end
    end
    return false
end

local function byDoorState(m) return doorOpen(m.id) and 1.0 or 0.0 end

local Kinds = {}

Kinds.arm = {
    models = function(m) return { m.model, BARRIER_POST } end,
    spawnAt = function(m)
        local base = m.hinge - m.right * math.max(0.0, ARM_LENGTH - m.span)
        m.post = CreateObjectNoOffset(BARRIER_POST, base.x, base.y, base.z, false, false, false)
        SetEntityHeading(m.post, m.heading)
        FreezeEntityPosition(m.post, true)
        return base + m.inw * ARM_SIDE + UP * ARM_HEIGHT
    end,
    spawned = function(m)
        if not Kinds.arm.rot then
            Kinds.arm.rot = calibrate(m.ent, m.heading, vector3(1.0, 0.0, 0.0),
                function(a) return m.right * math.cos(math.rad(a)) + UP * math.sin(math.rad(a)) end)
        end
    end,
    place = function(m)
        local p, r, y, o = Kinds.arm.rot(m.pos * OPEN_ANGLE, m.heading)
        SetEntityRotation(m.ent, p, r, y, o, false)
    end,
    target = function(m, now, scan)
        scan.vehicles = scan.vehicles or GetGamePool('CVehicle')
        if vehicleAt(m, scan.vehicles) then m.lastSeen = now end
        return (now - m.lastSeen < Config.Barriers.closeDelay) and 1.0 or 0.0
    end,
}

Kinds.shutter = {
    time = function() return Config.Doors.shutterTime end,
    spawned = function(m)
        local f, r, u = GetEntityMatrix(m.ent)
        m.mx = { f, r, u }
    end,
    place = function(m)
        local s = 1.0 - m.pos * (1.0 - SHUTTER_ROLLED)
        local c = m.coords + UP * (m.h * (1.0 - s))
        local f, r, u = m.mx[1], m.mx[2], m.mx[3]
        SetEntityMatrix(m.ent, f.x, f.y, f.z, r.x, r.y, r.z, u.x * s, u.y * s, u.z * s, c.x, c.y, c.z)
        SetEntityCollision(m.ent, m.pos < 0.6, true)
    end,
    refresh = function(m) return m.pos > 0.0 and m.pos == m.target end,
    target = byDoorState,
}

Kinds.door = {
    time = function() return Config.Doors.doorTime end,
    place = function(m)
        local hd = m.heading + m.pos * 90.0
        local rr = math.rad(hd)
        local c = m.coords - m.right * (m.w / 2) + vector3(math.cos(rr), math.sin(rr), 0.0) * (m.w / 2)
        SetEntityCoordsNoOffset(m.ent, c.x, c.y, c.z, false, false, false)
        SetEntityHeading(m.ent, hd)
    end,
    target = byDoorState,
}

Kinds.cdoor = {
    time = function() return Config.Doors.containerTime end,
    place = function(m) SetEntityHeading(m.ent, m.heading + m.data.swing * m.pos * m.data.open) end,
    target = byDoorState,
}

Kinds.hatch = {
    time = function() return Config.Doors.hatchTime end,
    spawned = function(m)
        m.rot = calibrate(m.ent, m.heading, vector3(0.0, -1.0, 0.0),
            function(a) return -m.inw * math.cos(math.rad(a)) + UP * math.sin(math.rad(a)) end)
    end,
    place = function(m)
        local p, r, y, o = m.rot(m.pos * m.data.open, m.heading)
        SetEntityRotation(m.ent, p, r, y, o, false)
    end,
    target = byDoorState,
}

Kinds.gate = {
    place = function(m)
        local c = m.coords + m.right * ((1.0 - m.pos) * m.closeOffset)
        SetEntityCoordsNoOffset(m.ent, c.x, c.y, c.z, false, false, false)
    end,
    target = function(m, now, scan)
        if not Config.Doors.gateAuto then return gateOpen(m.site) and 1.0 or 0.0 end
        if not scan.peds then
            scan.peds = {}
            for _, pid in ipairs(GetActivePlayers()) do scan.peds[#scan.peds + 1] = GetPlayerPed(pid) end
        end
        if playerAtGate(m, scan.peds) then m.lastSeen = now end
        return (now - m.lastSeen < Config.Doors.gateCloseDelay) and 1.0 or 0.0
    end,
}

SSF.MoverKinds = Kinds

local function spawn(m)
    if not HasModelLoaded(m.model) then return end
    local K = Kinds[m.kind]
    local c = K.spawnAt and K.spawnAt(m) or m.coords
    m.ent = CreateObjectNoOffset(m.model, c.x, c.y, c.z, false, false, false)
    FreezeEntityPosition(m.ent, true)
    SetEntityCoordsNoOffset(m.ent, c.x, c.y, c.z, false, false, false)
    SetEntityHeading(m.ent, m.heading)
    if K.spawned then K.spawned(m) end
    m.pos = m.target
    K.place(m)
end

local function despawn(m)
    for _, k in ipairs({ 'post', 'ent' }) do
        if m[k] and DoesEntityExist(m[k]) then DeleteEntity(m[k]) end
        m[k] = nil
    end
end

local function updateTargets(now, list)
    local scan = {}
    for _, m in ipairs(list) do m.target = Kinds[m.kind].target(m, now, scan) end
end

local function addMover(m)
    local K = Kinds[m.kind]
    if not K then return end
    m.right, m.inw = axes(m.heading)
    m.time = m.time or (K.time and K.time(m)) or 1.0
    m.target = m.target or 0.0
    m.lastSeen = -1e9
    movers[#movers + 1] = m
end

if Config.Barriers.enabled then
    for _, d in ipairs(FacilityData.barriers or {}) do
        addMover({ kind = 'arm', site = d.site, model = BARRIER_ARM, hinge = d.hinge, heading = d.heading, span = d.span,
                   time = OPEN_ANGLE / Config.Barriers.speed })
    end
end
for _, d in ipairs(FacilityData.doors or {}) do
    addMover({ kind = Kinds[d.kind] and d.kind or 'shutter', site = d.site, id = d.id, model = GetHashKey(d.model),
               coords = d.coords, heading = d.heading, w = d.w, h = d.h, data = d })
end
for _, site in ipairs(FacilityData.sites) do
    local g = site.gate
    if g then
        addMover({ kind = 'gate', site = site.key, model = GetHashKey(g.model), coords = g.coords, heading = g.heading,
                   closeOffset = g.closeOffset, length = g.length, time = Config.Doors.gateTime,
                   target = Config.Doors.gateAuto and 0.0 or 1.0 })
    end
end

local moversBySite = {}
for _, m in ipairs(movers) do
    moversBySite[m.site] = moversBySite[m.site] or {}
    table.insert(moversBySite[m.site], m)
end

local function spawnSite(list)
    local models = {}
    for _, m in ipairs(list) do
        local K = Kinds[m.kind]
        for _, model in ipairs(K.models and K.models(m) or { m.model }) do models[model] = true end
    end
    for model in pairs(models) do
        if not pcall(lib.requestModel, model) then print(('[%s] model %s not loaded'):format(GetCurrentResourceName(), model)) end
    end
    local limit = GetGameTimer() + 2000
    for model in pairs(models) do
        RequestCollisionForModel(model)
        while not HasCollisionForModelLoaded(model) and GetGameTimer() < limit do Wait(0) end
    end
    updateTargets(GetGameTimer(), list)
    for _, m in ipairs(list) do spawn(m) end
    for model in pairs(models) do SetModelAsNoLongerNeeded(model) end
end

if #movers > 0 then
    CreateThread(function()
        local active, live, nextScan = {}, {}, 0
        while true do
            local me = GetEntityCoords(cache.ped)
            local changed = false
            for key, list in pairs(moversBySite) do
                local inside = inZone(key, me, active[key])
                if not active[key] and inside then
                    spawnSite(list)
                    active[key], changed = true, true
                elseif active[key] and not inside then
                    for _, m in ipairs(list) do despawn(m) end
                    active[key], changed = nil, true
                end
            end
            if changed then
                live = {}
                for key in pairs(active) do
                    for _, m in ipairs(moversBySite[key]) do live[#live + 1] = m end
                end
            end
            if #live == 0 then
                Wait(1000)
            else
                local now = GetGameTimer()
                if now >= nextScan then
                    nextScan = now + 150
                    updateTargets(now, live)
                    for _, m in ipairs(live) do
                        local K = Kinds[m.kind]
                        if K.refresh and m.ent and K.refresh(m) and #(m.coords - me) < 60.0 then K.place(m) end
                    end
                end
                local moving, dt = false, GetFrameTime()
                for _, m in ipairs(live) do
                    if m.ent and m.pos ~= m.target then
                        local step = dt / m.time
                        m.pos = m.pos < m.target and math.min(m.target, m.pos + step) or math.max(m.target, m.pos - step)
                        Kinds[m.kind].place(m)
                        moving = true
                    end
                end
                Wait(moving and 0 or 150)
            end
        end
    end)
end

local blocking = {}
for _, site in ipairs(FacilityData.sites) do
    local L = site.lot
    blocking[#blocking + 1] = AddScenarioBlockingArea(L.min.x, L.min.y, L.min.z, L.max.x, L.max.y, L.max.z,
        false, true, true, true)
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, b in ipairs(blocking) do RemoveScenarioBlockingArea(b, false) end
    for _, m in ipairs(movers) do despawn(m) end
    for _, z in ipairs(targetZones) do pcall(Bridge.removeZone, z) end
end)
