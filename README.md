# ov_estradadaboiada

Transporte de gado em grupo para RedM + VORPCore. Cada cidade tem um curral com capataz:
ele solta a manada e a comitiva conduz o gado a cavalo até o comprador.

## Dependências

`vorp_core`, `vorp_menu` (e OneSync, padrão no RedM).

## Como funciona

1. Fale com o **capataz** de qualquer curral (G): Valentine, Rhodes, Strawberry, Blackwater, Saint Denis, Annesburg, Armadillo ou Tumbleweed. Escolha o destino (mais longe
   paga mais por cabeça) e a quantidade de gado.
2. Quem estiver a até `Config.Group.radius` de você entra na **comitiva**.
   Cada vaqueiro extra aumenta o total em `bonusPerMember`, e o valor é
   dividido entre todos.
3. A manada anda como um bloco: chegue **por trás** dela para tocá-la.
   **[H]** faz o gado disparar por alguns segundos (qualquer membro pode).
4. Cada vaca tem um blip pequeno no mapa, para achar as desgarradas.
5. No destino:
   - se todas as vacas vivas estiverem no curral, a entrega é automática;
   - se só parte chegou, use o prompt **"Entregar o gado"** para receber
     pelas que estão no curral (as outras são perdidas).
6. O servidor confere a posição de cada vaca antes de pagar.

Falha: todas as vacas morrem, o prazo (`Config.TimeLimitMinutes`) acaba ou
o líder desconecta. Para desistir, fale de novo com o capataz → "Cancelar
transporte". As vacas são removidas em qualquer caso.

## Configuração (`config.lua`)

- `Config.Corrals`: um curral por cidade (centro do curral + posição do capataz). Serve de saída e de entrega.
- `Config.MinDistance` / `Config.MaxDistance`: só aparecem destinos entre 1 e 5 km do curral de saída.
- `Config.Price` e `Config.Time`: preço por cabeça e prazo calculados pela distância.
  Ajuste as coordenadas com **/mycoords**.
- `Config.Group`, `Config.MissionCooldown`, `Config.TimeLimitMinutes`.
- `Config.Herd`: velocidades e distâncias da manada.

## Comandos

- `/mycoords`: mostra sua posição e heading (para ajustar configs).
