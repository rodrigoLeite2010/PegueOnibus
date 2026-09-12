# ENTREGA — Etapa 10A: Prova de Conceito do Novo Passageiro 3D

## 1. Arquitetura encontrada (Passo 1 — auditoria)

**Arquivo:** `scripts/game/passenger_controller.gd` (`class_name PassengerController extends Node3D`), instanciado a partir de `scenes/game/Passenger.tscn` (uma cena trivial: só o `Node3D` raiz com o script anexado, sem filhos pré-montados).

- **Função que cria o visual:** `_build()`, chamada por `_ready()` e por `setup(color_id, is_polish)`. Ela primeiro faz `for child in get_children(): child.free()` (limpa qualquer visual anterior) e recria tudo do zero.
- **Nós utilizados (visual antigo):** um `Node3D` chamado `BodyRoot` como contêiner, e dentro dele: `MeshInstance3D` com `BoxMesh` (torso, pernas, braços) e `SphereMesh` (cabeça, cabelo, olhos, mãos), mais dois `Node3D` (`LegPivot` × 2, `ArmPivot` × 2) usados só como pivôs de rotação para a passada de caminhada. Nenhum destes nós vem de uma cena — tudo é `.new()` em código.
- **Como a cor lógica é aplicada:** `COLOR_MAP` (`Dictionary[String, Color]`) mapeia `color_id` (ex. `"red"`, `"blue"`) para uma `Color`; cada mesh recebe um `StandardMaterial3D` próprio via `material_override` (`_material(color, roughness)`), derivado de `shirt_color = COLOR_MAP[color_id]` (mais variações: pele, cabelo, sapato, tons escurecidos/claros).
- **Como o visual é movimentado durante embarque:** `step_to(target)` (fila reorganizando) e `walk_to_and_board()`/`walk_to_and_board_polished()` (embarque completo) usam `Tween` para animar `position`/`scale`/`rotation.y` do **próprio nó raiz** (`self`, o `PassengerController`/`Node3D`) — nunca mexem em `BodyRoot` diretamente para o deslocamento. `BodyRoot` só é animado para: o *idle bounce* (`position:y` subindo/descendo), o ciclo de caminhada (`LegPivot`/`ArmPivot` girando) e o "pop" de reação de cor (`polish_color_react()`, escala de `BodyRoot`). Essa separação é exatamente o que tornou possível trocar só o CONTEÚDO de `BodyRoot` sem tocar em nenhuma dessas animações.
- **Como o visual é destruído/removido:** ao final de `walk_to_and_board()`/`walk_to_and_board_polished()`, o próprio `PassengerController` chama `queue_free()` (a animação de embarque termina com o boneco encolhendo a zero e sumindo). Quando a fila visual é resincronizada (`PassengerCrowdController.rebuild_dolls()`/`sync_to_state()`), boneco "extra" é removido com `doll.free()` (imediato, não `queue_free()`).

**Arquivo:** `scripts/game/passenger_crowd_controller.gd` (`class_name PassengerCrowdController`) — não desenha nada, só decide POSIÇÃO (grade/zigue-zague, `queue_slot_position()`) e ciclo de vida (`_spawn_doll`, `_spawn_doll_walking_in`, `pop_front_doll`, `rebuild_dolls`, `sync_to_state`), sempre via `preload("res://scenes/game/Passenger.tscn").instantiate()` seguido de `doll.setup(color_id, polish_mode)`.

Conclusão da auditoria: a representação visual está isolada dentro de `BodyRoot`; a lógica de movimento/cor/ciclo-de-vida nunca soube o que havia dentro dele. Isso permitiu trocar o CONTEÚDO de `BodyRoot` (primitivas → GLB) sem tocar em `step_to`, `walk_to_and_board*`, `pop_in`, `polish_color_react`, no idle, ou em qualquer parte do `PassengerCrowdController`/`GameController`/`GameEngine`/`GameState`.

## 2. Arquivos alterados

