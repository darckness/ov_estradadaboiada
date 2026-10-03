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
    { name = "Valentine",   coords = vector3(-207.53, 614.79, 113.29),    npc = vector4(-207.53, 614.79, 113.29, 101.0) },
    { name = "Rhodes",      coords = vector3(1459.85, -1388.98, 78.96),      npc = vector4(1459.85, -1388.98, 78.96, 147.5) },
    { name = "Strawberry",  coords = vector3(-1793.48, -567.99, 155.99),  npc = vector4(-1793.48, -567.99, 155.99, 163.6) },
    { name = "Blackwater",  coords = vector3(-970.54, -1335.04, 51.22),   npc = vector4(-970.54, -1335.04, 51.22, 233.8) },
    { name = "Saint Denis", coords = vector3(2569.16, -737.38, 42.38),   npc = vector4(2569.16, -737.38, 42.38, 231.7) },
    { name = "Annesburg",   coords = vector3(2988.10, 1442.60, 45.54),    npc = vector4(2988.10, 1442.60, 45.54, 324.2) },
    { name = "Armadillo",   coords = vector3(-3698.67, -2530.29, -13.99), npc = vector4(-3698.67, -2530.29, -13.99, 119.7) },
    { name = "Tumbleweed",  coords = vector3(-5525.29, -3030.45, -2.09),  npc = vector4(-5525.29, -3030.45, -2.09, 283.1) },
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

    -- DUAS MARCHAS (todas as vacas sempre na MESMA velocidade - gado treinado):
    -- [Q] alterna entre a 1 (caminhando) e a 2 (trotando); a marcha fica até apertar de novo.
    -- speed = velocidade das vacas | lead = quanto a âncora fica À FRENTE do centro delas (m)
    gearKey = 'q',
    gears = {
        { label = "Marcha 1: caminhando", speed = 1.0, lead = 3.0 },
        { label = "Marcha 2: trotando",   speed = 2.0, lead = 4.5 },
    },


    -- Rumo da manada: ela vira pro lado OPOSTO de quem toca. Quanto mais pra
    -- frente (na lateral) a pessoa estiver, mais brusca a curva (graus por passo).
    turnRear  = 6.0,    -- tocando por TRÁS (até 60° pra cada lado do rabo da manada)
    turnSide  = 30.0,   -- tocando pela LATERAL
    turnFront = 50.0,   -- pela FRENTE: a manada refuga e vira pra trás
    rearCone  = -0.5,   -- (cosseno) até onde conta como "atrás"  (-0.5 = 60° pra cada lado)
    frontCone = 0.35,   -- (cosseno) a partir de onde conta como "frente" (~70°)

    -- Trava de segurança: vaca muito longe da âncora recebe ordem reforçada
    leashCheckInterval = 1500,
    leashDistance = 8.0,
}

Config.CheckInterval = 2000 -- ms entre verificações de chegada

-- DEBUG no jogo: círculo VERDE = área da manada | pontos + círculo AZUL = rumo
-- e o próximo ponto aonde ela vai | texto = de onde está sendo tocada.
-- Liga/desliga no jogo com /boiada_debug
Config.HerdDebug = {
    enabled = true,
    herdRadius = 5.0,   -- raio do círculo verde
    lookAhead = 7.0,    -- distância do círculo azul (à frente, no rumo)
}
