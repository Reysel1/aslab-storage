local call, notify = SSF.call, SSF.notify

local objects = {}
local saleProps = {}
local active = {}
local placing = nil

local function siteOf(unit) return FacilityData.unitSite[unit] end
local function live(unit) return active[siteOf(unit) or ''] == true end

local SALE_BARRIER, SALE_SIGN = `prop_barrier_work05`, `prop_forsale_sign_fs`
local FALLBACK = GetHashKey(Config.ItemPropFallback)
local UP = vector3(0.0, 0.0, 1.0)
local DISPLAY_GAP = 0.05

local FurnitureByKey = {}
for _, f in ipairs(Config.Furniture) do FurnitureByKey[f.key] = f end

local function st(unit) return SSF.state()[unit] end
local function canUse(unit) local s = st(unit) return s ~= nil and s.access == true end
local function isMine(unit) local s = st(unit) return s ~= nil and s.mine == true and not s.expired end

local function resolveModel(model)
    local h
    if type(model) == 'string' and model:sub(1, 7) == 'weapon:' then
        h = GetWeapontypeModel(GetHashKey(model:sub(8)))
    else
        h = type(model) == 'number' and model or GetHashKey(model or '')
    end
    if not h or h == 0 or not IsModelInCdimage(h) then return FALLBACK, false end
    return h, type(model) == 'string' and model:sub(1, 7) == 'weapon:'
end

local noCollision = {}

local function loadModel(h, timeout)
    if not HasModelLoaded(h) then
        local ok = pcall(lib.requestModel, h, timeout or 15000)
        if not ok or not HasModelLoaded(h) then return false end
    end
    if not noCollision[h] and not HasCollisionForModelLoaded(h) then
        RequestCollisionForModel(h)
        local limit = GetGameTimer() + 2000
        while not HasCollisionForModelLoaded(h) do
            if GetGameTimer() > limit then noCollision[h] = true break end
            Wait(0)
        end
    end
    return true
end
local RETRY_MS = 3000
local SETTLE_DIST = 80.0
local MAX_FIXES = 6

local function orient(ent, heading, weapon)
    SetEntityRotation(ent, weapon and 90.0 or 0.0, 0.0, heading, 2, false)
end

local function axes(ent)
    local p = GetEntityCoords(ent)
    return GetOffsetFromEntityInWorldCoords(ent, 1.0, 0.0, 0.0) - p, GetOffsetFromEntityInWorldCoords(ent, 0.0, 0.0, 1.0) - p, p
end

local function pickupAnim()
    lib.requestAnimDict('pickup_object')
    TaskPlayAnim(cache.ped, 'pickup_object', 'pickup_low', 8.0, -8.0, 1000, 48, 0, false, false, false)
end

local function inBox(I, p)
    local r = math.rad(I.heading)
    local rel = p - I.c
    return rel.x * math.cos(r) + rel.y * math.sin(r), -rel.x * math.sin(r) + rel.y * math.cos(r), rel.z
end

local function fromBox(I, lx, ly, z)
    local r = math.rad(I.heading)
    return vector3(I.c.x + lx * math.cos(r) - ly * math.sin(r), I.c.y + lx * math.sin(r) + ly * math.cos(r), z)
end

local function camRay(dist, ignore)
    local cam = GetGameplayCamCoord()
    local rot = GetGameplayCamRot(2)
    local rx, rz = math.rad(rot.x), math.rad(rot.z)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local to = cam + dir * dist
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16, ignore, 4)
    local _, hit, pos = GetShapeTestResult(h)
    return hit == 1, hit == 1 and pos or to
end

local function keys()
    return { { key = 'E', text = locale('key_place') }, { key = locale('key_wheel'), text = locale('key_rotate') },
             { key = 'Shift', text = locale('key_fine') }, { key = 'G', text = locale('key_straight') },
             { key = locale('key_backspace'), text = locale('key_cancel') } }
end

