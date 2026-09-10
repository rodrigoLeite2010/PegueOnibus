# Boarding Area V5

Correção do estacionamento visual:

- O índice visual do slot agora vem do `GameState.waiting_slots`, que é a fonte definitiva da regra.
- O evento `VehicleParked` fica apenas como fallback.
- Ao terminar a rota, o veículo recebe um snap final usando `Marker3D.global_position`.
- Foi adicionado log `[BOARDING] vehicle -> slot` para diagnóstico no Output do Godot.
- Nenhuma regra do GameEngine ou conteúdo das fases foi alterado.

Teste recomendado: Fase 5, enviar laranja e depois vermelho. O Output deve mostrar slots diferentes (0 e 1).
