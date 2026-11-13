Bridge = {}

local function running(name)
    local s = GetResourceState(name)
    return s == 'started' or s == 'starting'
end

local function detect(setting, list)
    if setting and setting ~= 'auto' then return setting end
    for _, name in ipairs(list) do if running(name) then return name end end
end

local Frameworks = {}

Frameworks['qb-core'] = function()
    local QB = exports['qb-core']:GetCoreObject()
    local F = {}
    local function get(src) return QB.Functions.GetPlayer(src) end
    function F.id(src) local p = get(src) return p and p.PlayerData.citizenid end
    function F.name(src)
        local p = get(src)
        local ci = p and p.PlayerData.charinfo or {}
        return (((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''))
    end
    function F.job(src)
        local p = get(src)
        local j = p and p.PlayerData.job or {}
        return j.name, tonumber(type(j.grade) == 'table' and j.grade.level or j.grade) or 0, j.onduty ~= false
    end
    function F.pay(src, amount, reason)
        local p = get(src)
        if not p then return false end
        return p.Functions.RemoveMoney('bank', amount, reason) or p.Functions.RemoveMoney('cash', amount, reason)
    end
    function F.give(src, account, amount, reason)
        local p = get(src)
        return p ~= nil and p.Functions.AddMoney(account, amount, reason)
    end
    function F.online(id)
        local p = QB.Functions.GetPlayerByCitizenId(id)
        return p and p.PlayerData.source
    end
    function F.exists(src) return get(src) ~= nil end
    function F.items(src) local p = get(src) return p and p.PlayerData.items or {} end
    function F.itemDef(name) return QB.Shared.Items[name] or QB.Shared.Items[name:lower()] end
    function F.onLoaded(cb) AddEventHandler('QBCore:Server:PlayerLoaded', function(p) cb(p.PlayerData.source) end) end
    return F
end

Frameworks['qbx_core'] = function()
    local Q = exports.qbx_core
    local F = {}
    local function get(src) return Q:GetPlayer(src) end
    function F.id(src) local p = get(src) return p and p.PlayerData.citizenid end
    function F.name(src)
        local p = get(src)
        local ci = p and p.PlayerData.charinfo or {}
        return (((ci.firstname or '') .. ' ' .. (ci.lastname or '')):gsub('^%s+', ''))
    end
    function F.job(src)
        local p = get(src)
        local j = p and p.PlayerData.job or {}
        return j.name, tonumber(type(j.grade) == 'table' and j.grade.level or j.grade) or 0, j.onduty ~= false
    end
    function F.pay(src, amount, reason)
        if not get(src) then return false end
        return Q:RemoveMoney(src, 'bank', amount, reason) or Q:RemoveMoney(src, 'cash', amount, reason)
    end
    function F.give(src, account, amount, reason) return Q:AddMoney(src, account, amount, reason) end
    function F.online(id)
        local p = Q:GetPlayerByCitizenId(id)
        return p and p.PlayerData.source
    end
    function F.exists(src) return get(src) ~= nil end
    function F.items(src) local p = get(src) return p and p.PlayerData.items or {} end
    function F.itemDef() return nil end
    function F.onLoaded(cb) AddEventHandler('QBCore:Server:PlayerLoaded', function(p) cb(p.PlayerData.source) end) end
    return F
end

Frameworks['es_extended'] = function()
    local ESX = exports.es_extended:getSharedObject()
    local F = {}
    local function get(src) return ESX.GetPlayerFromId(src) end
    function F.id(src) local p = get(src) return p and p.identifier end
    function F.name(src) local p = get(src) return p and p.getName() or '' end
    function F.job(src)
        local p = get(src)
        local j = p and p.getJob() or {}
        return j.name, tonumber(j.grade) or 0, j.onDuty ~= false
    end
    function F.pay(src, amount, reason)
        local p = get(src)
        if not p then return false end
        local bank = p.getAccount('bank')
        if bank and bank.money >= amount then p.removeAccountMoney('bank', amount, reason) return true end
        if p.getMoney() >= amount then p.removeMoney(amount, reason) return true end
        return false
    end
    function F.give(src, account, amount, reason)
        local p = get(src)
        if not p then return false end
        p.addAccountMoney(account == 'cash' and 'money' or account, amount, reason)
        return true
    end
    function F.online(id)
        local p = ESX.GetPlayerFromIdentifier(id)
        return p and p.source
    end
    function F.exists(src) return get(src) ~= nil end
    function F.items(src) local p = get(src) return p and p.getInventory() or {} end
    function F.itemDef(name) return ESX.Items and ESX.Items[name] end
    function F.onLoaded(cb) AddEventHandler('esx:playerLoaded', function(src) cb(src) end) end
    return F
end

local function count(e)
    return tonumber(e.count) or (type(e.amount) == 'table' and tonumber(e.amount.actual)) or tonumber(e.amount) or 0
end

local function isWeapon(name, def)
    return (def and (def.isWeapon or def.weapon or def.type == 'weapon')) and true or name:lower():find('^weapon_') ~= nil
end

local Inventories = {}

Inventories['ox_inventory'] = function()
    local ox = exports.ox_inventory
    local I = {}
    function I.register(id, label, slots, weight)
        ox:RegisterStash(id, label, slots, weight)
        pcall(function() ox:SetSlotCount(id, slots) end)
        pcall(function() ox:SetMaxWeight(id, weight) end)
    end
    function I.open(src, id, slots, weight, label)
        I.register(id, label, slots, weight)
        ox:forceOpenInventory(src, 'stash', id)
        return true
    end
    function I.stash(id)
        local ok, items = pcall(function() return ox:GetInventoryItems(id) end)
        if not ok then return nil end
        return items or {}
    end
    function I.def(name)
        local d = ox:Items(name) or ox:Items(name:lower())
        return d and { label = d.label, weapon = d.weapon or name:upper():find('^WEAPON_') ~= nil }
    end
    function I.items(src) return ox:GetInventoryItems(src) or {} end
    function I.image(e) return e.metadata and e.metadata.image and ('nui://ox_inventory/web/images/%s.png'):format(e.metadata.image)
        or ('nui://ox_inventory/web/images/%s.png'):format(e.name) end
    function I.removeSlot(src, slot, name, amount) return (ox:RemoveItem(src, name, amount, nil, slot)) end
    function I.canCarry(src, name, amount, metadata) return (ox:CanCarryItem(src, name, amount, metadata)) end
    function I.give(src, name, amount, metadata) return (ox:AddItem(src, name, amount, metadata)) end
    function I.count(src, name) return ox:Search(src, 'count', name) or 0 end
    function I.remove(src, name, amount) return (ox:RemoveItem(src, name, amount)) end
    function I.clear(id) pcall(function() ox:ClearInventory(id) end) end
    return I
end

local function qbFamily(res)
    return function()
        local inv = exports[res]
        local major = tonumber((GetResourceMetadata(res, 'version', 0) or ''):match('^(%d+)')) or 0
        local modern = res == 'qb-inventory' and major >= 2
        local byExport = modern or res == 'ps-inventory'
        local I = {}
        function I.register() end
        function I.open(src, id, slots, weight, label)
            if byExport then
                inv:OpenInventory(src, id, { label = label, maxweight = weight, slots = slots })
            else
                TriggerClientEvent('ssf:legacyStash', src, id, slots, weight, label)
            end
            return true
        end
        local function saved(id)
            local row
            if modern then
                row = MySQL.single.await('SELECT items FROM inventories WHERE identifier = ?', { id })
            else
                row = MySQL.single.await('SELECT items FROM stashitems WHERE stash = ?', { id })
            end
            return row and json.decode(row.items or '[]') or {}
        end
        function I.stash(id)
            if modern then
                local ok, data = pcall(function() return inv:GetInventory(id) end)
                if ok and data and data.items then return data.items end
            end
            local ok, items = pcall(saved, id)
            if not ok then return nil end
            return items
        end
        function I.def(name)
            local d = Bridge.fw.itemDef(name)
            return d and { label = d.label, weapon = d.type == 'weapon', image = d.image }
        end
        function I.items(src) return Bridge.fw.items(src) end
        function I.image(e)
            local d = Bridge.fw.itemDef(e.name)
            return ('nui://%s/html/images/%s'):format(res, e.image or (d and d.image) or (e.name .. '.png'))
        end
        function I.removeSlot(src, slot, name, amount) return (inv:RemoveItem(src, name, amount, slot, 'ssf')) end
        function I.canCarry(src, name, amount)
            if not modern then return true end
            return (inv:CanAddItem(src, name, amount))
        end
        function I.give(src, name, amount, metadata) return (inv:AddItem(src, name, amount, false, metadata, 'ssf')) end
        function I.count(src, name)
            local ok, n = pcall(function() return inv:GetItemCount(src, name) end)
            if ok and n then return n end
            local total = 0
            for _, e in pairs(Bridge.fw.items(src)) do if e.name == name then total = total + count(e) end end
            return total
        end
        function I.remove(src, name, amount) return (inv:RemoveItem(src, name, amount, false, 'ssf')) end
        function I.clear(id)
            if modern then
                pcall(function() inv:ClearStash(id) end)
                MySQL.query('DELETE FROM inventories WHERE identifier = ?', { id })
                return
            end
            MySQL.query('DELETE FROM stashitems WHERE stash = ?', { id })
        end
        return I
    end
end
Inventories['qb-inventory'] = qbFamily('qb-inventory')
Inventories['ps-inventory'] = qbFamily('ps-inventory')
Inventories['lj-inventory'] = qbFamily('lj-inventory')

local fw, inv

local function framework()
    if fw then return fw end
    local name = detect(Config.Framework, { 'qbx_core', 'qb-core', 'es_extended' })
    local make = name and Frameworks[name]
    if not make then error(('no supported framework found (%s)'):format(tostring(Config.Framework))) end
    fw = make()
    fw.resource = name
    return fw
end

local function inventory()
    if inv then return inv end
    local name = detect(Config.Inventory, { 'ox_inventory', 'qb-inventory', 'ps-inventory', 'lj-inventory' })
    local make = name and Inventories[name]
    if not make then error(('no supported inventory found (%s)'):format(tostring(Config.Inventory))) end
    inv = make()
    inv.resource = name
    return inv
end

Bridge.fw = setmetatable({}, { __index = function(_, k) return framework()[k] end })
Bridge.inv = setmetatable({}, { __index = function(_, k) return inventory()[k] end })

function Bridge.id(src) return framework().id(src) end
function Bridge.name(src) return framework().name(src) end
function Bridge.job(src) return framework().job(src) end
function Bridge.pay(src, amount, reason) return amount <= 0 or (framework().pay(src, amount, reason) and true or false) end
function Bridge.addMoney(src, account, amount, reason) if amount > 0 then framework().give(src, account, amount, reason) end end
function Bridge.online(id) return id and framework().online(id) end
function Bridge.exists(src) return framework().exists(src) end
function Bridge.onPlayerLoaded(cb)
    CreateThread(function()
        local tries = 0
        while not pcall(framework) do
            tries = tries + 1
            if tries == 30 then print(('^1[%s] no supported framework is running^7'):format(GetCurrentResourceName())) end
            Wait(1000)
        end
        framework().onLoaded(cb)
    end)
end

function Bridge.registerStash(id, label, slots, weight) inventory().register(id, label, slots, weight) end
function Bridge.openStash(src, id, slots, weight, label) return inventory().open(src, id, slots, weight, label) and true or false end
function Bridge.clearStash(id) inventory().clear(id) end

function Bridge.stashItems(id)
    local raw = inventory().stash(id)
    if raw == nil then return nil end
    local sum, order = {}, {}
    for _, e in pairs(raw) do
        local n = count(e)
        if e.name and n > 0 then
            if not sum[e.name] then order[#order + 1] = e.name end
            sum[e.name] = (sum[e.name] or 0) + n
        end
    end
    local out = {}
    for i, name in ipairs(order) do out[i] = { name = name, count = sum[name] } end
    return out
end

function Bridge.itemDef(name) return inventory().def(name) end

function Bridge.itemLabel(name)
    local d = inventory().def(name)
    return d and d.label or name
end

function Bridge.playerItems(src)
    local I = inventory()
    local out = {}
    for _, e in pairs(I.items(src) or {}) do
        local n = count(e)
        if e.name and n > 0 then
            local def = I.def(e.name)
            local meta = e.metadata or e.info
            out[#out + 1] = { slot = tonumber(e.slot), name = e.name, label = e.label or (def and def.label) or e.name,
                              count = n, metadata = type(meta) == 'table' and meta or {}, image = I.image(e),
                              weapon = isWeapon(e.name, def), model = def and def.model }
        end
    end
    table.sort(out, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return out
end

function Bridge.removeFromSlot(src, slot, name, amount) return inventory().removeSlot(src, slot, name, amount) and true or false end
function Bridge.canCarry(src, name, amount, metadata) return inventory().canCarry(src, name, amount, metadata) and true or false end
function Bridge.giveItem(src, name, amount, metadata) return inventory().give(src, name, amount, metadata) and true or false end
function Bridge.itemCount(src, name) return tonumber(inventory().count(src, name)) or 0 end
function Bridge.removeItem(src, name, amount) return inventory().remove(src, name, amount) and true or false end

local notifyKind = { primary = 'inform', info = 'inform', success = 'success', error = 'error' }

function Bridge.notify(src, kind, text)
    lib.notify(src, { description = text, type = notifyKind[kind] or 'inform' })
end

function Bridge.alertPolice(src, unit, coords)
    local D = Config.Dispatch
    if detect(D.system, { 'ps-dispatch' }) == 'ps-dispatch' then
        TriggerClientEvent('ssf:dispatch', src, unit)
        return
    end
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        local name, grade, duty = Bridge.job(id)
        local min = Config.PoliceJobs[name or '']
        if min and grade >= min and duty then
            Bridge.notify(id, 'error', locale('dispatch_notify', unit))
            TriggerClientEvent('ssf:policeBlip', id, unit, coords)
        end
    end
end

function Bridge.describe()
    return ('%s / %s'):format(framework().resource, inventory().resource)
end
