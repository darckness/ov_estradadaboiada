# ov_cattletransport

Missão de transporte de gado para RedM com **VORPCore**: pegue 6 vacas em
Valentine e conduza a manada até Rhodes, a cavalo, para receber uma
recompensa em dinheiro.

## Dependências

- `vorp_core` (usa `exports.vorp_core:GetCore()` — nenhum `shared_script` extra é necessário)

## Instalação

1. Copie a pasta `ov_cattletransport` para dentro de `resources/[VORP]/` (ou
   onde ficam seus outros resources VORP).
2. Adicione `ensure ov_cattletransport` no `server.cfg`, **depois** de
   `ensure vorp_core`.
3. Ajuste as coordenadas em `config.lua` (veja [Configuração](#configuração)).
4. Reinicie o resource (ou o servidor inteiro, na primeira vez).

## Como funciona

1. Um blip fixo aparece em Valentine. Perto dele, um marker no chão indica
   o ponto de início.
2. Ao chegar perto (menos de 2m) e apertar **G**, o servidor libera a
   missão (respeitando cooldown e uma missão por vez).
3. 6 vacas nascem espalhadas ao redor do ponto, com a altura do chão
   ajustada automaticamente pra não nascerem enterradas/flutuando.
4. A manada é tratada como **um bloco só**: existe um ponto-âncora
   invisível que representa o grupo, e cada vaca ocupa uma posição fixa
   (sorteada uma vez, no início) relativa a essa âncora. Isso mantém o
   grupo compacto, na mesma direção e no mesmo ritmo — sem depender de
   decisões individuais de cada vaca.
5. **Guiando a manada (a cavalo):**
   - Chegando perto por trás da âncora (dentro do `pushRange`), a manada
     anda **calma** na direção oposta a você — recalculada continuamente,
     então se você vier mais de um lado, ela desvia pro outro.
   - Apertando **H**, a manada **dispara** (corre) por alguns segundos,
     mesmo sem você tão perto.
6. Um blip com rota indica o ponto de entrega em Rhodes.
7. Quando todas as vacas vivas chegam ao raio de entrega, a missão é
   concluída: as vacas somem, o blip de entrega é removido, e o jogador
   recebe `Config.Reward.perCow` por vaca entregue, em **dinheiro**
   (`currencyType = 0` no VORPCore).
8. Se todas as vacas morrerem no caminho, a missão é cancelada
   automaticamente (com cooldown, igual a uma entrega/cancelamento normal).

## Configuração

Tudo fica em `config.lua`, comentado. Os blocos principais:

- **`Config.StartPoint`** / **`Config.DeliveryPoint`** — coordenadas,
  raio de entrega e ícone do blip de cada ponto.
- **`Config.CowModelCandidates`** — lista de nomes de modelo de vaca a
  testar em ordem (o primeiro válido nesta build é usado). Hoje só tem
  `a_c_cow`, confirmado como funcional.
- **`Config.CowCount`** / **`Config.SpawnRadius`** — quantas vacas e o
  raio de spawn ao redor do ponto de início.
- **`Config.Herd`** — todo o comportamento de manada:
  - `pushRange`, `walkSpeed`, `walkStepDistance` — andar calmo por
    proximidade (padrão).
  - `sprintKey`, `sprintRange`, `sprintSpeed`, `sprintStepDistance`,
    `sprintDuration` — a disparada (tecla H).
  - `checkInterval` — frequência de atualização do movimento.
  - `formationRadius` — o quão espalhada é a formação fixa das vacas.
- **`Config.Reward`** — valor pago por vaca e se é dinheiro ou ouro.
- **`Config.CheckInterval`** — frequência de checagem de entrega.
- **`Config.MissionCooldown`** — cooldown (minutos) entre missões, por jogador.

## Comandos úteis (debug)

- **`/mycoords`** — imprime sua posição atual (`vector3(x, y, z)` +
  heading) no chat e no console. Use pra achar as coordenadas certas de
  `Config.StartPoint` e `Config.DeliveryPoint` andando até o local
  desejado no jogo.
- **`/blipsprite <nome>`** — troca em tempo real o ícone do blip de
  início, pelo nome (ex: `/blipsprite BLIP_AMBIENT_HERD`). Útil pra
  testar ícones antes de fixar um no `config.lua`. Pode remover esse
  comando do `client.lua` depois de escolher.

## Observações sobre esta build do RedM

Durante o desenvolvimento, notamos que **vários natives com nome
"amigável" (alias GTA5) não existem nesta build específica do
FXServer/RedM**, exigindo alternativas:

- `AddBlipForCoord` → usar `BlipAddForCoords(styleHash, x, y, z)`.
- `SetBlipSprite` → precisa de 3 parâmetros: `SetBlipSprite(blip, iconHash, true)`,
  com o ícone como **hash de nome** (ex: `` `BLIP_JOB` ``), não número.
- Trio `BeginTextCommandSetBlipName` / `AddTextComponentString` /
  `EndTextCommandSetBlipName` → substituído por `SetBlipName(blip, texto)`.
- `SetBlipColour`, `BeginTextCommandDisplayHelp` → indisponíveis; o
  código ignora essas chamadas silenciosamente (via `pcall`) e usa o
  chat como alternativa para avisos/textos de ajuda.
- `TaskGoStraightToCoord` anda em linha reta e não desvia de obstáculos;
  o código usa `TaskGoToCoordAnyMeans` (com pathfinding) para o
  movimento da manada.

O código já foi escrito de forma defensiva (com `pcall` e fallbacks) pra
lidar com isso, mas se migrar para um artifact/build mais novo do
FXServer, vale testar se os natives "padrão" passam a funcionar direto —
não deve quebrar nada de qualquer forma.

## Estrutura de arquivos

```
ov_cattletransport/
├── fxmanifest.lua
├── config.lua
├── client.lua
├── server.lua
└── README.md
```