Novos:
- `scenes/passengers/Passenger3D.tscn` — cena wrapper (Passo 2): `Passenger3D (Node3D)` → `VisualRoot (Node3D)` → instância de `passenger_01.glb`. Nenhum outro arquivo do projeto referencia o `.glb` diretamente.
- `scripts/game/passenger_3d.gd` — script do wrapper: expõe `get_visual_root()`, `get_skeleton()`, `get_animation_player()` (buscas recursivas) para uso futuro (trocar personagem, achar rig/animação se um modelo futuro tiver).
- `tests/etapa10a/` — ferramentas de auditoria/QA desta etapa (scripts de inspeção do GLB, bancada de performance, screenshots). Não fazem parte do jogo.

Modificados (mudança mínima, cirúrgica):
- `scripts/game/passenger_controller.gd`: novo campo `use_glb_visual`, `setup()` ganha 3º parâmetro opcional, `_build()` passou a limpar `_leg_pivots`/`_arm_pivots` e então ramificar para `_build_procedural_visual()` (código antigo, byte-a-byte igual, só movido para dentro de uma função) ou `_build_glb_visual()` (nova, só instancia `Passenger3D.tscn` dentro de `BodyRoot`). Nenhuma outra função foi tocada.
- `scripts/game/passenger_crowd_controller.gd`: `setup()` ganha parâmetro `use_glb_visual` (padrão `false`), repassado nos 3 pontos de spawn (`_spawn_doll`, `_spawn_doll_walking_in`, `pop_front_doll`).
- `scripts/game/game_controller.gd`: novo `enum PassengerVisualMode { PROCEDURAL, GLB_3D }`, nova const `FORCE_GLB_PASSENGER_VISUAL_DEBUG := false` (mesmo padrão já usado por `FORCE_CLASSIC_DEBUG`), novo resolver `_resolve_passenger_visual_mode()`, chamado em `_load_level_number()` e repassado a `_passenger_crowd.setup(...)`.

**Não alterados** (confirmado por `git diff --stat` vazio): `scripts/core/game_engine.gd`, `scripts/core/game_state.gd`, `scripts/core/level_generator.gd`, os 5 níveis JSON + `level_900.json`/`level_950.json`. `scenes/game/PolishTest.tscn` também não foi tocado por mim — o diff nele já existia no início desta etapa (o próprio teste manual do usuário, um `passenger_01.glb` solto na cena) e permanece idêntico, byte a byte, ao estado em que a etapa começou.

## 3. A flag central (Passo 9)

`GameController.FORCE_GLB_PASSENGER_VISUAL_DEBUG` (const, hoje `false`) é a fonte única: `_resolve_passenger_visual_mode()` só retorna `GLB_3D` quando ela está ligada; fora disso, **toda fase — incluindo a 950 — continua exatamente no boneco procedural de sempre**. Ligar essa única constante e reabrir o projeto liga o GLB em qualquer fase testada (comparação A/B instantânea); desligar de volta é rollback instantâneo. Por que o padrão ficou desligado mesmo na fase 950: ver seção 6 (performance).

## 4. Escala e rotação finais (Passos 4 e 5)

**Escala: 1.0 (sem ajuste).** **Rotação: identidade / 0° (sem ajuste).** `VisualRoot` foi deixado exatamente como veio — nenhuma correção foi necessária. Isso foi confirmado visualmente (não só presumido): renderizei o wrapper sozinho, de frente, com uma câmera dedicada (ver screenshot enviado) e o personagem aparece em pé, de frente, pés no chão, sem nenhuma rotação estranha herdada da exportação do Tripo. Isso é consistente com o teste manual que o usuário já tinha feito (GLB solto na cena, Scale (1,1,1), "aparece corretamente"). `VisualRoot` já está pronto para receber uma correção futura caso um PRÓXIMO modelo venha exportado com outro eixo frontal — só não foi preciso para este.

## 5. Auditoria técnica do GLB (Passos 7 e 8)

Inspecionei o `.glb` importado carregando-o direto via `load()` no Godot (não é estimativa, é a malha real pós-import):

