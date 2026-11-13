local RES = GetCurrentResourceName()

local Points = {}
for _, p in ipairs(FacilityData.units) do Points[p.id] = p end
for _, p in ipairs(FacilityData.containers) do Points[p.id] = p end

local Sites = FacilityData.siteByKey
local function siteOf(id) return Sites[FacilityData.unitSite[id] or ''] end

local Doors, UnitDoors, Interiors = {}, {}, {}
for _, d in ipairs(FacilityData.doors or {}) do
    Doors[d.id] = d
    UnitDoors[d.unit] = UnitDoors[d.unit] or {}
    table.insert(UnitDoors[d.unit], d.id)
    if d.interior and (d.id == d.unit or not Interiors[d.unit]) then Interiors[d.unit] = d.interior end
end

local DoorRules = {
    shutter = { reach = 4.5, withStash = true },
    door = { reach = 3.0, withStash = false },
    cdoor = { reach = 4.5, withStash = true },
    hatch = { reach = 4.0, withStash = false, free = true },
}
local function ruleOf(d) return DoorRules[d.kind] or DoorRules.shutter end

local FurnitureByKey = {}
for _, f in ipairs(Config.Furniture) do FurnitureByKey[f.key] = f end

local rentals = {}
local meta = {}
local placed = {}
local grants = {}
local contents = {}
local watching = {}
local registered = {}
local DAY = 86400

local function now() return os.time() end

local function log(key, ...)
    local text = locale(key, ...)
    print(('[%s] %s'):format(RES, text))
    lib.logger(0, key, text)
end

local function notify(src, kind, text) Bridge.notify(src, kind, text) end

