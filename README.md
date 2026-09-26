# ov_cattletransport

Missão de transporte de gado para RedM com **VORPCore**: escolha o destino
e a quantidade de gado em um menu, pegue as vacas em Valentine e conduza a
manada até o destino escolhido, a cavalo, para receber uma recompensa em
dinheiro (o valor por cabeça varia conforme a distância do destino).

## Dependências

- `vorp_core` (usa `exports.vorp_core:GetCore()` — nenhum `shared_script` extra é necessário)
- `vorp_menu` (usa `exports.vorp_menu:GetMenuData()` para o menu de destino/quantidade)

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
2. Ao chegar perto (menos de 2m) e apertar **G**, abre um menu (vorp_menu)
   pra escolher o **destino** (cada um com preço por cabeça diferente,
   maior quanto mais longe de Valentine) e depois a **quantidade de gado**
   (entre `Config.CowCountMin` e `Config.CowCountMax`).
3. Confirmando o menu, o servidor libera a missão (respeitando cooldown e
   uma missão por vez) e as vacas escolhidas nascem espalhadas ao redor do
   ponto, com a altura do chão ajustada automaticamente pra não nascerem
   enterradas/flutuando.
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
6. Um blip com rota indica o ponto de entrega no destino escolhido.
7. Quando todas as vacas vivas chegam ao raio de entrega, a missão é
   concluída: as vacas somem, o blip de entrega é removido, e o jogador
   recebe `pricePerCow` (do destino escolhido) por vaca entregue, em
   **dinheiro** (`Config.Reward.currencyType = 0` no VORPCore).
8. Se todas as vacas morrerem no caminho, a missão é cancelada
   automaticamente (com cooldown, igual a uma entrega/cancelamento normal).

## Configuração

Tudo fica em `config.lua`, comentado. Os blocos principais:

- **`Config.StartPoint`** — coordenadas, heading e ícone do blip do ponto
  de início em Valentine.
- **`Config.Destinations`** — tabela com cada destino possível (chave
  interna, nome exibido, coordenadas, raio de entrega, preço por vaca e
  ícone do blip). Adicione quantos quiser seguindo o mesmo formato; o
  menu de destino é montado automaticamente a partir dessa lista, e a
  distância mostrada no menu é calculada sozinha (não precisa preencher).
- **`Config.CowCountMin`** / **`Config.CowCountMax`** / **`Config.CowCountDefault`**
  — limites e valor inicial do slider de quantidade de gado no menu.
- **`Config.CowModelCandidates`** — lista de nomes de modelo de vaca a
  testar em ordem (o primeiro válido nesta build é usado). Hoje só tem
  `a_c_cow`, confirmado como funcional.
- **`Config.SpawnRadius`** — raio de spawn ao redor do ponto de início.
- **`Config.Herd`** — todo o comportamento de manada:
  - `pushRange`, `walkSpeed`, `walkStepDistance` — andar calmo por
    proximidade (padrão).
  - `sprintKey`, `sprintRange`, `sprintSpeed`, `sprintStepDistance`,
    `sprintDuration` — a disparada (tecla H).
  - `checkInterval` — frequência de atualização do movimento.
  - `formationRadius` — o quão espalhada é a formação fixa das vacas.
- **`Config.Reward.currencyType`** — se o pagamento é em dinheiro (0) ou
  ouro (1) no VORPCore. O valor por vaca em si fica em cada destino
  (`Config.Destinations[...].pricePerCow`).
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