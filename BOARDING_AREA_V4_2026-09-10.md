# Boarding Area V4 — 2026-09-10

Correção focada no defeito observado na Fase 5: o segundo veículo visual terminava atrás/sobre o primeiro embora o estado lógico indicasse Slot0 e Slot1.

## Correção
- `_boarding_slot_position()` agora converte explicitamente `Marker3D.global_position` para o espaço local de `$Vehicles` usando `vehicles_root.to_local(...)`.
- Todos os pontos entregues a `VehicleController.drive_route()` ficam no mesmo sistema de coordenadas de `vehicle_node.position`.
- Fallback da vaga também passa pela mesma conversão.
- GameEngine, fases e regras não foram alterados.

## Teste principal
Fase 5: enviar laranja e depois vermelho. O laranja deve terminar no Slot0 e o Alfa vermelho no Slot1, lado a lado, sem sobreposição.
