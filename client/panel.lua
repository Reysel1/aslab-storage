local view = nil
local handlers = {}
local shown = false
local Panel = {}

local function call(...) return SSF.call(...) end
local function notify(kind, text) SSF.notify(kind, text) end
local money, kg = FormatMoney, FormatKg

local function timeLeft(endAt)
    local s = math.max(0, math.floor(endAt - SSF.serverNow()))
    local h, m = s // 3600, (s % 3600) // 60
    return h > 0 and locale('time_hm', h, m) or locale('time_ms', m, s % 60)
end

local function pct(a, b) return b > 0 and math.floor(a / b * 100 + 0.5) or 0 end
local function saleElapsed(s) return pct(SSF.serverNow() - s.startAt, math.max(1, s.endAt - s.startAt)) end

local function strings()
    return { close = locale('ui_close'), hold = locale('ui_hold'), cancel = locale('ui_cancel'), confirm = locale('ui_confirm'),
             code = locale('ui_code_placeholder'), loading = locale('ui_loading') }
end

local function focus() SetNuiFocus(shown, shown) end

local function gps(c, text)
    SetNewWaypoint(c.x + 0.0, c.y + 0.0)
    notify('primary', text)
end

local function codeAction(button, run)
    return { type = 'code', label = button }, function(value)
        local pin = tostring(value or '')
        if not pin:match('^%d%d%d%d$') then return notify('error', locale('code_digits')) end
        run(pin)
    end
end

local act