local function pedCoords(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function near(src, coords, dist)
    local c = pedCoords(src)
    return c ~= nil and #(c - coords) <= (dist or 6.0)
end

local function nearSite(src, field, dist)
    for _, s in ipairs(FacilityData.sites) do
        if s[field] and near(src, s[field].coords, dist) then return s end
    end
end

local function sizeOf(point) return Config.Sizes[point.size] or Config.Sizes.small end
local function sizeKey(point) return Config.Sizes[point.size] and point.size or 'small' end

local function stashId(id, r) return ('ssf_%s_%d'):format(id:gsub('%-', ''), r.rental) end
local function furnitureStash(o) return ('ssf_%s_%d_f%d'):format(o.unit:gsub('%-', ''), o.rental, o.id) end

local function validPin(pin)
    pin = tostring(pin or '')
    return pin:match('^%d%d%d%d$') and pin or nil
end

local function vec(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

local function level(id)
    local r, m = rentals[id], meta[id]
    return (r and m and m.rental == r.rental and m.level) or 0
end

local function onSale(id)
    local r, m = rentals[id], meta[id]
    return r ~= nil and m ~= nil and m.rental == r.rental and (m.saleEnd or 0) > 0
end

local function salePrice(id)
    local m, size = meta[id], sizeOf(Points[id])
    local t = math.min(1.0, math.max(0.0, (now() - m.saleStart) / math.max(1, m.saleEnd - m.saleStart)))
    local mult = Config.Sale.startMultiplier + (Config.Sale.floorMultiplier - Config.Sale.startMultiplier) * t
    return math.floor(size.price * mult / 10 + 0.5) * 10
end

local function capacity(id)
    local size = sizeOf(Points[id])
    local slots, weight = size.slots, size.weight
    for i = 1, level(id) do
        local u = Config.Upgrades[i]
        slots, weight = slots + u.slots, weight + u.weight
    end
    return slots, weight
end

local function isOwner(src, id)
    local r = rentals[id]
    return r ~= nil and not onSale(id) and r.citizenid == Bridge.id(src) and r.expires >= now()
end

local function hasAccess(src, id)
    local r = rentals[id]
    if not r or onSale(id) or r.expires < now() then return false end
    if r.citizenid == Bridge.id(src) then return true end
    local g = grants[id] and grants[id][src]
    return g ~= nil and g > now()
end

local function rentedBy(src)
    local cid, n = Bridge.id(src), 0
    for id, r in pairs(rentals) do if r.citizenid == cid and not onSale(id) then n = n + 1 end end
    return n
end

local function publicState(src)
    local cid = Bridge.id(src)
    local out = {}
    for id, r in pairs(rentals) do
        local s = { mine = r.citizenid == cid and not onSale(id), access = hasAccess(src, id),
                    untilText = os.date('%d/%m %H:%M', r.expires), expired = r.expires < now() }
        if onSale(id) then
            local m, size = meta[id], sizeOf(Points[id])
            s.sale = { startAt = m.saleStart, endAt = m.saleEnd, from = size.price * Config.Sale.startMultiplier,
                       to = size.price * Config.Sale.floorMultiplier }
        end
        out[id] = s
    end
    return out
end

local function sendState(src) TriggerClientEvent('ssf:state', src, publicState(src), now()) end

local function broadcast()
    for _, s in ipairs(GetPlayers()) do sendState(tonumber(s)) end
end

local function grant(src, id)
    grants[id] = grants[id] or {}
    grants[id][src] = now() + Config.AccessMinutes * 60
    sendState(src)
end

local function hasJob(src, jobs)
    local name, grade = Bridge.job(src)
    local min = jobs[name or '']
    return min ~= nil and grade >= min
end

local function setDoor(id, open) GlobalState['ssf_door_' .. id] = open == true end

local function setUnitDoors(unit, open, stashOnly)
    for _, did in ipairs(UnitDoors[unit] or {}) do
        if not stashOnly or ruleOf(Doors[did]).withStash then setDoor(did, open) end
    end
end

for _, s in ipairs(FacilityData.sites) do
    if s.gate then GlobalState['ssf_gate_' .. s.key] = Config.Doors.gateOpenAtStart == true end
end

local function inward(d)
    local r = math.rad(d.heading)
    if d.kind == 'cdoor' then return vector3(-math.cos(r), -math.sin(r), 0.0) end
    return vector3(-math.sin(r), math.cos(r), 0.0)
end

lib.callback.register('ssf:door', function(src, doorId, open, pin)
    local ids = Doors[doorId] and { doorId } or FacilityData.mainDoors[doorId]
    local d = ids and Doors[ids[1]]
    local c = pedCoords(src)
    if not d or not c or not Bridge.exists(src) then return false end
    local rule = ruleOf(d)
    if #(c - (d.coords + vector3(0.0, 0.0, 1.0))) > rule.reach then return false end
    if onSale(d.unit) then notify(src, 'error', locale('on_sale')) return false end
    local function set(v)
        for _, id in ipairs(ids) do setDoor(id, v) end
        return true
    end
    if not open or rule.free then return set(open) end
    local rel, inw = c - d.coords, inward(d)
    if rel.x * inw.x + rel.y * inw.y > 0.4 then return set(true) end
    local r = rentals[d.unit]
    if not r then notify(src, 'error', locale('unit_free')) return false end
    if not hasAccess(src, d.unit) then
        if validPin(pin) == nil or validPin(pin) ~= r.pin then notify(src, 'error', locale('wrong_code')) return false end
        if r.expires < now() then notify(src, 'error', locale('locked_unpaid')) return false end
        grant(src, d.unit)
    end
    return set(true)
end)

lib.callback.register('ssf:gate', function(src, key, open)
    local s = Sites[key]
    local g = s and s.gate
    if not g or not Bridge.exists(src) then return false end
    local r = math.rad(g.heading)
    local mid = g.coords + vector3(math.cos(r), math.sin(r), 0.0) * (g.closeOffset + g.length / 2)
    if not near(src, mid, g.length / 2 + 4.0) then return false end
    if Config.Doors.gateJobs and not hasJob(src, Config.Doors.gateJobs) then
        notify(src, 'error', locale('no_gate_key')) return false
    end
    GlobalState['ssf_gate_' .. key] = open == true
    return true
end)

local function objectLabel(o)
    local f = o.kind == 'furniture' and FurnitureByKey[o.ref]
    return f and FurnitureLabel(f) or o.label
end

local function publicObj(o)
    return { id = o.id, unit = o.unit, kind = o.kind, ref = o.ref, label = objectLabel(o), model = o.model,
             x = o.x, y = o.y, z = o.z, h = o.h, amount = o.amount, contents = contents[o.id] }
end

local function countPlaced(unit, kind)
    local n = 0
    for _, o in pairs(placed) do if o.unit == unit and o.kind == kind then n = n + 1 end end
    return n
end

local function insideUnit(unit, pos)
    local I = Interiors[unit]
    if not I or type(pos) ~= 'table' and type(pos) ~= 'vector3' then return false end
    local rel = vector3(pos.x + 0.0, pos.y + 0.0, pos.z + 0.0) - I.c
    local r = math.rad(I.heading)
    local lx = rel.x * math.cos(r) + rel.y * math.sin(r)
    local ly = -rel.x * math.sin(r) + rel.y * math.cos(r)
    return math.abs(lx) <= I.hx and math.abs(ly) <= I.hy and rel.z >= -0.4 and rel.z <= I.height
        and not FacilityData.overHatch(unit, pos, 0.15)
end

local function removeUnitObjects(unit)
    for pid, o in pairs(placed) do if o.unit == unit then placed[pid], contents[pid] = nil, nil end end
    MySQL.query('DELETE FROM ssf_storage_placed WHERE unit = ?', { unit })
    TriggerClientEvent('ssf:placedRemoveUnit', -1, unit)
end

local function addObject(o)
    o.id = MySQL.insert.await([[INSERT INTO ssf_storage_placed (unit, rental, kind, ref, label, model, x, y, z, h, amount, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)]],
        { o.unit, o.rental, o.kind, o.ref, o.label, o.model, o.x, o.y, o.z, o.h, o.amount, json.encode(o.metadata or {}) })
    if not o.id then return nil end
    placed[o.id] = o
    TriggerClientEvent('ssf:placedAdd', -1, publicObj(o))
    return o
end

local function deleteObject(o)
    placed[o.id] = nil
    contents[o.id] = nil
    MySQL.query('DELETE FROM ssf_storage_placed WHERE id = ?', { o.id })
    TriggerClientEvent('ssf:placedRemove', -1, o.id)
end

local function itemModel(name, def)
    local n = name:lower()
    if Config.ItemProps[n] then return Config.ItemProps[n] end
    if (def and def.weapon) or n:find('^weapon_') then return 'weapon:' .. n end
    if def and type(def.model) == 'string' and def.model ~= '' then return def.model end
    for _, rule in ipairs(Config.ItemPropPatterns) do
        if n:find(rule[1]) then return rule[2] end
    end
    return Config.ItemPropFallback
end

local function posArg(pos, heading)
    if type(pos) ~= 'table' and type(pos) ~= 'vector3' then return nil end
    local x, y, z, h = tonumber(pos.x), tonumber(pos.y), tonumber(pos.z), tonumber(heading) or 0.0
    if not (x and y and z) then return nil end
    return vector3(x, y, z), h % 360.0
end

local function furnitureStashFor(o)
    local id, f = furnitureStash(o), FurnitureByKey[o.ref]
    if f and not registered[id] then
        registered[id] = true
        Bridge.registerStash(id, ('%s · %s'):format(FurnitureLabel(f), o.unit), f.slots, f.weight)
    end
    return id, f
end

local function hasDisplay(o)
    local f = o.kind == 'furniture' and FurnitureByKey[o.ref]
    return f and f.display ~= nil
end

local function refreshContents(o)
    if not placed[o.id] or not hasDisplay(o) then return end
    local ok, items = pcall(Bridge.stashItems, (furnitureStashFor(o)))
    if not ok or type(items) ~= 'table' then return end
    local list = {}
    for _, it in ipairs(items) do
        list[#list + 1] = { name = it.name, count = math.floor(it.count), model = itemModel(it.name, Bridge.itemDef(it.name)) }
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    local parts = {}
    for i, it in ipairs(list) do parts[i] = it.name .. 'x' .. it.count end
    local sig = table.concat(parts, ',')
    if sig == (o.contentsSig or '') and contents[o.id] then return end
    o.contentsSig = sig
    contents[o.id] = list
    TriggerClientEvent('ssf:contents', -1, o.id, list)
end

CreateThread(function()
    local tick = 0
    while true do
        Wait(1000)
        tick = tick + 1
        if tick % 60 == 0 then
            for _, o in pairs(placed) do refreshContents(o) end
        end
        for src, w in pairs(watching) do
            local o = placed[w.id]
            if o then refreshContents(o) end
            if not o or not GetPlayerName(src) or w.untilT < now() or not near(src, vec(o), 6.0) then watching[src] = nil end
        end
    end
end)

lib.callback.register('ssf:placedAll', function()
    local out = {}
    for _, o in pairs(placed) do out[#out + 1] = publicObj(o) end
    return out
end)

lib.callback.register('ssf:buyFurniture', function(src, unit, key, pos, heading)
    local f, r = FurnitureByKey[key], rentals[unit]
    local v, h = posArg(pos, heading)
    if not f or not r or not v or not isOwner(src, unit) then return false end
    if not insideUnit(unit, v) or not near(src, v, 8.0) then notify(src, 'error', locale('must_be_inside')) return false end
    local limit = Config.FurnitureLimit[Points[unit].size] or 3
    if countPlaced(unit, 'furniture') >= limit then notify(src, 'error', locale('furniture_full', limit)) return false end
    if not Bridge.pay(src, f.price, 'storage-furniture') then notify(src, 'error', locale('no_money', FormatMoney(f.price))) return false end
    addObject({ unit = unit, rental = r.rental, kind = 'furniture', ref = key, label = FurnitureLabel(f), model = f.model,
                x = v.x, y = v.y, z = v.z, h = h, amount = 1 })
    notify(src, 'success', locale('furniture_placed', FurnitureLabel(f), FormatMoney(f.price)))
    return true
end)

lib.callback.register('ssf:moveObject', function(src, pid, pos, heading)
    local o = placed[tonumber(pid)]
    local v, h = posArg(pos, heading)
    if not o or not v then return false end
    local can = isOwner(src, o.unit) or (o.kind == 'item' and hasAccess(src, o.unit))
    if not can or not insideUnit(o.unit, v) or not near(src, v, 8.0) then return false end
    o.x, o.y, o.z, o.h = v.x, v.y, v.z, h
    MySQL.update('UPDATE ssf_storage_placed SET x = ?, y = ?, z = ?, h = ? WHERE id = ?', { o.x, o.y, o.z, o.h, o.id })
    TriggerClientEvent('ssf:placedUpdate', -1, publicObj(o))
    return true
end)

lib.callback.register('ssf:removeFurniture', function(src, pid)
    local o = placed[tonumber(pid)]
    if not o or o.kind ~= 'furniture' or not isOwner(src, o.unit) then return false end
    if not near(src, vec(o), 6.0) then return false end
    local items = Bridge.stashItems((furnitureStashFor(o)))
    if items == nil then return false end
    if #items > 0 then notify(src, 'error', locale('empty_first')) return false end
    local f = FurnitureByKey[o.ref]
    local back = f and math.floor(f.price * Config.FurnitureRefund) or 0
    deleteObject(o)
    Bridge.addMoney(src, 'bank', back, 'storage-furniture')
    notify(src, 'success', locale('furniture_removed', objectLabel(o), FormatMoney(back)))
    return true
end)

lib.callback.register('ssf:openFurniture', function(src, pid)
    local o = placed[tonumber(pid)]
    if not o or o.kind ~= 'furniture' or not hasAccess(src, o.unit) or not near(src, vec(o), 4.0) then return false end
    local id, f = furnitureStashFor(o)
    if not f then return false end
    local ok = Bridge.openStash(src, id, f.slots, f.weight, ('%s · %s'):format(FurnitureLabel(f), o.unit))
    if ok and f.display then watching[src] = { id = o.id, untilT = now() + 900 } end
    return ok
end)

local function slotItem(src, slot)
    for _, e in ipairs(Bridge.playerItems(src)) do
        if e.slot == slot then return e end
    end
end

lib.callback.register('ssf:dropItem', function(src, unit, slot, amount, pos, heading)
    local r = rentals[unit]
    local v, h = posArg(pos, heading)
    slot = tonumber(slot)
    if not r or not v or not slot or not hasAccess(src, unit) then return false end
    if not insideUnit(unit, v) or not near(src, v, 8.0) then notify(src, 'error', locale('must_stay_inside')) return false end
    if countPlaced(unit, 'item') >= Config.LooseItemsLimit then
        notify(src, 'error', locale('items_full', Config.LooseItemsLimit)) return false
    end
    local e = slotItem(src, slot)
    if not e then return false end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > e.count then notify(src, 'error', locale('not_enough')) return false end
    if not Bridge.removeFromSlot(src, slot, e.name, amount) then return false end
    addObject({ unit = unit, rental = r.rental, kind = 'item', ref = e.name, label = e.label,
                model = itemModel(e.name, { weapon = e.weapon, model = e.model }),
                x = v.x, y = v.y, z = v.z, h = h, amount = amount, metadata = e.metadata })
    notify(src, 'success', locale('item_left', amount, e.label))
    return true
end)

lib.callback.register('ssf:takeItem', function(src, pid)
    local o = placed[tonumber(pid)]
    if not o or o.kind ~= 'item' or not hasAccess(src, o.unit) or not near(src, vec(o), 4.0) then return false end
    if not Bridge.canCarry(src, o.ref, o.amount, o.metadata) then notify(src, 'error', locale('cannot_carry')) return false end
    deleteObject(o)
    if not Bridge.giveItem(src, o.ref, o.amount, o.metadata) then addObject(o) return false end
    return true
end)

lib.callback.register('ssf:invItems', function(src)
    local out = {}
    for _, e in ipairs(Bridge.playerItems(src)) do
        local n = e.name:lower()
        if n ~= 'cash' and n ~= 'money' and n ~= 'black_money' then
            out[#out + 1] = { slot = e.slot, name = e.name, label = e.label, img = e.image, count = e.count,
                              model = itemModel(e.name, { weapon = e.weapon, model = e.model }), weapon = e.weapon,
                              serial = e.metadata.serial }
        end
    end
    return out
end)

local function saveMeta(id)
    local m = meta[id]
    if not m then MySQL.query('DELETE FROM ssf_storage_meta WHERE unit = ?', { id }) return end
    MySQL.query('REPLACE INTO ssf_storage_meta (unit, rental, level, sale_start, sale_end) VALUES (?, ?, ?, ?, ?)',
        { id, m.rental, m.level or 0, m.saleStart or 0, m.saleEnd or 0 })
end

local function wipeUnit(id)
    rentals[id], meta[id], grants[id] = nil, nil, nil
    MySQL.query('DELETE FROM ssf_storage_rentals WHERE unit = ?', { id })
    saveMeta(id)
    removeUnitObjects(id)
    setUnitDoors(id, false)
end

local function startSale(id)
    local r = rentals[id]
    meta[id] = { rental = r.rental, level = level(id), saleStart = now(), saleEnd = now() + Config.Sale.hours * 3600 }
    grants[id] = nil
    saveMeta(id)
    setUnitDoors(id, false)
    setUnitDoors(id, true, true)
    local owner = Bridge.online(r.citizenid)
    if owner then notify(owner, 'error', locale('your_unit_on_sale', id)) end
    log('log_on_sale', id, r.name or r.citizenid)
end

CreateThread(function()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS ssf_storage_rentals (
        unit VARCHAR(16) NOT NULL PRIMARY KEY,
        citizenid VARCHAR(64) NOT NULL,
        owner_name VARCHAR(100) NULL,
        pin VARCHAR(8) NOT NULL,
        expires INT NOT NULL,
        rental INT NOT NULL
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS ssf_storage_meta (
        unit VARCHAR(16) NOT NULL PRIMARY KEY,
        rental INT NOT NULL,
        level INT NOT NULL DEFAULT 0,
        sale_start INT NOT NULL DEFAULT 0,
        sale_end INT NOT NULL DEFAULT 0
    )]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS ssf_storage_placed (
        id INT NOT NULL AUTO_INCREMENT PRIMARY KEY,
        unit VARCHAR(16) NOT NULL,
        rental INT NOT NULL,
        kind VARCHAR(12) NOT NULL,
        ref VARCHAR(64) NOT NULL,
        label VARCHAR(100) NULL,
        model VARCHAR(80) NOT NULL,
        x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, h DOUBLE NOT NULL,
        amount INT NOT NULL DEFAULT 1,
        metadata LONGTEXT NULL,
        INDEX (unit)
    )]])
    for _, row in ipairs(MySQL.query.await('SELECT * FROM ssf_storage_rentals') or {}) do
        if Points[row.unit] then
            rentals[row.unit] = { citizenid = row.citizenid, name = row.owner_name, pin = row.pin,
                                  expires = row.expires, rental = row.rental }
        end
    end
    for _, row in ipairs(MySQL.query.await('SELECT * FROM ssf_storage_meta') or {}) do
        meta[row.unit] = { rental = row.rental, level = row.level, saleStart = row.sale_start, saleEnd = row.sale_end }
    end
    local stale = {}
    for _, row in ipairs(MySQL.query.await('SELECT * FROM ssf_storage_placed') or {}) do
        local r = rentals[row.unit]
        if r and r.rental == row.rental then
            placed[row.id] = { id = row.id, unit = row.unit, rental = row.rental, kind = row.kind, ref = row.ref,
                               label = row.label, model = row.model, x = row.x, y = row.y, z = row.z, h = row.h,
                               amount = row.amount, metadata = json.decode(row.metadata or '{}') or {} }
        else
            stale[#stale + 1] = row.id
        end
    end
    if #stale > 0 then MySQL.query('DELETE FROM ssf_storage_placed WHERE id IN (?)', { stale }) end
    for _, o in pairs(placed) do refreshContents(o) end
    for id in pairs(Doors) do setDoor(id, false) end
    for id in pairs(rentals) do if onSale(id) then setUnitDoors(id, true, true) end end
    local n = 0
    for _ in pairs(rentals) do n = n + 1 end
    log('log_loaded', n, Bridge.describe())
    broadcast()
    TriggerClientEvent('ssf:placedReload', -1)
    while true do
        local changed = false
        for id, r in pairs(rentals) do
            if onSale(id) then
                if now() >= meta[id].saleEnd then
                    log('log_unsold', id)
                    wipeUnit(id)
                    changed = true
                end
            elseif r.expires + Config.GraceDays * DAY < now() then
                startSale(id)
                changed = true
            end
        end
        for id, g in pairs(grants) do
            for s, t in pairs(g) do if t < now() then g[s] = nil end end
            if next(g) == nil then grants[id] = nil end
        end
        if changed then broadcast() end
        Wait(60000)
    end
end)

Bridge.onPlayerLoaded(sendState)

AddEventHandler('playerDropped', function()
    local src = source
    for _, g in pairs(grants) do g[src] = nil end
    watching[src] = nil
end)

lib.callback.register('ssf:getState', function(src) return publicState(src), now() end)

lib.addCommand('ssf_reset', { help = locale('cmd_reset'), restricted = 'group.admin' }, function(src)
    local n, stashes = 0, {}
    for id, r in pairs(rentals) do
        stashes[#stashes + 1] = stashId(id, r)
        n = n + 1
    end
    for _, o in pairs(placed) do if o.kind == 'furniture' then stashes[#stashes + 1] = furnitureStash(o) end end
    for id in pairs(rentals) do wipeUnit(id) end
    for _, id in ipairs(stashes) do Bridge.clearStash(id) end
    rentals, meta, placed, grants, contents, watching = {}, {}, {}, {}, {}, {}
    MySQL.query.await('DELETE FROM ssf_storage_rentals')
    MySQL.query.await('DELETE FROM ssf_storage_meta')
    MySQL.query.await('DELETE FROM ssf_storage_placed')
    for id in pairs(Doors) do setDoor(id, false) end
    broadcast()
    TriggerClientEvent('ssf:placedReload', -1)
    log('log_reset', n)
    if src > 0 then notify(src, 'success', locale('log_reset', n)) end
end)

lib.callback.register('ssf:rent', function(src, id, pin)
    local point = Points[id]
    if not point or not Bridge.exists(src) or not near(src, point.coords, 8.0) then return false end
    pin = validPin(pin)
    if not pin then notify(src, 'error', locale('code_digits')) return false end
    if rentals[id] then notify(src, 'error', onSale(id) and locale('buy_from_door') or locale('already_rented')) return false end
    local mine = rentedBy(src)
    if mine >= Config.MaxRentalsPerPlayer then notify(src, 'error', locale('too_many', mine)) return false end
    local size = sizeOf(point)
    if not Bridge.pay(src, size.price, 'storage-rent') then notify(src, 'error', locale('no_money', FormatMoney(size.price))) return false end
    local rental = math.random(100000, 999999)
    local r = { citizenid = Bridge.id(src), name = Bridge.name(src), pin = pin, expires = now() + Config.RentDays * DAY, rental = rental }
    rentals[id] = r
    meta[id] = { rental = rental, level = 0 }
    saveMeta(id)
    MySQL.query('REPLACE INTO ssf_storage_rentals (unit, citizenid, owner_name, pin, expires, rental) VALUES (?, ?, ?, ?, ?, ?)',
        { id, r.citizenid, r.name, pin, r.expires, rental })
    notify(src, 'success', locale('rented', SizeLabel(sizeKey(point)), id, Config.RentDays, FormatMoney(size.price), pin))
    broadcast()
    return true
end)

lib.callback.register('ssf:renew', function(src, id)
    local point, r = Points[id], rentals[id]
    if not point or not r or r.citizenid ~= Bridge.id(src) or onSale(id) then return false end
    local base = math.max(r.expires, now())
    if base + Config.RentDays * DAY - now() > Config.MaxPrepaidDays * DAY then
        notify(src, 'error', locale('max_prepaid', Config.MaxPrepaidDays)) return false
    end
    local size = sizeOf(point)
    if not Bridge.pay(src, size.price, 'storage-rent') then notify(src, 'error', locale('no_money', FormatMoney(size.price))) return false end
    r.expires = base + Config.RentDays * DAY
    MySQL.query('UPDATE ssf_storage_rentals SET expires = ? WHERE unit = ?', { r.expires, id })
    notify(src, 'success', locale('renewed', id, os.date('%d/%m %H:%M', r.expires)))
    broadcast()
    return true
end)

lib.callback.register('ssf:setPin', function(src, id, pin)
    local r = rentals[id]
    if not r or r.citizenid ~= Bridge.id(src) or onSale(id) then return false end
    pin = validPin(pin)
    if not pin then notify(src, 'error', locale('code_digits')) return false end
    r.pin = pin
    grants[id] = nil
    MySQL.query('UPDATE ssf_storage_rentals SET pin = ? WHERE unit = ?', { pin, id })
    notify(src, 'success', locale('new_code', id, pin))
    return true
end)

lib.callback.register('ssf:release', function(src, id)
    local r = rentals[id]
    if not r or r.citizenid ~= Bridge.id(src) or onSale(id) then return false end
    wipeUnit(id)
    notify(src, 'primary', locale('released', id))
    broadcast()
    return true
end)

lib.callback.register('ssf:buyUpgrade', function(src, id)
    local r = rentals[id]
    if not r or not isOwner(src, id) then return false end
    local lvl = level(id)
    local u = Config.Upgrades[lvl + 1]
    if not u then notify(src, 'error', locale('all_upgrades')) return false end
    if not Bridge.pay(src, u.price, 'storage-upgrade') then notify(src, 'error', locale('no_money', FormatMoney(u.price))) return false end
    local m = meta[id]
    if not m or m.rental ~= r.rental then m = { rental = r.rental, level = 0 } end
    m.level = lvl + 1
    meta[id] = m
    saveMeta(id)
    notify(src, 'success', locale('upgrade_done', id, UpgradeLabel(u, lvl + 1)))
    return true
end)

lib.callback.register('ssf:buySale', function(src, id, pin)
    local point, r = Points[id], rentals[id]
    if not point or not r or not onSale(id) or not Bridge.exists(src) then return false end
    if not near(src, point.coords, 10.0) and not nearSite(src, 'reception', 6.0) then return false end
    pin = validPin(pin)
    if not pin then notify(src, 'error', locale('code_digits')) return false end
    local mine = rentedBy(src)
    if mine >= Config.MaxRentalsPerPlayer then notify(src, 'error', locale('too_many', mine)) return false end
    local price = salePrice(id)
    if not Bridge.pay(src, price, 'storage-auction') then notify(src, 'error', locale('no_money', FormatMoney(price))) return false end
    local old = r.citizenid
    r.citizenid, r.name, r.pin, r.expires = Bridge.id(src), Bridge.name(src), pin, now() + Config.RentDays * DAY
    meta[id].saleStart, meta[id].saleEnd = 0, 0
    saveMeta(id)
    MySQL.query('UPDATE ssf_storage_rentals SET citizenid = ?, owner_name = ?, pin = ?, expires = ? WHERE unit = ?',
        { r.citizenid, r.name, pin, r.expires, id })
    setUnitDoors(id, false)
    local prev = Bridge.online(old)
    if prev then notify(prev, 'error', locale('your_old_unit_sold', id)) end
    notify(src, 'success', locale('bought_sale', id, FormatMoney(price), pin))
    log('log_sold', id, r.name, FormatMoney(price))
    broadcast()
    return true
end)

local function unitObjects(id)
    local out = {}
    for _, o in pairs(placed) do
        if o.unit == id then out[#out + 1] = { id = o.id, kind = o.kind, label = objectLabel(o), amount = o.amount, ref = o.ref } end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

lib.callback.register('ssf:panel', function(src, id)
    local point = Points[id]
    if not point then return nil end
    local r, size = rentals[id], sizeOf(point)
    local slots, weight = capacity(id)
    local site = siteOf(id)
    local mine = r ~= nil and r.citizenid == Bridge.id(src) and not onSale(id)
    local out = {
        id = id, site = point.site, siteLabel = site and site.label,
        sizeKey = point.size, size = SizeLabel(sizeKey(point)), price = size.price, days = Config.RentDays,
        baseSlots = size.slots, baseWeight = size.weight, slots = slots, weight = weight, level = level(id),
        hasInterior = Interiors[id] ~= nil, rented = r ~= nil, mine = mine, access = hasAccess(src, id),
        owner = isOwner(src, id), now = now(),
        furnitureLimit = Config.FurnitureLimit[point.size] or 3, furnitureCount = countPlaced(id, 'furniture'),
        itemsLimit = Config.LooseItemsLimit, itemsCount = countPlaced(id, 'item'),
        upgrades = {}, catalog = {},
    }
    for i, u in ipairs(Config.Upgrades) do
        out.upgrades[i] = { label = UpgradeLabel(u, i), price = u.price, slots = u.slots, weight = u.weight, bought = i <= out.level }
    end
    for i, f in ipairs(Config.Furniture) do
        out.catalog[i] = { key = f.key, label = FurnitureLabel(f), price = f.price, slots = f.slots, weight = f.weight,
                           desc = FurnitureDesc(f), model = f.model }
    end
    if r and mine then
        out.pin, out.expires, out.expired = r.pin, r.expires, r.expires < now()
        out.untilText = os.date('%d/%m %H:%M', r.expires)
        out.graceUntil = os.date('%d/%m %H:%M', r.expires + Config.GraceDays * DAY)
    end
    if r and (out.access or mine) then out.objects = unitObjects(id) end
    if onSale(id) then
        local m = meta[id]
        out.sale = { price = salePrice(id), startAt = m.saleStart, endAt = m.saleEnd,
                     from = size.price * Config.Sale.startMultiplier, to = size.price * Config.Sale.floorMultiplier,
                     furniture = countPlaced(id, 'furniture'), items = countPlaced(id, 'item'), level = level(id) }
    end
    return out
end)

local SiteOrder = {}
for i, s in ipairs(FacilityData.sites) do SiteOrder[s.key] = i end

lib.callback.register('ssf:reception', function(src, key)
    local cid = Bridge.id(src)
    local here = Sites[key]
    local out = { site = here and key, label = here and here.label, mine = {}, sales = {}, sizes = {},
                  days = Config.RentDays, now = now() }
    for id, r in pairs(rentals) do
        local point = Points[id]
        local size, site = sizeOf(point), siteOf(id)
        local base = { id = id, size = SizeLabel(sizeKey(point)), site = point.site, siteLabel = site and site.label,
                       coords = { x = point.coords.x, y = point.coords.y, z = point.coords.z } }
        if onSale(id) then
            local m = meta[id]
            base.price, base.startAt, base.endAt = salePrice(id), m.saleStart, m.saleEnd
            base.from, base.to = size.price * Config.Sale.startMultiplier, size.price * Config.Sale.floorMultiplier
            base.furniture, base.items = countPlaced(id, 'furniture'), countPlaced(id, 'item')
            out.sales[#out.sales + 1] = base
        elseif r.citizenid == cid then
            base.pin, base.untilText, base.expired = r.pin, os.date('%d/%m %H:%M', r.expires), r.expires < now()
            out.mine[#out.mine + 1] = base
        end
    end
    local function rank(e) return e.site == key and 0 or (SiteOrder[e.site] or 99) end
    table.sort(out.mine, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return a.id < b.id
    end)
    table.sort(out.sales, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        return a.endAt < b.endAt
    end)
    for _, k in ipairs({ 'small', 'medium', 'large', 'container' }) do
        local s = Config.Sizes[k]
        if s then out.sizes[#out.sizes + 1] = { label = SizeLabel(k), price = s.price, slots = s.slots, weight = s.weight } end
    end
    return out
end)

local function openFor(src, id, r, label)
    local slots, weight = capacity(id)
    setUnitDoors(id, true, true)
    return Bridge.openStash(src, stashId(id, r), slots, weight, label or locale('stash_label', SizeLabel(sizeKey(Points[id])), id))
end

lib.callback.register('ssf:open', function(src, id, pin)
    local point, r = Points[id], rentals[id]
    if not point or not r or not near(src, point.coords, 8.0) then return false end
    if onSale(id) then notify(src, 'error', locale('on_sale')) return false end
    if not hasAccess(src, id) then
        if validPin(pin) == nil or validPin(pin) ~= r.pin then notify(src, 'error', locale('wrong_code')) return false end
        if r.expires < now() then notify(src, 'error', locale('locked_unpaid')) return false end
        grant(src, id)
    end
    if r.expires < now() then notify(src, 'error', locale('expired_renew')) return false end
    return openFor(src, id, r)
end)

lib.callback.register('ssf:police', function(src, id)
    local point, r = Points[id], rentals[id]
    if not point or not r or onSale(id) or not near(src, point.coords, 8.0) then return false end
    local _, _, duty = Bridge.job(src)
    if not hasJob(src, Config.PoliceJobs) or not duty then notify(src, 'error', locale('not_authorized')) return false end
    log('log_police', Bridge.name(src), (Bridge.job(src)), id, r.name or r.citizenid)
    grant(src, id)
    return openFor(src, id, r, locale('stash_police', id))
end)

local function policeOnline()
    local n = 0
    for _, s in ipairs(GetPlayers()) do
        local name = Bridge.job(tonumber(s))
        if name and Config.PoliceJobs[name] then n = n + 1 end
    end
    return n
end

lib.callback.register('ssf:lockpick', function(src, id)
    local L = Config.Lockpick
    local point, r = Points[id], rentals[id]
    if not L.enabled or not point or not r or onSale(id) or not near(src, point.coords, 8.0) then return false end
    if policeOnline() < L.minPolice then notify(src, 'error', locale('bad_moment')) return false end
    local item, chance
    for name, c in pairs(L.items) do
        if Bridge.itemCount(src, name) > 0 and (not chance or c > chance) then item, chance = name, c end
    end
    if not item then notify(src, 'error', locale('need_lockpick')) return false end
    if L.alertOwner then
        local owner = Bridge.online(r.citizenid)
        if owner then notify(owner, 'error', locale('alarm', id)) end
    end
    if L.alertPolice then Bridge.alertPolice(src, id, point.coords) end
    if math.random() > chance then
        if math.random() < L.breakChance then
            Bridge.removeItem(src, item, 1)
            notify(src, 'error', locale('lockpick_broke'))
        else
            notify(src, 'error', locale('lockpick_failed'))
        end
        return false
    end
    grant(src, id)
    return openFor(src, id, r, locale('stash_forced', id))
end)

local function tradeEntry(list, item)
    for _, e in ipairs(list) do if e.item == item then return e end end
end

local function tradeLabel(e) return e.label or LocaleText('item_' .. e.item) or Bridge.itemLabel(e.item) end

lib.callback.register('ssf:trade', function()
    local out = { sell = {}, buy = {}, max = Config.MaxTradeAmount }
    for i, e in ipairs(Config.Sell) do out.sell[i] = { item = e.item, label = tradeLabel(e), price = e.price } end
    for i, e in ipairs(Config.Buy) do out.buy[i] = { item = e.item, label = tradeLabel(e), price = e.price } end
    return out
end)

lib.callback.register('ssf:sell', function(src, item, amount)
    local e = tradeEntry(Config.Sell, item)
    amount = math.floor(tonumber(amount) or 0)
    if not e or amount < 1 or amount > Config.MaxTradeAmount or not nearSite(src, 'trade', 8.0) or not Bridge.exists(src) then return false end
    local label = tradeLabel(e)
    if Bridge.itemCount(src, item) < amount then notify(src, 'error', locale('not_enough_of', amount, label)) return false end
    if not Bridge.removeItem(src, item, amount) then return false end
    Bridge.addMoney(src, 'cash', e.price * amount, 'storage-trade')
    notify(src, 'success', locale('sold', amount, label, FormatMoney(e.price * amount)))
    return true
end)

lib.callback.register('ssf:buy', function(src, item, amount)
    local e = tradeEntry(Config.Buy, item)
    amount = math.floor(tonumber(amount) or 0)
    if not e or amount < 1 or amount > Config.MaxTradeAmount or not nearSite(src, 'trade', 8.0) or not Bridge.exists(src) then return false end
    local label = tradeLabel(e)
    if not Bridge.canCarry(src, item, amount) then notify(src, 'error', locale('cannot_carry')) return false end
    if not Bridge.pay(src, e.price * amount, 'storage-trade') then notify(src, 'error', locale('no_money', FormatMoney(e.price * amount))) return false end
    Bridge.giveItem(src, item, amount)
    notify(src, 'success', locale('bought', amount, label, FormatMoney(e.price * amount)))
    return true
end)

local function defaultZone(key)
    local s = Sites[key]
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    local function add(c)
        if c then x0, y0, x1, y1 = math.min(x0, c.x), math.min(y0, c.y), math.max(x1, c.x), math.max(y1, c.y) end
    end
    for _, list in ipairs({ 'units', 'containers', 'doors' }) do
        for _, e in ipairs(FacilityData[list]) do if e.site == key then add(e.coords) end end
    end
    for _, b in ipairs(FacilityData.barriers) do if b.site == key then add(b.hinge) end end
    for _, f in ipairs({ 'reception', 'trade', 'gate' }) do add(s[f] and s[f].coords) end
    if x0 == math.huge then x0, y0, x1, y1 = s.lot.min.x, s.lot.min.y, s.lot.max.x, s.lot.max.y end
    local m = Config.Zone.margin
    return { { x = x0 - m, y = y0 - m }, { x = x1 + m, y = y0 - m }, { x = x1 + m, y = y1 + m }, { x = x0 - m, y = y1 + m } }
end

local function cleanZone(pts)
    if type(pts) ~= 'table' or #pts < 3 then return nil end
    local out = {}
    for i, p in ipairs(pts) do
        local x, y = tonumber(type(p) == 'table' and (p.x or p[1])), tonumber(type(p) == 'table' and (p.y or p[2]))
        if not x or not y then return nil end
        out[i] = { x = x, y = y }
    end
    return out
end

do
    local ok, saved = pcall(json.decode, LoadResourceFile(RES, 'zones.json') or '')
    if not ok or type(saved) ~= 'table' then saved = {} end
    local zones = {}
    for _, s in ipairs(FacilityData.sites) do
        zones[s.key] = cleanZone(Config.Zone.polygons and Config.Zone.polygons[s.key]) or cleanZone(saved[s.key]) or defaultZone(s.key)
    end
    GlobalState.ssf_zones = zones
end
