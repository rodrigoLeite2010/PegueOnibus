# Ajustes de layout, vagas e passageiros - 2026-09-11

Objetivo desta revisão: aproximar o fluxo do jogo da referência enviada, priorizando a mecânica antes do acabamento visual.

## O que mudou

- Todas as fases JSON agora usam 5 vagas de embarque limitadas.
- O gerador procedural também usa 5 vagas.
- A regra de falta de vaga continua centralizada no `GameEngine`; um sexto veículo não pode estacionar enquanto as 5 vagas estiverem ocupadas.
- Veículos param nos `Marker3D` reais das vagas e passam para uma escala de miniatura ao estacionar, para caber visualmente dentro do quadrado.
- O contador branco da vaga mostra `capacity - occupied_seats` e diminui a cada passageiro que entra.
- Passageiros deixaram de ser resumidos visualmente no topo da HUD. O `QueuePanel/QueueHolder` foi ocultado.
- Passageiros são pessoas 3D reais junto da área de embarque. Até 40 ficam visíveis ao mesmo tempo, organizados em uma grade compacta.
- 40 passageiros visíveis corresponde exatamente à maior capacidade oficial (ônibus).
- Em fases procedurais, as capacidades agora são:
  - small_car: 16
  - medium_car: 24
  - bus: 40
- O gerador cria exatamente `capacity` passageiros da cor de cada veículo, mantendo a ordem lógica da solução.
- A animação de embarque foi acelerada para evitar que um ônibus de 40 lugares demore mais de 10 segundos para completar.
- A HUD superior foi reduzida para devolver espaço ao tabuleiro/área 3D.
- A câmera passou a enquadrar uma área de passageiros mais profunda acima das vagas.

## Arquivos principais alterados

- scripts/game/game_controller.gd
- scripts/core/level_generator.gd
- scripts/core/vehicle_capacity_table.gd
- scripts/core/level_definition.gd
- scripts/game/vehicle_controller.gd
- scripts/game/passenger_controller.gd
- scripts/ui/hud_controller.gd
- scenes/ui/HUD.tscn
- levels/level_001.json ... level_005.json
- levels/level_900.json

## Teste recomendado

1. Rodar primeiro uma fase procedural alta (ex.: fase 15 ou 39) para conferir 16/24/40 passageiros.
2. Ocupar as 5 vagas e confirmar que o próximo veículo recebe feedback de falta de vaga.
3. Conferir se small/medium/bus cabem visualmente dentro dos slots.
4. Conferir o contador branco diminuindo até 0.
5. Conferir se a pessoa da cor correta caminha até a porta/BoardingPoint do veículo.
6. Se a grade de 40 pessoas ocupar espaço demais ou de menos, ajustar apenas `CROWD_COLUMN_SPACING` e `CROWD_ROW_SPACING` em game_controller.gd.