local function startPlacement(opts)
    if placing then return end
    local I = SSF.Interiors[opts.unit]
    if not I then notify('error', locale('no_room')) return end
    local hash, weapon = resolveModel(opts.model)
    if not loadModel(hash) then notify('error', locale('model_failed')) return end
    local ped = cache.ped
    if #(GetEntityCoords(ped) - I.c) > math.max(I.hx, I.hy) + 6.0 then notify('error', locale('get_closer')) return end
    local ghost = CreateObjectNoOffset(hash, I.c.x, I.c.y, I.c.z, false, false, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityAlpha(ghost, 170, false)
    if opts.rec then SSF.hideObject(opts.rec, true) end
    local mn, mx = GetModelDimensions(hash)
    local heading = opts.heading or ((I.heading + 180.0) % 360.0)
    placing = true
    SSF.showHints(locale('placing', opts.label), keys())
    CreateThread(function()
        local result
        while true do
            for _, c in ipairs({ 24, 25, 37, 44, 45, 140, 141, 142, 257, 263, 14, 15, 16, 17, 47, 38, 177, 200, 199 }) do
                DisableControlAction(0, c, true)
            end
            local hit, pos = camRay(8.0, ghost)
            local d = math.rad(heading - I.heading)
            local sx, sy = math.max(math.abs(mn.x), math.abs(mx.x)), math.max(math.abs(mn.y), math.abs(mx.y))
            if weapon then sx, sy = math.max(math.abs(mn.x), math.abs(mx.x)), math.max(math.abs(mn.z), math.abs(mx.z)) end
            local ex = math.abs(math.cos(d)) * sx + math.abs(math.sin(d)) * sy
            local ey = math.abs(math.sin(d)) * sx + math.abs(math.cos(d)) * sy
            local lx, ly, lz = inBox(I, pos)
            local inside = math.abs(lx) <= I.hx and math.abs(ly) <= I.hy
            lx = math.max(-I.hx + ex, math.min(I.hx - ex, lx))
            ly = math.max(-I.hy + ey, math.min(I.hy - ey, ly))
            if I.hx < ex then lx = 0.0 end
            if I.hy < ey then ly = 0.0 end
            local floor = I.c.z
            local surface = floor
            if opts.kind == 'item' and hit and inside and lz > 0.02 and lz < I.height - 0.2 then surface = I.c.z + lz end
            local z = weapon and (surface + 0.03) or (surface - mn.z)
            local p = fromBox(I, lx, ly, z)
            SetEntityCoordsNoOffset(ghost, p.x, p.y, p.z, false, false, false)
            orient(ghost, heading, weapon)
            local blocked = FacilityData.overHatch(opts.unit, p, math.max(ex, ey))
            local r, g, b = 126, 224, 138
            if blocked then r, g, b = 224, 110, 96 end
            DrawMarker(25, p.x, p.y, surface + 0.02, 0, 0, 0, 0, 0, 0, math.max(0.4, ex * 2), math.max(0.4, ey * 2), 1.0,
                r, g, b, 120, false, false, 2, false, nil, nil, false)
            local step = IsDisabledControlPressed(0, 21) and 2.0 or 15.0
            if IsDisabledControlJustPressed(0, 241) or IsControlJustPressed(0, 15) then heading = (heading + step) % 360.0 end
            if IsDisabledControlJustPressed(0, 242) or IsControlJustPressed(0, 14) then heading = (heading - step) % 360.0 end
            if IsDisabledControlJustPressed(0, 47) then heading = (math.floor((heading - I.heading) / 90.0 + 0.5) * 90.0 + I.heading) % 360.0 end
            if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 25)
                or IsEntityDead(cache.ped) or #(GetEntityCoords(cache.ped) - I.c) > math.max(I.hx, I.hy) + 10.0 then
                break
            end
            if IsDisabledControlJustPressed(0, 38) then
                if not blocked then
                    result = { pos = p, heading = heading }
                    break
                end
                notify('error', locale('over_hatch'))
            end
            Wait(0)
        end
        DeleteEntity(ghost)
        SetModelAsNoLongerNeeded(hash)
        SSF.hideHints()
        placing = nil
        if opts.rec then SSF.hideObject(opts.rec, false) end
        if result then
            pickupAnim()
            opts.confirm({ x = result.pos.x, y = result.pos.y, z = result.pos.z }, result.heading)
        end
    end)
end

function SSF.placeFurniture(unit, key)
    for _, f in ipairs(Config.Furniture) do
        if f.key == key then
            startPlacement({ unit = unit, model = f.model, label = f.label, kind = 'furniture',
                confirm = function(pos, h) call('ssf:buyFurniture', unit, key, pos, h) end })
            return
        end
    end
end

function SSF.dropItem(unit, item, amount)
    startPlacement({ unit = unit, model = item.model, label = ('%dx %s'):format(amount, item.label), kind = 'item',
        confirm = function(pos, h) call('ssf:dropItem', unit, item.slot, amount, pos, h) end })