local function tabsOf(v)
    local d = v.data
    if v.kind == 'reception' then
        return { { 'mine', locale('tab_mine'), 'key-round', #d.mine > 0 and tostring(#d.mine) or nil },
                 { 'sales', locale('tab_sales'), 'tag', #d.sales > 0 and tostring(#d.sales) or nil },
                 { 'prices', locale('tab_prices'), 'receipt' } }
    end
    if v.kind == 'trade' then
        return { { 'sell', locale('tab_sell'), 'recycle' }, { 'buy', locale('tab_buy'), 'shopping-cart' } }
    end
    if d.sale or not d.rented then return {} end
    local t = { { 'summary', locale('tab_summary'), 'layout-dashboard' } }
    if d.mine then t[#t + 1] = { 'upgrades', locale('tab_upgrades'), 'circle-arrow-up', ('%d/%d'):format(d.level, #d.upgrades) } end
    if d.hasInterior and d.mine then t[#t + 1] = { 'furniture', locale('tab_furniture'), 'armchair', ('%d/%d'):format(d.furnitureCount, d.furnitureLimit) } end
    if d.hasInterior and d.access then t[#t + 1] = { 'drop', locale('tab_drop'), 'hand', ('%d/%d'):format(d.itemsCount, d.itemsLimit) } end
    if d.access or d.mine then t[#t + 1] = { 'content', locale('tab_content'), 'package', #(d.objects or {}) > 0 and tostring(#d.objects) or nil } end
    return t
end

local function unitBody(v)
    local d, tab = v.data, v.tab
    if d.sale then
        local s = d.sale
        local buyAction, buyRun = codeAction(locale('btn_buy'), function(pin) act('ssf:buySale', true, d.id, pin) end)
        return { title = locale('sale_title'), icon = 'tag',
                 meter = { text = locale('sale_left', timeLeft(s.endAt)), value = saleElapsed(s) }, list = {
            { label = locale('sale_price_now'), icon = 'trending-down', tag = money(SSF.salePrice(s)), tone = 'accent',
              description = locale('sale_drops_to', money(s.to)), progress = saleElapsed(s) },
            { label = locale('sale_inside'), icon = 'package', tag = ('%d + %d'):format(s.furniture, s.items),
              description = locale('sale_inside_desc', s.furniture, s.items) },
            { label = locale('capacity'), icon = 'circle-arrow-up', tag = locale('slots', d.slots),
              description = locale('sale_capacity_desc', s.level, #d.upgrades, kg(d.weight)), progress = pct(s.level, #d.upgrades) },
            { label = locale('sale_buy_now'), icon = 'hand-coins', tone = 'accent', tag = money(SSF.salePrice(s)),
              description = locale('sale_buy_desc', d.days), action = buyAction, run = buyRun },
        } }
    end
    if not d.rented then
        local list = {
            { label = locale('rent_price'), icon = 'calendar-clock', tag = money(d.price), tone = 'muted',
              description = locale('rent_price_desc', d.days) },
            { label = locale('capacity'), icon = 'package', tag = locale('slots', d.baseSlots), tone = 'muted',
              description = locale('rent_capacity_desc', kg(d.baseWeight)) },
        }
        if d.hasInterior then
            list[#list + 1] = { label = locale('rent_furniture'), icon = 'armchair', tag = locale('up_to', d.furnitureLimit),
                                tone = 'muted', description = locale('rent_furniture_desc') }
        end
        local a, run = codeAction(locale('btn_rent'), function(pin) act('ssf:rent', false, d.id, pin) end)
        list[#list + 1] = { label = locale('rent_action'), icon = 'key-round', tone = 'accent', tag = money(d.price),
                            description = locale('rent_action_desc'), action = a, run = run }
        return { title = locale('rent_title', d.id), icon = 'key-round', meter = { text = d.size }, list = list }
    end
    if tab == 'summary' then
        local list = {
            { label = locale('open_stash'), icon = 'warehouse', tone = 'accent', tag = locale('slots', d.slots),
              description = locale('load_desc', kg(d.weight)),
              use = function()
                  Panel.close()
                  call('ssf:open', d.id)
              end },
        }
        if d.mine then
            local placedCount = #(d.objects or {})
            list[2] = { label = locale('renew', d.days), icon = 'calendar-clock', tag = money(d.price),
                        tone = d.expired and 'danger' or nil,
                        description = d.expired and locale('expired_on_sale', d.graceUntil) or locale('until', d.untilText),
                        action = { type = 'button', label = locale('btn_pay') }, run = function() act('ssf:renew', false, d.id) end }
            local a, run = codeAction(locale('btn_change'), function(p) act('ssf:setPin', false, d.id, p) end)
            list[3] = { label = locale('access_code'), icon = 'key-round', tag = d.pin, description = locale('access_code_desc'),
                        action = a, run = run }
            list[4] = { label = locale('release'), icon = 'log-out', tone = 'danger',
                        description = placedCount > 0 and locale('release_desc_n', placedCount) or locale('release_desc'),
                        action = { type = 'hold', label = locale('btn_release'), time = 1400, danger = true },
                        run = function() act('ssf:release', true, d.id) end }
        else
            list[2] = { label = locale('temp_access'), icon = 'clock', tone = 'muted', description = locale('temp_access_desc') }
        end
        return { title = locale('tab_summary'), icon = 'layout-dashboard', list = list,
                 meter = { text = d.mine and (d.expired and locale('expired') or locale('until', d.untilText)) or locale('temp_access') } }
    elseif tab == 'upgrades' then
        local list = {}
        for i, u in ipairs(d.upgrades) do
            local nextOne = i - 1 == d.level
            list[i] = { label = u.label, icon = u.bought and 'circle-check' or 'circle-arrow-up',
                        on = u.bought, tag = u.bought and locale('installed') or money(u.price),
                        tone = u.bought and 'muted' or nextOne and 'accent' or nil,
                        description = locale('upgrade_desc', u.slots, kg(u.weight)),
                        action = nextOne and { type = 'button', label = locale('btn_buy') } or nil,
                        run = nextOne and function() act('ssf:buyUpgrade', false, d.id) end or nil }
        end
        return { title = locale('tab_upgrades'), icon = 'circle-arrow-up', list = list,
                 meter = { text = ('%d/%d'):format(d.level, #d.upgrades), value = pct(d.level, #d.upgrades) } }
    elseif tab == 'furniture' then
        local full, list = d.furnitureCount >= d.furnitureLimit, {}
        for i, f in ipairs(d.catalog) do
            list[i] = { label = f.label, img = ('thumbs/%s.png'):format(f.key), tag = money(f.price),
                        description = locale('furniture_desc', f.desc, f.slots, kg(f.weight)),
                        use = function()
                            if full then return notify('error', locale('furniture_full_remove', d.furnitureLimit)) end
                            Panel.close()
                            SSF.placeFurniture(d.id, f.key)
                        end }
        end
        return { title = locale('tab_furniture'), icon = 'armchair', grid = true, list = list,
                 meter = { text = ('%d/%d'):format(d.furnitureCount, d.furnitureLimit), value = pct(d.furnitureCount, d.furnitureLimit) } }
    elseif tab == 'drop' then
        local meter = { text = ('%d/%d'):format(d.itemsCount, d.itemsLimit), value = pct(d.itemsCount, d.itemsLimit) }
        if d.itemsCount >= d.itemsLimit or not v.inv or #v.inv == 0 then
            local row = d.itemsCount >= d.itemsLimit
                and { label = locale('items_full_title', d.itemsLimit), icon = 'triangle-alert', tone = 'danger', description = locale('items_full_desc') }
                or not v.inv and { label = locale('checking_pockets'), icon = 'loader', tone = 'muted' }
                or { label = locale('nothing_to_drop'), icon = 'package-open', tone = 'muted' }
            return { title = locale('tab_drop'), icon = 'hand', list = { row }, meter = meter }
        end
        local list = {}
        for i, it in ipairs(v.inv) do
            local function drop(n)
                Panel.close()
                SSF.dropItem(d.id, it, math.max(1, math.min(it.count, math.floor(tonumber(n) or it.count))))
            end
            list[i] = { label = it.label, img = it.img ~= '' and it.img or nil, count = it.count,
                        description = it.serial and locale('serial', it.serial) or nil,
                        use = function() drop(it.count) end,
                        action = it.count > 1 and { type = 'amount', label = locale('btn_place'), min = 1, max = it.count, value = it.count } or nil,
                        run = it.count > 1 and drop or nil }
        end
        return { title = locale('tab_drop'), icon = 'hand', grid = true, list = list, meter = meter }
    end
    local list = {}
    for i, o in ipairs(d.objects or {}) do
        local furniture = o.kind == 'furniture'
        list[i] = { label = o.label, icon = furniture and 'armchair' or 'package', tone = 'muted',
                    tag = furniture and locale('furniture_tag') or ('x%d'):format(o.amount),
                    description = furniture and locale('furniture_own_stash') or locale('loose_item') }
    end
    if #list == 0 then
        list[1] = { label = locale('empty_unit'), icon = 'package-open', tone = 'muted', description = locale('empty_unit_desc') }
    end
    return { title = locale('tab_content'), icon = 'package', list = list, meter = { text = locale('content_meter', #(d.objects or {})) } }
end

local openUnit

local function receptionBody(v)
    local d, list = v.data, {}
    if v.tab == 'mine' then
        for i, m in ipairs(d.mine) do
            local here = m.site == v.site
            list[i] = { label = locale('unit_n', m.id), icon = 'key-round',
                        tag = m.expired and locale('expired_tag') or m.size, tone = m.expired and 'danger' or nil,
                        description = locale('mine_desc', here and '' or (m.siteLabel or '?') .. ' · ', m.pin,
                                         m.expired and locale('unpaid') or locale('until', m.untilText)),
                        use = function() gps(m.coords, locale('gps_unit', m.id)) end,
                        action = here and { type = 'button', label = locale('btn_view') } or nil,
                        run = here and function() openUnit(m.id) end or nil }
        end
        if #list == 0 then
            list[1] = { label = locale('none_yet'), icon = 'package-open', tone = 'muted', description = locale('none_yet_desc') }
        end
        return { title = locale('tab_mine'), icon = 'key-round', list = list, meter = { text = locale('rented_n', #d.mine) } }
    elseif v.tab == 'sales' then
        for i, s in ipairs(d.sales) do
            local here = s.site == v.site
            list[i] = { label = ('%s · %s'):format(s.id, s.size), icon = 'tag', tag = money(SSF.salePrice(s)), tone = 'accent',
                        description = locale('sales_desc', here and '' or (s.siteLabel or '?') .. ' · ', s.furniture, s.items, timeLeft(s.endAt)),
                        progress = saleElapsed(s),
                        use = function()
                            if here then return openUnit(s.id) end
                            gps(s.coords, locale('gps_sale', s.id, s.siteLabel or '?'))
                        end,
                        action = { type = 'button', label = locale('btn_gps') },
                        run = function() gps(s.coords, locale('gps_sale', s.id, s.siteLabel or '?')) end }
        end
        if #list == 0 then list[1] = { label = locale('no_sales'), icon = 'package-open', tone = 'muted', description = locale('no_sales_desc') } end
        return { title = locale('tab_sales'), icon = 'tag', list = list, meter = { text = locale('sales_meter') } }
    end
    for i, s in ipairs(d.sizes) do
        list[i] = { label = s.label, icon = 'warehouse', tag = money(s.price), tone = 'muted',
                    description = locale('size_desc', s.slots, kg(s.weight), d.days) }
    end
    return { title = locale('tab_prices'), icon = 'receipt', list = list, meter = { text = locale('every_days', d.days) } }
end

local function tradeBody(v)
    local d, list = v.data, {}
    local selling = v.tab == 'sell'
    for i, e in ipairs(selling and d.sell or d.buy) do
        list[i] = { label = e.label, icon = selling and 'recycle' or 'shopping-cart', tag = money(e.price),
                    description = locale('per_unit'),
                    action = { type = 'amount', label = selling and locale('btn_sell') or locale('btn_buy'), min = 1, max = d.max, value = 1 },
                    run = function(n) act(selling and 'ssf:sell' or 'ssf:buy', false, e.item, math.floor(tonumber(n) or 1)) end }
    end
    return { title = selling and locale('tab_sell') or locale('tab_buy'), icon = selling and 'recycle' or 'shopping-cart', list = list,
             meter = { text = selling and locale('sell_meter') or locale('buy_meter') } }
end

local FIELDS = { 'label', 'icon', 'img', 'description', 'count', 'on', 'tag', 'tone', 'progress', 'action' }

local function build()
    handlers = {}
    local v = view
    if not v then return nil end
    local tabs = tabsOf(v)
    local valid = false
    for _, t in ipairs(tabs) do if t[1] == v.tab then valid = true end end
    if not valid then v.tab = tabs[1] and tabs[1][1] or nil end
    local nav = {}
    for i, t in ipairs(tabs) do nav[i] = { id = t[1], label = t[2], icon = t[3], badge = t[4], active = t[1] == v.tab } end
    local body = v.kind == 'reception' and receptionBody(v) or v.kind == 'trade' and tradeBody(v) or unitBody(v)
    if v.kind == 'unit' and v.tab == 'drop' and not v.inv and not v.loadingInv then
        v.loadingInv = true
        CreateThread(function()
            v.inv = call('ssf:invItems') or {}
            v.loadingInv = false
            if view == v then Panel.push() end
        end)
    end
    local items = {}
    for slot, r in ipairs(body.list) do
        local item = { use = r.use ~= nil }
        for _, f in ipairs(FIELDS) do item[f] = r[f] end
        items[slot] = item
        handlers[slot] = { use = r.use, run = r.run }
    end
    local d = v.data
    local title, subtitle
    if v.kind == 'reception' then
        title, subtitle = locale('reception_title'), d.label
    elseif v.kind == 'trade' then
        local s = FacilityData.siteByKey[v.site]
        title, subtitle = locale('trade_title'), s and s.label
    else
        title = locale('unit_n', v.id)
        subtitle = ('%s%s'):format(d.siteLabel and d.siteLabel .. ' · ' or '', d.sale and locale('seized') or not d.rented and locale('free') or d.size)
    end
    return { title = title, subtitle = subtitle, tabs = nav, key = ('%s:%s:%s'):format(v.kind, v.id or v.site, v.tab or 'main'),
             body = { title = body.title, icon = body.icon, meter = body.meter, layout = body.grid and 'grid' or 'rows', items = items } }
end

function Panel.push()
    if not view or not shown then return end
    SendNUIMessage({ action = 'panel', open = true, view = build(), strings = strings() })
end

local function reload(v)
    local data
    if v.kind == 'reception' then data = call('ssf:reception', v.site)
    elseif v.kind == 'trade' then data = call('ssf:trade', v.site)
    else data = call('ssf:panel', v.id) end
    if view ~= v then return end
    if not data then return Panel.close() end
    v.data = data
    if v.tab == 'drop' then v.inv = nil end
    Panel.push()
end

act = function(name, close, ...)
    local args, v = { ... }, view
    CreateThread(function()
        local ok = call(name, table.unpack(args))
        if ok and close and name ~= 'ssf:buySale' then return Panel.close() end
        if view == v then reload(v) end
    end)
end

local function open(kind, id, site)
    CreateThread(function()
        local data
        if kind == 'reception' then data = call('ssf:reception', site)
        elseif kind == 'trade' then data = call('ssf:trade', site)
        else data = call('ssf:panel', id) end
        if not data then return end
        local old = view
        view = { kind = kind, id = id, site = site, data = data,
                 tab = old and old.kind == kind and old.id == id and old.site == site and old.tab or nil }
        shown = true
        focus()
        Panel.push()
    end)
end

openUnit = function(id) open('unit', id, FacilityData.unitSite[id]) end
SSF.openUnit = openUnit
SSF.openReception = function(key) open('reception', nil, key) end
SSF.openTrade = function(key) open('trade', nil, key) end

function Panel.close()
    if not view and not shown then return end
    view, shown, handlers = nil, false, {}
    SendNUIMessage({ action = 'panel', open = false })
    focus()
end
SSF.closePanel = Panel.close

RegisterNUICallback('ssf:tab', function(d, cb)
    cb(true)
    local v = view
    if not v or not d or v.tab == d.id then return end
    v.tab = d.id
    if d.id == 'drop' then v.inv = nil end
    Panel.push()
end)

RegisterNUICallback('ssf:use', function(d, cb)
    cb(true)
    local h = d and handlers[tonumber(d.slot)]
    if h and h.use then CreateThread(h.use) end
end)

RegisterNUICallback('ssf:action', function(d, cb)
    cb(true)
    local h = d and handlers[tonumber(d.slot)]
    if h and h.run then CreateThread(function() h.run(d.value) end) end
end)

RegisterNUICallback('ssf:close', function(_, cb)
    cb(true)
    Panel.close()
end)

CreateThread(function()
    while true do
        local v = view
        if v and shown then
            local me = GetEntityCoords(cache.ped)
            if not SSF.inZone(v.site, me, true) or IsEntityDead(cache.ped) then Panel.close() end
        end
        Wait(1000)
    end
end)

CreateThread(function()
    while true do
        local v = view
        if shown and v and ((v.kind == 'unit' and v.data.sale) or (v.kind == 'reception' and v.tab == 'sales' and #v.data.sales > 0)) then
            Panel.push()
        end
        Wait(1000)
    end
end)

local pendingReload = false
RegisterNetEvent('ssf:state', function()
    if not view or view.kind == 'trade' or pendingReload then return end
    pendingReload = true
    SetTimeout(300, function()
        pendingReload = false
        local v = view
        if v and shown then reload(v) end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if shown then SetNuiFocus(false, false) end
end)
