Config = {}

-- ============================
-- PONTO DE INÍCIO (Valentine)
-- ============================
-- Ajuste as coordenadas para o local exato onde quer o ícone/marker em Valentine.
Config.StartPoint = {
    coords = vector3(-270.20, 669.85, 113.31),
    heading = 331.3,
    blip = {
        sprite = `BLIP_AMBIENT_HERD`, -- ícone de "trabalho/missão" - troque por outro nome da lista de blips do RDR3 se quiser
        scale = 0.9,
        label = "Transporte de Gado"
    }
}

-- ============================
-- PONTO DE ENTREGA (Rhodes)
-- ============================
-- Ajuste as coordenadas para o local exato de entrega em Rhodes.
Config.DeliveryPoint = {
    coords = vector3(-294.27, 630.91, 111.45),
    radius = 15.0,  -- raio (em metros) que conta como "chegou no destino"
    blip = {
        sprite = `blip_code_waypoint`, -- ícone de vagão/entrega - existe também BLIP_AMBIENT_HERD se preferir
        scale = 0.9,
        label = "Entregar Gado - Rhodes"
    }
}

-- ============================
-- GADO
-- ============================
-- Lista de candidatos a modelo de vaca. O script testa cada um em ordem
-- e usa o primeiro que for válido nesta build do jogo (imprime no console
-- qual foi escolhido, ou quais falharam, para diagnóstico).
Config.CowModelCandidates = {
    "a_c_cow", -- confirmado válido nesta build
}
Config.CowCount = 6
Config.SpawnRadius = 6.0 -- raio em que as 6 vacas nascem ao redor do ponto inicial (menor agora, já que a manada as mantém juntas)

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
    pushRange = 14.0,             -- distância da âncora até você em que a manada reage e anda
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
}

-- ============================
-- RECOMPENSA
-- ============================
-- currencyType segue o padrão do VORPCore: 0 = dinheiro, 1 = ouro
Config.Reward = {
    perCow = 5.00,
    currencyType = 0
}

-- Intervalo (ms) em que o script verifica se as vacas chegaram ao destino
Config.CheckInterval = 2000

-- Cooldown em minutos antes do mesmo jogador poder iniciar a missão de novo (0 = sem cooldown)
Config.MissionCooldown = 5