end

local function objectOptions(o)
    if o.kind == 'furniture' then
        return {
            { name = 'ssf_fopen_' .. o.id, label = locale('opt_open_furniture', o.label:lower()), icon = 'archive', distance = 2.5,
              canInteract = function() return canUse(o.unit) end,
              onSelect = function() call('ssf:openFurniture', o.id) end },
            { name = 'ssf_fmove_' .. o.id, label = locale('opt_move'), icon = 'move', distance = 2.5,
              canInteract = function() return isMine(o.unit) end,
              onSelect = function() SSF.moveObject(o.id) end },
            { name = 'ssf_fdel_' .. o.id, label = locale('opt_dismantle', math.floor(Config.FurnitureRefund * 100)), icon = 'dismantle',
              distance = 2.5,
              canInteract = function() return isMine(o.unit) end,
              onSelect = function()
                  if Bridge.progress(locale('progress_dismantle'), 1500, { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 }) then
                      call('ssf:removeFurniture', o.id)
                  end
              end },
        }
    end
    return {
        { name = 'ssf_itake_' .. o.id, label = locale('opt_take', o.amount > 1 and ('%dx %s'):format(o.amount, o.label) or o.label),
          icon = 'take', distance = 2.0,
          canInteract = function() return canUse(o.unit) end,
          onSelect = function() pickupAnim() call('ssf:takeItem', o.id) end },
        { name = 'ssf_imove_' .. o.id, label = locale('opt_move'), icon = 'move', distance = 2.0,
          canInteract = function() return canUse(o.unit) end,
          onSelect = function() SSF.moveObject(o.id) end },
    }
end

local matrixYFirst = nil
local function setAxes(ent, X, Y, Z, p)
    if matrixYFirst == nil then
        SetEntityRotation(ent, 0.0, 0.0, 0.0, 2, false)
        local a = GetEntityMatrix(ent)
        matrixYFirst = a.y > 0.9
    end
    local A, B = X, Y
    if matrixYFirst then A, B = Y, X end
    SetEntityMatrix(ent, A.x, A.y, A.z, B.x, B.y, B.z, Z.x, Z.y, Z.z, p.x, p.y, p.z)
end

local function displayDef(o)
    local f = o.kind == 'furniture' and FurnitureByKey[o.ref]
    return f and f.display or nil
end

local function isWeaponModel(model) return type(model) == 'string' and model:sub(1, 7) == 'weapon:' end