| Item | Valor |
|---|---|
| Triângulos | **1.962.848** (1 único surface, 1.164.344 vértices) |
| Meshes | 1 (`MeshInstance3D` único, malha inteira sem separação por parte do corpo) |
| Materiais | 1 (`StandardMaterial3D`) |
| Texturas | 3, todas 1024×1024 JPEG: albedo/basecolor (362 KB), normal (141 KB), metallic+roughness (216 KB) — todas efetivamente ligadas ao material (`albedo_texture`, `normal_texture`, `metallic_texture`/`roughness_texture`) |
| `Skeleton3D` | **Não existe** |
| `AnimationPlayer` | **Não existe** (`get_animation_list()` não aplicável — o nó nem existe na árvore) |
| Cast shadow | Ligado (padrão do `MeshInstance3D`) |
| AABB local | altura (Y) 0,98 m · largura (X) 0,50 m · profundidade (Z) 0,34 m · pés já em Y=0 |
| Tamanho em disco | 61,5 MB (o `.glb`) + ~0,7 MB de texturas |

**1,96 milhão de triângulos para um único personagem de fundo é 100–1000× um orçamento típico para esse tipo de personagem em mobile** (a referência usual para "crowd"/NPC secundário é algo entre 500 e 15.000 triângulos). Isso é claramente resultado de uma geração por IA 3D sem retopologia/otimização — a malha provavelmente veio direto do scan/geração sem nenhuma etapa de redução (decimation), exatamente o risco que o pedido antecipava.

Sem `Skeleton3D`/`AnimationPlayer`, não há o que auditar do Passo 8 além de confirmar a ausência: nenhuma tentativa foi feita de criar animação artificialmente (conforme instruído). O `PassengerController` continua movimentando o `Node3D` inteiro via `Tween` (posição/escala/rotação), exatamente como fazia antes — a ausência de rig não quebra nada porque o sistema de movimento nunca dependeu de um esqueleto.

## 6. Performance (Passo 7) — por que o GLB fica desligado por padrão

Este container não tem GPU real; os números abaixo vêm de renderização **de verdade** (não o modo `--headless` puramente dummy, que não desenha nada) via um rasterizador por software (Mesa llvmpipe, rodando em CPU) sob Xvfb — ou seja, são reais no sentido de que passam pelo pipeline de renderização completo, mas **não equivalem a uma GPU de celular real**: uma GPU móvel real processa triângulos em paralelo, com muito mais throughput por watt do que uma CPU fazendo rasterização por software. Trato os números abaixo como um sinal direcional forte, não como o FPS real esperado num aparelho.

| Instâncias simultâneas | FPS médio | FPS mín/máx |
|---|---|---|
| 1 | 10,8 | 1 / 25 |
| 10 | 10,6 | 4 / 18 |
| 30 | 7,6 | 1 / 9 |
| 60 | 6,8 | 1 / 8 |

Mesmo com **1 única instância parada em quadro estático**, o software rasterizer já cai para a casa de 10 fps — o gargalo é claramente o 1,96M de triângulos por personagem, não a lógica do jogo. `PassengerCrowdController.MAX_VISIBLE_QUEUE_DOLLS = 40` é o teto real de instâncias simultâneas na fase 950 (não "centenas ao mesmo tempo" — o total de passageiros da fase, 576, é cumulativo ao longo do tempo; no máximo 40 ficam visíveis de uma vez), e mesmo assim a tendência de queda entre 30 e 60 instâncias é clara e monotônica.

Por isso, seguindo a instrução explícita do pedido ("se estiver pesado, não instanciar centenas imediatamente... se excessivamente pesado, parar e reportar os números antes de tentar otimizações destrutivas"), **não reduzi a qualidade da malha nem tentei otimização alguma** — apenas deixei `FORCE_GLB_PASSENGER_VISUAL_DEBUG = false` por padrão, mesmo na fase 950, para não arriscar entregar algo que possa não rodar aceitavelmente em hardware móvel real sem que o usuário veja os números primeiro. A flag está pronta para o usuário ligar e testar em hardware real (desktop ou device) e decidir se/quando ativar por padrão.

## 7. Validação (Passo 10) — feita com a flag LIGADA temporariamente

