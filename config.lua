Config = {}

Config.Framework = 'auto'
Config.Inventory = 'auto'
Config.Target = 'auto'
Config.Progress = 'circle'

Config.Blip = { enabled = true, sprite = 473, color = 47, scale = 0.8 }

Config.RentDays = 7
Config.MaxPrepaidDays = 28
Config.GraceDays = 3
Config.MaxRentalsPerPlayer = 3

Config.Sizes = {
    small     = { price = 750,  slots = 30, weight = 150000 },
    medium    = { price = 1200, slots = 45, weight = 300000 },
    large     = { price = 2000, slots = 70, weight = 600000 },
    container = { price = 2500, slots = 80, weight = 800000 },
}

Config.PoliceJobs = { police = 0, sheriff = 0 }
Config.PoliceSearchTime = 5000

Config.Lockpick = {
    enabled = true,
    items = { advancedlockpick = 0.60, lockpick = 0.35 },
    breakChance = 0.5,
    time = 12000,
    minPolice = 0,
    alertOwner = true,
    alertPolice = true,
}

Config.Dispatch = {
    system = 'auto',
    code = '10-31',
    blip = { sprite = 161, color = 1, scale = 1.2, seconds = 60 },
}

Config.Sell = {
    { item = 'metalscrap', price = 6 },
    { item = 'iron',       price = 9 },
    { item = 'steel',      price = 12 },
    { item = 'aluminum',   price = 10 },
    { item = 'copper',     price = 15 },
    { item = 'plastic',    price = 4 },
    { item = 'rubber',     price = 5 },
    { item = 'glass',      price = 4 },
}
Config.Buy = {
    { item = 'screwdriverset', price = 350 },
    { item = 'repairkit',      price = 650 },
    { item = 'weapon_crowbar', price = 250 },
}
Config.MaxTradeAmount = 50

Config.InteractDistance = 2.5

Config.Upgrades = {
    { key = 'shelves',    price = 1500, slots = 10, weight = 100000 },
    { key = 'loft',       price = 3500, slots = 15, weight = 200000 },
    { key = 'industrial', price = 7000, slots = 25, weight = 400000 },
}

Config.Furniture = {
    { key = 'shelf_small', model = 'v_ret_ml_shelfrk', price = 900, slots = 15, weight = 80000,
      display = { shelves = { -0.79, -0.28, 0.23, 0.75 }, x = { -0.66, 0.66 }, y = { -0.19, 0.19 } } },
    { key = 'shelf_large', model = 'prop_ff_shelves_01', price = 1800, slots = 30, weight = 160000,
      display = { shelves = { 0.24, 0.81, 1.30, 1.79, 2.23 }, x = { -1.13, 1.13 }, y = { -0.33, 0.37 } } },
    { key = 'shelf_ind', model = 'v_ind_cf_shelf', price = 2400, slots = 40, weight = 250000,
      display = { shelves = { 0.09, 0.73, 1.31, 1.85 }, x = { -1.35, 1.35 }, y = { -0.36, 0.36 } } },
    { key = 'gunrack', model = 'prop_cs_gunrack', price = 3200, slots = 10, weight = 60000,
      display = { rack = { x = -0.565, step = 0.1255, n = 10, z = -0.304 } } },
    { key = 'locker', model = 'prop_cabinet_01', price = 1100, slots = 12, weight = 60000 },
    { key = 'cabinet', model = 'prop_rub_cabinet03', price = 1300, slots = 18, weight = 90000 },
    { key = 'toolchest', model = 'prop_toolchest_05', price = 1600, slots = 20, weight = 120000 },
    { key = 'fridge', model = 'prop_fridge_03', price = 1200, slots = 15, weight = 50000 },
    { key = 'crate', model = 'prop_box_wood05a', price = 700, slots = 15, weight = 120000 },
    { key = 'milcrate', model = 'prop_mil_crate_02', price = 1500, slots = 20, weight = 150000 },
    { key = 'guncrate', model = 'gr_prop_gr_crate_gun_01a', price = 2600, slots = 12, weight = 80000,
      display = { crate = { x = { -0.33, 0.33 }, y = { -0.66, 0.66 }, z = 0.335, layers = 2 } } },
    { key = 'safe', model = 'p_v_43_safe_s', price = 6500, slots = 20, weight = 100000 },
}
Config.Display = { perProp = 10, maxPerItem = 4, distance = 40.0 }
Config.FurnitureLimit = { small = 3, medium = 5, large = 8, container = 4 }
Config.FurnitureRefund = 0.5

Config.LooseItemsLimit = 30
Config.ItemProps = {
    cash = 'prop_cash_pile_01', money = 'prop_cash_pile_01', markedbills = 'prop_money_bag_01', black_money = 'prop_money_bag_01',
    goldbar = 'prop_gold_bar', gold = 'prop_gold_bar', rolex = 'prop_jewel_02a', diamond = 'prop_jewel_02a',
    weed_brick = 'hei_prop_heist_weed_block_01', coke_brick = 'prop_coke_block_01', meth = 'prop_meth_bag_01',
    lockpick = 'prop_cs_package_01', advancedlockpick = 'prop_tool_box_04', repairkit = 'prop_tool_box_04',
    screwdriverset = 'prop_tool_box_04', drill = 'prop_tool_drill', weapon_crowbar = 'prop_tool_wrench',
    phone = 'prop_phone_ing', tablet = 'prop_cs_tablet', laptop = 'prop_cs_tablet',
    bandage = 'prop_ld_health_pack', firstaid = 'prop_ld_health_pack', medikit = 'prop_med_bag_01b',
    jerrycan = 'prop_ld_jerrycan_01', car_battery = 'prop_car_battery_01',
    metalscrap = 'prop_ld_scrap', iron = 'prop_ld_scrap', steel = 'prop_ld_scrap', aluminum = 'prop_ld_scrap', copper = 'prop_ld_scrap',
}
Config.ItemPropPatterns = {
    { '^ammo', 'prop_ld_ammo_pack_01' }, { 'ammo$', 'prop_ld_ammo_pack_01' },
    { 'weed', 'bkr_prop_weed_bag_01a' }, { 'coke', 'hei_prop_hei_drug_pack_01a' }, { 'meth', 'prop_meth_bag_01' },
    { 'drug', 'prop_drug_package' }, { 'bag', 'prop_paper_bag_01' }, { 'burger', 'prop_cs_burger_01' },
    { 'sandwich', 'prop_food_bag1' }, { 'water', 'prop_cs_beer_bot_01' }, { 'beer', 'prop_cs_beer_bot_01' },
    { 'cola', 'prop_cs_beer_bot_01' }, { 'case', 'prop_ld_case_01' }, { 'part', 'prop_rub_carpart_02' },
}
Config.ItemPropFallback = 'prop_cs_cardbox_01'

Config.Sale = { hours = 48, startMultiplier = 4.0, floorMultiplier = 1.0 }

Config.AccessMinutes = 20

Config.Doors = {
    shutterTime = 3.5,
    doorTime = 1.2,
    containerTime = 3.0,
    hatchTime = 1.6,
    gateTime = 4.0,
    gateAuto = true,
    gateDetect = 6.0,
    gateCloseDelay = 3000,
    gateOpenAtStart = true,
    gateJobs = nil,
}

Config.Barriers = { enabled = true, detect = 7.0, speed = 75.0, closeDelay = 2500 }

Config.Zone = {
    margin = 30.0,
    exitMargin = 15.0,
    polygons = {},
}
