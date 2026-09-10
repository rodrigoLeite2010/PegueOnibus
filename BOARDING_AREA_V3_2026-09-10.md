# Boarding Area V3 — 2026-09-10

Correção do estacionamento visual dos veículos em espera.

- Adicionado `BoardingArea` ao mundo 3D da cena Game.
- Cada waiting slot lógico agora possui um `Marker3D` fixo (`Slot0`, `Slot1`, ...).
- O destino final da animação vem diretamente do Marker3D correspondente ao `slot_index` emitido pelo GameEngine.
- Os veículos passam por uma faixa comum antes de alinhar na vaga, evitando destinos aproximados e sobreposição visual.
- Cada vaga ganhou uma base 3D discreta para deixar visível onde o veículo deve estacionar.
- GameEngine e regras das fases não foram alterados.

Teste principal: Fase 5. Envie primeiro o laranja e depois o vermelho. Eles devem terminar em vagas diferentes e permanecer exatamente nelas enquanto aguardam a cor da fila.
