Config = {}

-- ============================
-- PONTO DE INÍCIO (Valentine)
-- ============================
-- Ajuste as coordenadas para o local exato onde quer o ícone/marker em Valentine.
Config.StartPoint = {
    coords = vector3(-270.20, 669.85, 113.31),
    heading = 331.3,
    blip = {
        sprite = `BLIP_AMBIENT_HERD`, -- ícone de manada - troque por outro nome da lista de blips do RDR3 se quiser
        scale = 0.9,
        label = "Transporte de Gado"
    }
}

-- ============================
-- DESTINOS DE ENTREGA
-- ============================
-- Cada destino tem suas próprias coordenadas e preço por vaca (cidades
-- mais longe de Valentine pagam mais). Ajuste as coordenadas de cada uma
-- indo até o local no jogo e usando /mycoords (veja o README).
-- O "key" de cada destino (ex: "rhodes") é usado internamente - pode
-- adicionar quantos destinos quiser, seguindo o mesmo formato.
Config.Destinations = {
    rhodes = {
        name = "Rhodes",
        coords = vector3(1274.0, -1308.0, 77.0),
        radius = 15.0,       -- raio (em metros) que conta como "chegou no destino"
        pricePerCow = 5.00,  -- mais perto de Valentine = paga menos
        blip = {
            sprite = `blip_code_waypoint`,
            scale = 0.9,
        }
    },
    blackwater = {
        name = "Blackwater",
        coords = vector3(-1848.0, -450.0, 42.0), -- AJUSTE com /mycoords
        radius = 15.0,
        pricePerCow = 8.50,  -- mais longe = paga mais
        blip = {
            sprite = `blip_code_waypoint`,
            scale = 0.9,
        }
    },
    saint_denis = {
        name = "Saint Denis",
        coords = vector3(2650.0, -1240.0, 50.0), -- AJUSTE com /mycoords
        radius = 15.0,
        pricePerCow = 12.00, -- o mais longe, paga o melhor
        blip = {
            sprite = `blip_code_waypoint`,
            scale = 0.9,
        }
    },
}

-- Quantidade de gado selecionável no menu (lista de opções fixas, de
-- CowCountMin até CowCountMax, pulando de CowCountStep em CowCountStep)
Config.CowCountMin = 2
Config.CowCountMax = 12
Config.CowCountStep = 2

-- ============================
-- GADO
-- ============================
-- Lista de candidatos a modelo de vaca. O script testa cada um em ordem
-- e usa o primeiro que for válido nesta build do jogo (imprime no console
-- qual foi escolhido, ou quais falharam, para diagnóstico).
Config.CowModelCandidates = {
    "a_c_cow", -- confirmado válido nesta build
}
Config.SpawnRadius = 6.0 -- raio em que as vacas nascem ao redor do ponto inicial (a manada as mantém juntas depois)

-- ============================
-- COMPORTAMENTO DE MANADA
-- ============================
-- Faz as vacas ficarem perto umas das outras e reagirem quando o
-- jogador se aproxima (efeito de "tocar" o gado pra frente).
-- Modelo "ponto-âncora": a manada é tratada como UM bloco só. Existe um
-- ponto invisível (a "âncora") que anda pelo mapa quando você (a cavalo)
-- se aproxima por trás. Cada vaca tem uma posição FIXA (sorteada uma
-- única vez, no início) relativa a essa âncora, e todas são sempre
-- mandadas pra lá na MESMA velocidade. Isso garante grupo compacto,
-- mesma direção e mesmo ritmo pra todas, sem decisões individuais.
Config.Herd = {
    checkInterval = 500,          -- ms entre atualizações (constante = movimento sempre no mesmo ritmo)
    pushRange = 24.0,             -- distância da âncora até você em que a manada reage e anda
    formationRadius = 2.0,        -- raio em que a posição fixa de cada vaca na formação é sorteada (só uma vez)

    -- Padrão: enquanto você só está perto, a manada anda CALMA (sem
    -- "susto"), só respondendo à sua proximidade.
    walkSpeed = 1.0,              -- velocidade calma padrão
    walkStepDistance = 2.0,       -- quanto a âncora avança por atualização, andando calma

    -- Disparada: aperte a tecla pra manada correr por alguns segundos
    -- (efeito de assustar o gado de propósito).
    sprintKey = 'h',
    sprintRange = 18.0,           -- distância máxima até a âncora pra o comando funcionar
    sprintSpeed = 3.0,            -- velocidade durante a disparada
    sprintStepDistance = 4.5,     -- quanto a âncora avança por atualização, durante a disparada
    sprintDuration = 3000,        -- ms que a disparada dura após apertar a tecla

    -- Trava de segurança (extra, não interfere no comportamento normal):
    -- fica de olho em vacas que ficaram longe demais da âncora (presas
    -- em obstáculo, engasgo de rede, etc.) e reforça o comando de volta
    -- com mais urgência (nunca teleporta).
    leashCheckInterval = 1500,    -- ms entre checagens de segurança
    leashDistance = 8.0,          -- se ficar mais longe que isso da âncora, reforça o comando de volta
}

-- ============================
-- RECOMPENSA
-- ============================
-- O valor por vaca é definido em cada destino (Config.Destinations).
-- Aqui só fica o tipo de moeda: 0 = dinheiro, 1 = ouro (padrão VORPCore)
Config.Reward = {
    currencyType = 0
}

-- Intervalo (ms) em que o script verifica se as vacas chegaram ao destino
Config.CheckInterval = 2000

-- Cooldown em minutos antes do mesmo jogador poder iniciar a missão de novo (0 = sem cooldown)
Config.MissionCooldown = 5