local function displayQueue(list, rackOnly)
    local D, q = Config.Display, {}
    for _, it in ipairs(list or {}) do
        local weapon = isWeaponModel(it.model)
        if weapon or not rackOnly then
            local n = weapon and math.min(it.count, 10) or math.min(D.maxPerItem, math.max(1, math.ceil(it.count / D.perProp)))
            for _ = 1, n do q[#q + 1] = it.model end
        end
    end
    return q
end

local function clearDisplay(rec)
    rec.dispToken = nil
    for _, e in ipairs(rec.disp or {}) do if DoesEntityExist(e) then DeleteEntity(e) end end
    rec.disp, rec.pose = nil, nil
end

local function buildDisplay(rec)
    clearDisplay(rec)
    local o, def = rec.data, displayDef(rec.data)
    if not def or not rec.ent then return end
    local token = {}
    rec.dispToken, rec.disp, rec.pose = token, {}, {}
    CreateThread(function()
        local ents, pose = rec.disp, rec.pose
        local origin = vector3(o.x, o.y, o.z)
        local r = math.rad(o.h)
        local R, F = vector3(math.cos(r), math.sin(r), 0.0), vector3(-math.sin(r), math.cos(r), 0.0)
        local function world(lx, ly, lz) return origin + R * lx + F * ly + UP * lz end
        local function put(hash, X, Y, Z, p)
            if rec.dispToken ~= token then return end
            local e = CreateObjectNoOffset(hash, p.x, p.y, p.z, false, false, false)
            if e == 0 then return end
            SetEntityCollision(e, false, false)
            FreezeEntityPosition(e, true)
            setAxes(e, X, Y, Z, p)
            if rec.hidden then SetEntityVisible(e, false, false) end
            ents[#ents + 1] = e
            pose[e] = { X, Y, Z, p, 0 }
            SetModelAsNoLongerNeeded(hash)
        end
        local queue = displayQueue(o.contents, def.rack ~= nil or def.crate ~= nil)
        for i = 1, #queue do
            if rec.dispToken ~= token then return end
            if not loadModel((resolveModel(queue[i]))) then
                for _, e in ipairs(ents) do if DoesEntityExist(e) then DeleteEntity(e) end end
                if rec.dispToken == token then
                    rec.dispToken, rec.retryAt = nil, GetGameTimer() + RETRY_MS
                    rec.disp, rec.pose = nil, nil
                end
                return
            end
        end
        if def.crate then
            local c = def.crate
            local ym = (c.y[1] + c.y[2]) / 2
            local cursor, base, top, layer = c.x[1], c.z, c.z, 1
            for i = 1, math.min(#queue, 12) do
                local hash = resolveModel(queue[i])
                if rec.dispToken ~= token then return end
                if loadModel(hash) then
                    local mn, mx = GetModelDimensions(hash)
                    local w = mx.z - mn.z
                    if cursor + w > c.x[2] and cursor > c.x[1] then
                        if layer >= (c.layers or 2) then return end
                        layer, cursor, base = layer + 1, c.x[1], top + 0.005
                    end
                    put(hash, F, UP, R, world(cursor - mn.z, ym - (mn.x + mx.x) / 2, base - mn.y + 0.005))
                    top = math.max(top, base + (mx.y - mn.y))
                    cursor = cursor + w + 0.02
                end
            end
            return
        end
        if def.rack then
            for i = 1, math.min(#queue, def.rack.n) do
                local hash = resolveModel(queue[i])
                if rec.dispToken ~= token then return end
                if loadModel(hash) then
                    local mn, mx = GetModelDimensions(hash)
                    put(hash, UP, R, F, world(def.rack.x + (i - 1) * def.rack.step, -(mn.z + mx.z) / 2, def.rack.z - mn.x + 0.01))
                end
            end
            return
        end
        local s = def.shelves
        local x0, x1, y0, y1 = def.x[1], def.x[2], def.y[1], def.y[2]
        local ym = (y0 + y1) / 2
        local cursor = {}
        for k = 1, #s do cursor[k] = x0 end
        for i, model in ipairs(queue) do
            local hash, weapon = resolveModel(model)
            if rec.dispToken ~= token then return end
            if loadModel(hash) then
                local mn, mx = GetModelDimensions(hash)
                local w = mx.x - mn.x
                local d, hgt = mx.y - mn.y, mx.z - mn.z
                if weapon then d, hgt = mx.z - mn.z, mx.y - mn.y end
                for k = 1, #s do
                    local room = s[k + 1] and (s[k + 1] - s[k] - 0.04) or 0.6
                    if cursor[k] + w <= x1 and hgt <= room and d <= (y1 - y0) + 0.1 then
                        if weapon then
                            put(hash, R, UP, -F, world(cursor[k] - mn.x, ym + (mn.z + mx.z) / 2, s[k] - mn.y + 0.005))
                        else
                            local j = math.rad(((i * 37) % 11 - 5) * 1.2)
                            local Rj = R * math.cos(j) + F * math.sin(j)
                            local Fj = F * math.cos(j) - R * math.sin(j)
                            put(hash, Rj, Fj, UP, world(cursor[k] - mn.x, ym - (mn.y + mx.y) / 2, s[k] - mn.z + 0.005))
                        end
                        cursor[k] = cursor[k] + w + DISPLAY_GAP
                        break
                    end
                end
            end
        end
    end)
end

local function despawnObject(rec)
    clearDisplay(rec)
    if rec.ent and DoesEntityExist(rec.ent) then
        pcall(Bridge.removeEntity, rec.ent)
        DeleteEntity(rec.ent)
    end
    rec.ent, rec.near, rec.fixes = nil, nil, nil
end

local function placeObject(rec)
    local o = rec.data
    SetEntityCoordsNoOffset(rec.ent, o.x, o.y, o.z, false, false, false)
    orient(rec.ent, o.h, rec.weapon)
end

local function objectMoved(rec)
    local o = rec.data
    local X, Z, p = axes(rec.ent)
    local r = math.rad(o.h)
    if #(p - vector3(o.x, o.y, o.z)) > 0.02 or #(X - vector3(math.cos(r), math.sin(r), 0.0)) > 0.02 then return true end
    if rec.weapon then return math.abs(Z.z) > 0.05 end
    return Z.z < 0.999
end

local function propMoved(e, t)
    local X, Z, p = axes(e)
    return #(p - t[4]) > 0.02 or #(X - t[1]) > 0.02 or #(Z - t[3]) > 0.02
end

local function settle(rec, force)
    if not rec.ent or not DoesEntityExist(rec.ent) then return end
    if (rec.fixes or 0) < MAX_FIXES and (force or objectMoved(rec)) then
        placeObject(rec)
        if not force then rec.fixes = (rec.fixes or 0) + 1 end
    end
    for _, e in ipairs(rec.disp or {}) do
        local t = rec.pose and rec.pose[e]
        if t and t[5] < MAX_FIXES and DoesEntityExist(e) and (force or propMoved(e, t)) then
            setAxes(e, t[1], t[2], t[3], t[4])
            if not force then t[5] = t[5] + 1 end
        end
    end
end

local function spawnObject(rec)
    local o = rec.data
    local hash, weapon = resolveModel(o.model)
    if rec.loading then return end
    rec.loading = true
    local loaded = loadModel(hash)
    rec.loading = false
    if not loaded then rec.retryAt = GetGameTimer() + RETRY_MS return end
    if rec.ent or objects[o.id] ~= rec or not live(o.unit) then return end
    local ent = CreateObjectNoOffset(hash, o.x, o.y, o.z, false, false, false)
    if ent == 0 then rec.retryAt = GetGameTimer() + RETRY_MS return end
    rec.ent, rec.weapon, rec.near, rec.fixes = ent, weapon, nil, nil
    placeObject(rec)
    FreezeEntityPosition(ent, true)
    SetEntityCollision(ent, o.kind == 'furniture', true)
    if rec.hidden then SetEntityVisible(ent, false, false) end
    SetModelAsNoLongerNeeded(hash)
    pcall(Bridge.addEntity, ent, objectOptions(o))
end

function SSF.hideObject(rec, hidden)
    rec.hidden = hidden or nil
    if rec.ent and DoesEntityExist(rec.ent) then SetEntityVisible(rec.ent, not hidden, false) end
    for _, e in ipairs(rec.disp or {}) do if DoesEntityExist(e) then SetEntityVisible(e, not hidden, false) end end
end

function SSF.moveObject(id)
    local rec = objects[id]
    if not rec then return end
    local o = rec.data
    startPlacement({ unit = o.unit, model = o.model, label = o.label, kind = o.kind, heading = o.h, rec = rec,
        confirm = function(pos, h) call('ssf:moveObject', o.id, pos, h) end })
end

local function setObject(o)
    local rec = objects[o.id]
    if rec then despawnObject(rec) end
    rec = { data = o }
    objects[o.id] = rec
    if live(o.unit) then spawnObject(rec) end
end

RegisterNetEvent('ssf:placedAdd', setObject)
RegisterNetEvent('ssf:contents', function(id, list)
    local rec = objects[id]
    if not rec then return end
    rec.data.contents = list
    if rec.disp then buildDisplay(rec) end
end)
RegisterNetEvent('ssf:placedUpdate', setObject)
RegisterNetEvent('ssf:placedRemove', function(id)
    local rec = objects[id]
    if rec then despawnObject(rec) objects[id] = nil end
end)
RegisterNetEvent('ssf:placedRemoveUnit', function(unit)
    for id, rec in pairs(objects) do
        if rec.data.unit == unit then despawnObject(rec) objects[id] = nil end
    end
end)

local function listOf(pick)
    local out = {}
    for _, rec in pairs(objects) do if pick(rec) then out[#out + 1] = rec end end
    return out
end

local function loadAll()
    for _, rec in pairs(objects) do despawnObject(rec) end
    objects = {}
    for _, o in ipairs(call('ssf:placedAll') or {}) do objects[o.id] = { data = o } end
    for _, rec in ipairs(listOf(function(r) return live(r.data.unit) end)) do CreateThread(function() spawnObject(rec) end) end
end
RegisterNetEvent('ssf:placedReload', loadAll)

local function clearSale(unit)
    for _, e in ipairs(saleProps[unit] or {}) do if DoesEntityExist(e) then DeleteEntity(e) end end
    saleProps[unit] = nil
end

local function spawnSale(unit)
    local dr = SSF.DoorById[unit]
    if not dr or not loadModel(SALE_BARRIER) or not loadModel(SALE_SIGN) then return end
    local right, inw = SSF.axes(dr.heading)
    local list = {}
    local n = math.max(1, math.ceil(dr.w / 2.0))
    for i = 1, n do
        local off = (i - (n + 1) / 2) * (dr.w / n)
        local p = dr.coords - inw * 0.7 + right * off
        local e = CreateObjectNoOffset(SALE_BARRIER, p.x, p.y, p.z, false, false, false)
        SetEntityHeading(e, dr.heading)
        PlaceObjectOnGroundProperly(e)
        FreezeEntityPosition(e, true)
        list[#list + 1] = e
    end
    local s = dr.coords - inw * 1.0 + right * (dr.w / 2 + 0.5)
    local sign = CreateObjectNoOffset(SALE_SIGN, s.x, s.y, s.z, false, false, false)
    SetEntityHeading(sign, (dr.heading + 180.0) % 360.0)
    PlaceObjectOnGroundProperly(sign)
    FreezeEntityPosition(sign, true)
    list[#list + 1] = sign
    saleProps[unit] = list
end

local function text3d(p, text)
    local on, x, y = World3dToScreen2d(p.x, p.y, p.z)
    if not on then return end
    SetTextScale(0.38, 0.38)
    SetTextFont(4)
    SetTextCentre(true)
    SetTextOutline()
    SetTextColour(240, 240, 235, 235)
    BeginTextCommandDisplayText('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayText(x, y)
end

CreateThread(function()
    while not FacilityData do Wait(500) end
    loadAll()
    while true do
        local me = GetEntityCoords(cache.ped)
        for _, site in ipairs(FacilityData.sites) do
            local key = site.key
            local inside = SSF.inZone(key, me, active[key])
            if not active[key] and inside then
                active[key] = true
                for _, rec in ipairs(listOf(function(r) return not r.ent and siteOf(r.data.unit) == key end)) do
                    CreateThread(function() spawnObject(rec) end)
                end
            elseif active[key] and not inside then
                active[key] = nil
                for _, rec in pairs(objects) do
                    if siteOf(rec.data.unit) == key then despawnObject(rec) end
                end
                for unit in pairs(saleProps) do
                    if siteOf(unit) == key then clearSale(unit) end
                end
            end
        end
        if next(active) then
            local now = GetGameTimer()
            for _, rec in pairs(objects) do
                if not rec.ent and not rec.loading and (rec.retryAt or 0) <= now and live(rec.data.unit) then
                    CreateThread(function() spawnObject(rec) end)
                end
            end
            local D = Config.Display.distance
            for _, rec in pairs(objects) do
                if rec.ent and displayDef(rec.data) then
                    local d = #(me - vector3(rec.data.x, rec.data.y, rec.data.z))
                    if not rec.disp and d < D and (rec.retryAt or 0) <= now then buildDisplay(rec)
                    elseif rec.disp and d > D + 10.0 then clearDisplay(rec) end
                end
            end
            local state = SSF.state()
            for unit in pairs(saleProps) do
                if not (state[unit] and state[unit].sale) then clearSale(unit) end
            end
            for unit, s in pairs(state) do
                if s.sale and not saleProps[unit] and live(unit) then spawnSale(unit) end
            end
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1500
        if next(active) then
            local me = GetEntityCoords(cache.ped)
            for _, rec in pairs(objects) do
                if rec.ent and not rec.hidden then
                    local o = rec.data
                    local d = #(me - vector3(o.x, o.y, o.z))
                    if d < SETTLE_DIST then
                        sleep = 500
                        settle(rec, not rec.near)
                        rec.near = true
                    elseif d > SETTLE_DIST + 20.0 and rec.near then
                        rec.near, rec.fixes = nil, nil
                        for _, t in pairs(rec.pose or {}) do t[5] = 0 end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if next(active) then
            local me = GetEntityCoords(cache.ped)
            for unit, s in pairs(SSF.state()) do
                local dr = s.sale and SSF.DoorById[unit]
                if dr and #(me - dr.coords) < 14.0 then
                    sleep = 0
                    local left = math.max(0, s.sale.endAt - SSF.serverNow())
                    text3d(dr.coords + vector3(0.0, 0.0, dr.h + 0.35),
                        locale('sale_3d', unit, FormatMoney(SSF.salePrice(s.sale)), left // 3600, (left % 3600) // 60))
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, rec in pairs(objects) do
        clearDisplay(rec)
        if rec.ent and DoesEntityExist(rec.ent) then DeleteEntity(rec.ent) end
    end
    for unit in pairs(saleProps) do clearSale(unit) end
end)