Para provar que o mecanismo funciona de ponta a ponta (não só em teoria), rodei a fase 950 de verdade — não uma simulação isolada — com `FORCE_GLB_PASSENGER_VISUAL_DEBUG` temporariamente `true`, sob o mesmo Xvfb+llvmpipe, e tirei screenshots reais em 540×960 (enviados nesta entrega):

1. **Personagem aparece corretamente** ✅ (screenshot "start": fila inteira com o novo modelo, camiseta amarela, bem legível mesmo em miniatura).
2. **Pés no chão** ✅ (AABB confirma Y=0 nos pés; visualmente o personagem está apoiado, sem flutuar/afundar).
3. **Escala adequada** ✅ (cabeça legível, sem sobreposição visível entre vizinhos na grade real do jogo).
4. **Crowd mantém posições** ✅ (grade/zigue-zague igual à versão procedural — `queue_slot_position()` não foi tocado).
5. **Passageiros continuam reorganizando** ✅ (screenshot "end": fila visivelmente menor após embarques, sem buracos/sobreposição).
6. **Passageiros continuam indo aos veículos** ✅ (3 veículos tocados via `_process_vehicle_tap` real, todos processaram embarque).
7. **Embarque continua funcionando** ✅ (mensagem "Passageiros embarcaram." + contadores nos veículos, ex. "11", "27").
8. **Contadores continuam corretos** ✅ (`queue_restante` foi de 576 → 526 após 3 toques, consistente com as capacidades dos veículos tocados).
9. **Vitória continua possível** — não joguei a fase inteira até vencer dentro desta sessão (cada leva de embarque em cascata tem animações reais em segundos, e a fase tem 26 veículos/576 passageiros; um clear completo automatizado estourou o tempo disponível da ferramenta). Isso NÃO é uma lacuna de solvabilidade: a lógica de vitória vem 100% do `GameEngine`/`GameState`, que esta etapa não tocou em nenhuma linha, e a solvabilidade do conteúdo de `level_950.json` já foi auditada e comprovada em etapas anteriores (9B/9C). O que eu confirmei diretamente é que a CAMADA VISUAL nova não interfere no fluxo de eventos que leva à vitória.
10. **Nenhum erro novo no debugger** ✅ — a única mensagem de erro observada nas rodadas de teste foi um aviso pré-existente e não relacionado (UID inválido do `PolishTest.tscn` do próprio teste manual do usuário) e avisos de áudio/vsync do ambiente Linux sem placa de som/GPU real, nada relativo ao código desta etapa.

Depois da validação, `FORCE_GLB_PASSENGER_VISUAL_DEBUG` foi devolvido a `false` e `scripts/game/polish_test_launcher.gd` (temporariamente instrumentado para rodar o teste automatizado) foi restaurado byte-a-byte ao original (`diff` vazio confirmado).

## 8. Riscos encontrados

- **Peso da malha (alto):** 1,96M triângulos/instância, sem LOD, sem rig — ver seção 6. Risco principal desta etapa.
- **Tamanho do arquivo:** 61,5 MB só o `.glb` — impacta tempo de build/download do app se usado em mais fases sem otimização.
- **Sem variação:** um único personagem para todos os passageiros (esperado nesta etapa — Passo 6 pediu explicitamente para não recolorir ainda; por coincidência o GLB já vem com camiseta amarela, então "todos amarelos" já é o resultado visual atual sem nenhum código extra).
- **Sem animação:** movimentos de perna/braço da caminhada (`_start_walk_cycle`) não têm efeito nenhum no modelo GLB (sem Skeleton3D) — o personagem desliza rígido pela cena. Não tentei mascarar isso (instrução explícita do Passo 8); fica para uma etapa de rig/animação futura.
- **`scenes/game/PolishTest.tscn` tem um nó solto** (`passenger_01` instanciado direto na raiz da cena, fora do fluxo do jogo) — é o teste manual do próprio usuário, pré-existente a esta etapa; não foi removido nem alterado, só sinalizado aqui para o usuário saber que continua lá.

## 9. Encerramento

Conforme instruído, a Etapa 10A termina aqui: nenhuma variedade de personagens, nenhum masculino/feminino, nenhuma troca de roupa, e a Etapa 10B não foi iniciada.
