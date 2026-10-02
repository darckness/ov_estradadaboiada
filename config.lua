Config = {}

-- =========================================================
-- CURRAIS (um por cidade)
-- =========================================================
-- Cada curral tem um capataz. Nele você PEGA gado para levar a outra
-- cidade, e ele também é o curral de ENTREGA de quem vem de fora.
--   coords: centro do curral (onde as vacas nascem e onde se entrega)
--   npc:    posição do capataz (x, y, z, heading)
-- Os currais novos ficam ao lado do açougue de cada cidade (coordenadas
-- do vorp_hunting). Se algum capataz ficar num lugar ruim, AJUSTE com
-- /mycoords e ponha a posição em coords e npc.
Config.Corrals = {
    { name = "Valentine",   coords = vector3(-270.20, 669.85, 113.31),    npc = vector4(-270.20, 669.85, 113.31, 331.3) },
    { name = "Rhodes",      coords = vector3(1274.0, -1308.0, 77.0),      npc = vector4(1274.0, -1308.0, 77.0, 0.0) },
    { name = "Strawberry",  coords = vector3(-1755.55, -396.48, 155.26),  npc = vector4(-1755.55, -396.48, 155.26, 181.4) },
    { name = "Blackwater",  coords = vector3(-749.85, -1287.40, 43.03),   npc = vector4(-749.85, -1287.40, 43.03, 273.6) },
    { name = "Saint Denis", coords = vector3(2817.94, -1326.77, 45.00),   npc = vector4(2817.94, -1326.77, 45.00, 51.8) },
    { name = "Annesburg",   coords = vector3(2931.57, 1304.85, 43.48),    npc = vector4(2931.57, 1304.85, 43.48, 70.6) },
    { name = "Armadillo",   coords = vector3(-3688.97, -2619.13, -14.75), npc = vector4(-3688.97, -2619.13, -14.75, 0.5) },
    { name = "Tumbleweed",  coords = vector3(-5507.37, -2950.64, -1.89),  npc = vector4(-5507.37, -2950.64, -1.89, 251.5) },
}
Config.CorralRadius = 15.0          -- raio do curral de entrega

Config.NpcModel = "A_M_M_ValFarmer_01"
Config.NpcSpawnDistance = 60.0

Config.Blip = {
    sprite = `BLIP_AMBIENT_HERD`,
    name = "Transporte de Gado",
}

Config.Prompt = {
    key = 0x760A9C6F,              -- [G]
    title = "Capataz da Boiada",
    text = "Falar com o capataz",
    distance = 2.5,
}

-- =========================================================
-- DESTINOS, PREÇO E PRAZO (calculados pela distância em linha reta)
-- =========================================================
-- Só aparecem destinos entre MinDistance e MaxDistance do curral de saída.
Config.MinDistance = 1000.0
Config.MaxDistance = 5000.0

-- preço por cabeça = base + porKm * km   (arredondado de 25 em 25 centavos)
-- Ex.: Valentine -> Rhodes (~2,3 km) = ~$6,75 por cabeça
Config.Price = { base = 1.00, perKm = 2.50 }

-- prazo em minutos = base + porKm * km
-- Ex.: Valentine -> Rhodes = ~38 min | 5 km = 65 min
Config.Time = { base = 15, perKm = 10 }

-- Quantidade de gado no menu (de Min até Max, pulando de Step em Step)
Config.CowCountMin = 2
Config.CowCountMax = 12
Config.CowCountStep = 2

-- Funções usadas pelo client e pelo server (mesmo cálculo nos dois)
function Config.Distance(fromIndex, toIndex)
    local a, b = Config.Corrals[fromIndex], Config.Corrals[toIndex]
    if not a or not b then return nil end
    return #(vector2(a.coords.x, a.coords.y) - vector2(b.coords.x, b.coords.y))
end

function Config.ValidRoute(fromIndex, toIndex)
    local d = fromIndex ~= toIndex and Config.Distance(fromIndex, toIndex)
    return d and d >= Config.MinDistance and d <= Config.MaxDistance or false
end

function Config.PricePerCow(fromIndex, toIndex)
    local km = (Config.Distance(fromIndex, toIndex) or 0) / 1000
    local price = Config.Price.base + Config.Price.perKm * km
    return math.floor(price * 4 + 0.5) / 4
end

function Config.TimeLimit(fromIndex, toIndex)
    local km = (Config.Distance(fromIndex, toIndex) or 0) / 1000
    return math.ceil(Config.Time.base + Config.Time.perKm * km)
end

-- =========================================================
-- GRUPO
-- =========================================================
Config.Group = {
    radius = 15.0,          -- quem estiver perto de quem iniciou entra no grupo
    maxMembers = 6,
    bonusPerMember = 0.25,  -- cada membro extra aumenta o total em 25% (dividido entre todos)
}
Config.MissionCooldown = 5     -- minutos entre um transporte e outro (por personagem)

-- =========================================================
-- GADO
-- =========================================================
Config.CowModel = "a_c_cow"
Config.SpawnRadius = 6.0      -- raio em que as vacas nascem em volta do curral
Config.CowBlips = true        -- blip pequeno em cada vaca (pra achar as desgarradas)

-- =========================================================
-- COMPORTAMENTO DE MANADA  (modelo "ponto-âncora")
-- =========================================================
-- A manada é um bloco só: um ponto invisível (âncora) anda quando alguém
-- do grupo chega perto por trás, e cada vaca vai para sua posição fixa
-- em volta da âncora, todas na mesma velocidade.
Config.Herd = {
    checkInterval = 500,
    pushRange = 24.0,             -- distância da âncora em que a manada reage e anda
    formationRadius = 2.0,

    walkSpeed = 1.0,
    walkStepDistance = 2.0,

    -- Disparada: aperte a tecla pra manada correr por alguns segundos
    sprintKey = 'h',
    sprintRange = 18.0,
    sprintSpeed = 3.0,
    sprintStepDistance = 4.5,
    sprintDuration = 3000,

    -- Trava de segurança: vaca muito longe da âncora recebe ordem reforçada
    leashCheckInterval = 1500,
    leashDistance = 8.0,
}

Config.CheckInterval = 2000 -- ms entre verificações de chegada
