Config = {}

Config.PizzaStart = vector3(290.3, -962.29, 29.02) -- Start NPC / job start location
Config.PizzaPed = 'u_m_y_burgerdrug_01' -- Start NPC model
Config.PizzaVehicle = 'faggio2' -- Delivery vehicle model

-- Delivery NPC model and locations
Config.DeliveryPed = 'a_m_m_business_01' -- Delivery customer ped model (change if desired)
Config.DeliveryLocations = {
    vector3(452.12, -662.19, 28.49),
    vector3(1150.95, -793.46, 57.60),
    vector3(-1487.21, -380.03, 40.16),
    vector3(-1227.12, -908.35, 12.33)
}

-- Fixed base payment per delivery
Config.Payment = 100

-- Customer behavior configuration (percent chances)
Config.RefuseChance = 10
Config.TipChance = 20
Config.TipMin = 10
Config.TipMax = 50

-- Start-NPC cooldown to avoid instant spam (seconds)
Config.StartCooldown = 30

-- Voice / speech options used by PlayPedAmbientSpeechNative on the delivery ped
Config.TipPhrases = { "GENERIC_THANKS", "THANKS" }
Config.RefusePhrases = { "GENERIC_NO", "GET_LOST" }
Config.SuccessPhrases = { "GENERIC_HI", "HELLO" }

-- Logging & DB options
Config.UseDatabase = true
Config.DatabaseTable = "qb_pizzajob_deliveries"

-- Admin permission config
-- Primary: ACE permission name (server owners: assign ACE to groups accordingly)
-- Example: Config.AdminPermission = "admin"
Config.AdminPermission = "admin"
-- Fallback: keep Config.AdminCitizenIds for compatibility if you want to use citizenid whitelist
Config.AdminCitizenIds = {}

-- Default number of log entries to fetch for /pizzalogs when no limit provided
Config.LogFetchLimit = 50

Config.PizzaItem = 'pizza' -- item name that will be given/removed (must exist in qb-core / ox_inventory)