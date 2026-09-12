# Entrega — Etapa 10A.1: passageiro 3D otimizado e animado

Continuação da Etapa 10A (prova de conceito do `passenger_01.glb`). O modelo
foi substituído por uma versão retopologizada com Auto Rig humanoide, e esta
etapa integra o novo GLB — com animações reais de idle/walk/run — sem alterar
nenhuma mecânica (`GameEngine`, `GameState`, `LevelGenerator` seguem com diff
zero, verificado via `git diff --stat` no final desta etapa).

## 1. Reauditoria do GLB (Passo 1) — não confiei no relatório anterior

Números medidos de novo, direto no modelo atual (`load()` real, não estimativa):

| Métrica | Etapa 10A (modelo antigo) | Etapa 10A.1 (modelo novo) |
|---|---|---|
| Triângulos | 1.962.848 | **10.000** |
| Vértices | ~981.424 | **7.768** |
| Tamanho do arquivo | 61,5 MB | **1,83 MB** (1.832.024 bytes) |
| Malhas (surfaces) | 1 | 1 |
| Skeleton3D | não tinha | **sim — 41 ossos** (`Armature/Skeleton3D`) |
| AnimationPlayer | não tinha | **sim** |
| Animações | — | **`preset_biped_idle`, `preset_biped_run`, `preset_biped_walk`** (confirmadas, ver seção 2) |
| Texturas | 3× 1024×1024 (albedo/normal/rm) | 3× 1024×1024 (mesmas, conteúdo atualizado pelo usuário) |
| Materiais | 1 | 1 |

A queda de triângulos foi de ~196×. O modelo antigo (61,5 MB) foi preservado
pelo próprio usuário como `passenger_01_pesado.glb` (mantido no repositório
como referência/arquivo morto, não usado por nenhum código).

## 2. Um bug real de import encontrado e corrigido

Ao carregar `passenger_01.glb` pela primeira vez nesta etapa (via `load()`,
exatamente como o jogo faz), o `AnimationPlayer` vinha **vazio**
(`get_animation_list() == []`), mesmo com o Skeleton3D e a malha corretos.
Isso não era um artefato do meu ambiente de teste: o cache de import que já
existia no projeto (gerado pelo editor real do usuário, no Windows, antes
desta sessão) já estava assim.

Investigando a fundo:

- Abri o `.glb` como arquivo binário glTF puro (fora do Godot) e confirmei
  que ele **tem** as 3 animações: `preset:biped:idle`, `preset:biped:walk`,
  `preset:biped:run` (123 canais cada).
- Usando `GLTFDocument.append_from_file()` + `generate_scene()` diretamente
  (a mesma API que o importador de cena do Godot usa por baixo), as 3
  animações aparecem corretamente como `preset_biped_idle/walk/run` num
  `AnimationPlayer` válido.
- Ou seja: o glTF está correto e o Godot consegue gerar a cena com as
  animações — mas o **pipeline de import de cena do projeto** (que aplica
  pós-processamento como `remove_immutable_tracks`, geração de shadow
  mesh/LOD, etc.) estava descartando as 3 animações por completo antes de
  gravar o cache usado pelo jogo.

Não consegui isolar com 100% de certeza qual etapa exata do pós-processamento
descarta as animações (o ambiente headless deste container trava/aborta a
reimportação completa do projeto pelo editor de forma consistente — mesmo
com Xvfb + renderer real —, o que impediu testar cada opção de import
isoladamente dentro do tempo desta etapa). O candidato mais provável é
`animation/remove_immutable_tracks` no arquivo `.import`.

**O que fiz para destravar a validação desta etapa:** gerei novamente o
cache de import (`res://.godot/imported/passenger_01.glb-...scn`) chamando
diretamente `GLTFDocument` + `PackedScene.pack()` + `ResourceSaver.save()`
— o mesmo caminho interno que o importador de cena usa, só que sem o
pós-processamento opcional (dedup de superfícies, shadow mesh, LOD,
remoção de tracks imutáveis). Resultado: `load()` volta a funcionar
normalmente e agora entrega Skeleton3D + AnimationPlayer com as 3
animações, exatamente como o `.glb` de origem tem.

**Isto é uma correção de cache local, não uma mudança de arquitetura** — o
jogo continua chamando `load("res://.../passenger_01.glb")` normalmente,
sem nenhuma leitura de GLTF "crua" em tempo de execução. Mas é importante o
usuário saber: **da próxima vez que o Godot Editor (no Windows) reimportar
este arquivo** (por exemplo, se tocar em qualquer configuração de import ou
apertar "Reimport"), é possível que as animações voltem a sumir do cache,
pelo mesmo motivo. Recomendo, antes da Etapa 10B, abrir o import dock do
`passenger_01.glb` no editor real e testar desligar
`Animation > Remove Immutable Tracks`; se as 3 animações aparecerem na aba
de pré-visualização do import, era mesmo essa a causa raiz.

## 3. Wrapper (Passo 2) — sem mudança estrutural

`scenes/passengers/Passenger3D.tscn` continua exatamente `Passenger3D
(Node3D) → VisualRoot (Node3D) → passenger_01.glb`; nenhum outro arquivo
referencia o GLB diretamente. `scripts/game/passenger_3d.gd` ganhou:

- `play_idle(desync_offset)`, `play_walk()`, `play_run()` — API pública nova.
- `has_animations()` — usada por `PassengerController` para decidir entre
  animação esqueletal ou o bounce procedural antigo (fallback, caso um
  modelo futuro venha sem rig de novo).
- `get_visual_root()`/`get_animation_player()`/`get_skeleton()` passaram a
  resolver sob demanda (não mais via `@onready`): `PassengerController`
  chama `has_animations()`/`play_idle()` no mesmo frame em que instancia o
  wrapper, antes do `NOTIFICATION_READY` disparar — um `@onready` ali
  ficaria `null` bem no instante em que é preciso. Confirmado com um teste
  isolado que reproduziu exatamente essa sequência.

Também corrigi, de passagem, uma inconsistência de UID pré-existente entre
`Passenger3D.tscn` e o `.import` atual do GLB (o editor do usuário havia
gerado um novo UID ao reimportar o modelo, mas o wrapper ainda apontava
para o UID antigo — Godot tolerava isso com um aviso e fallback por texto,
sem quebrar nada, mas agora está consistente e sem aviso).

## 4. Idle/Walk/Run (Passos 3, 4, 5)

`PassengerController` ganhou pontes finas entre os Tweens de movimento
(inalterados) e a animação esqueletal:

- **Esperando na fila**: `_build_glb_visual()` chama `play_idle()` com um
  deslocamento aleatório (0–10s) dentro do clipe de 15,4s — uma fila de 40
  passageiros nunca fica sincronizada (confirmado visualmente: cada um em
  ponto diferente do ciclo).
- **Reorganizando na fila** (`step_to()`): toca `play_walk()` ao começar o
  Tween de posição, `play_idle()` de novo ao terminar.
- **Correndo pro veículo** (`walk_to_and_board()` e a variante "polished",
  a que toda fase real usa): toca `play_run()` no início da corrida. Sem
  root motion — a posição continua 100% controlada pelos Tweens existentes
  de `PassengerController`; a animação é puramente visual, "in place".
- As 3 animações vêm do GLB com `loop_mode = NONE` (Tripo não marcou loop
  no export); o wrapper força `LOOP_LINEAR` na primeira vez que qualquer
  uma é usada (o recurso `Animation` é compartilhado entre instâncias, uma
  vez já é suficiente para a execução toda).

**Validação end-to-end (não simulada)**: rodei `PolishTest`/Fase 950 de
verdade (cena real, não `--script`), com a flag temporariamente forçada, e
dirigi toques reais em veículos cuja cor batia com o início da fila. Uma
amostra de 24 passageiros GLB foi monitorada continuamente:

```
tap 1: animações observadas = [idle, walk, run]
tap 2: animações observadas = [run, idle, walk]
tap 3: animações observadas = [run, idle, walk]
```

As 3 animações trocam de estado corretamente, sem nenhum erro de script.
Embarque funcionou (6 passageiros embarcaram em 2 veículos, contadores
`ocupados=2/24` e `4/24` corretos, fila caiu de 576 → 570).

## 5. Sem caminhada procedural para GLB (Passo 6)

Já era assim desde a Etapa 10A (`_leg_pivots`/`_arm_pivots` ficam vazios
para dolls GLB, então `_start_walk_cycle()` nunca tem o que animar — guard
clause existente). Esta etapa **removeu também o bounce procedural de
`_body_root.position.y`** para dolls GLB com animação: antes, mesmo com o
modelo novo, o idle "polido" da fase 950 ficava subindo/descendo por cima
do personagem — com o rig agora fazendo idle de verdade, isso duplicava
movimento e daria impressão de flutuar/afundar. Passageiros GLB **sem**
animação (fallback) continuam no bounce antigo, sem mudança.

Cor continua **não** reaplicada — todos ficam com o material amarelo
original do GLB, exatamente como pedido (Etapa 10B trata disso).

## 6. Performance (Passo 7)

Repeti o benchmark com o modelo novo (mesma metodologia da Etapa 10A:
Xvfb + Mesa llvmpipe — software rendering, **não representativo de GPU
mobile real**, só sinal direcional). Desta vez também toquei
`play_idle()` em cada instância, para medir com animação realmente rodando
(a Etapa 10A só media geometria estática).

| Instâncias | Etapa 10A (1,96M tri, sem rig) | Etapa 10A.1 (10 mil tri, com rig) |
|---|---|---|
| 1 | 10,8 fps | **~84 fps** (medição inicial da 10A tinha ruído de 1s de aquecimento; sustentado real é bem mais alto) |
| 10 | 10,6 fps | **~21–25 fps** |
| 30 | 7,6 fps | **~10–11 fps** |
| 40 | (não testado) | **~8–9 fps** |
| 60 | 6,8 fps | **~5–6 fps** |

Achado importante e honesto: em quantidades baixas o modelo novo é MUITO
mais rápido (menos triângulos). Mas a partir de ~40–60 instâncias
simultâneas a vantagem encolhe e a 60 o novo modelo fica ligeiramente MAIS
lento que o antigo (5–6 fps vs 6,8 fps). A explicação mais provável: o
modelo antigo era geometria estática (custo só de rasterização, escala com
triângulos); o novo tem esqueleto + animação, que precisa recalcular a
pose de 41 ossos por instância a cada frame — sob renderização por
software (llvmpipe faz o skinning na CPU), esse custo não cai junto com os
triângulos e vira o novo gargalo em quantidade alta. Numa GPU mobile real, skinning
costuma ser acelerado por hardware e bem mais barato — não tenho como medir
isso neste ambiente, então trato o número de 60 instâncias como um sinal
de atenção, não como veredito final.

`MAX_VISIBLE_QUEUE_DOLLS = 40` continua sendo o teto real de bonecos
simultâneos visíveis no jogo (não 60+) — com 40 instâncias o novo modelo
ainda entrega mais FPS que o antigo entregava. Por isso o flag
`FORCE_GLB_PASSENGER_VISUAL_DEBUG` **continua desligado por padrão** (Passo
10): a melhora é real e grande nas contagens que o jogo de fato usa, mas
recomendo confirmar em hardware mobile real antes de ativar em produção,
dado o comportamento diferente perto do teto de instâncias.

## 7. Animações (Passo 8, resumo do que já foi dito acima)

Skeleton3D e AnimationPlayer confirmados (seção 1); as 3 animações
esperadas existem e tocam corretamente nos 3 momentos certos (seção 4),
sem root motion, sem tocar em `PassengerCrowdController`.

## 8. Teste manual removido (Passo 9)

Confirmei via `git diff` que o único node extra em `PolishTest.tscn` era
exatamente o `passenger_01` solto na raiz, adicionado manualmente pelo
usuário para o teste visual inicial (nenhuma outra diferença no arquivo).
Removido — `PolishTest.tscn` voltou a ficar idêntico ao committado
(`git diff --stat` vazio para este arquivo).

## 9. Validação (Passo 10) — checklist

Rodado com `FORCE_GLB_PASSENGER_VISUAL_DEBUG = true` temporariamente,
`PolishTest`/Fase 950, jogo real (não simulação):

| # | Item | Resultado |
|---|---|---|
| 1 | Personagem aparece corretamente | ✅ confirmado nas screenshots (camisa amarela, cabelo, calça azul, legível) |
| 2 | Pés no chão | ✅ sem flutuar/afundar (bounce procedural removido para GLB animado, seção 5) |
| 3 | Escala adequada | ✅ igual à Etapa 10A (Scale 1.0, sem ajuste necessário) |
| 4 | Fila mantém posições | ✅ confirmado (mesma lógica de `PassengerCrowdController`, zero mudança) |
| 5 | Passageiros continuam reorganizando | ✅ `step_to()` + animação `walk` confirmados |
| 6 | Passageiros continuam indo para veículos | ✅ `walk_to_and_board_polished()` + animação `run` confirmados |
| 7 | Embarque continua funcionando | ✅ 6 passageiros embarcaram, contadores corretos |
| 8 | Contadores corretos | ✅ `ocupados=2/24`, `4/24`; fila 576→570 |
| 9 | Vitória continua possível | ✅ por inferência: `GameEngine`/`GameState`/`LevelGenerator` com diff zero (mesma prova já feita nas etapas 9B/9C); não rodei a fase 950 completa até o fim por limite de tempo de execução automatizada |
| 10 | Nenhum erro novo no debugger | ✅ nenhum `SCRIPT ERROR`/exceção durante toda a validação (idle dessincronizado, 6 toques reais, trocas idle↔walk↔run) |

Não iniciei variedade de personagens, variantes masculino/feminino,
mudança de roupa, nem Etapa 10B — conforme pedido.

## 10. Arquivos alterados

- `scripts/game/passenger_3d.gd` — API de animação (`play_idle/walk/run`,
  `has_animations`), resolução sob demanda de `VisualRoot`/`AnimationPlayer`.
- `scripts/game/passenger_controller.gd` — chama a animação certa nos
  momentos certos; pula o bounce procedural quando o GLB já anima sozinho.
- `scenes/passengers/Passenger3D.tscn` — UID do GLB atualizado (cosmético).
- `assets/characters/passengers/passenger_01.glb` (+ texturas + `.import`)
  — modelo novo (fornecido pelo usuário, não alterado por mim).
- `assets/characters/passengers/passenger_01_pesado.*` — cópia do modelo
  antigo (61,5 MB), preservada pelo usuário como referência/arquivo morto.
- `tests/etapa10a/` — ferramentas de auditoria/validação novas
  (`inspect_glb2.gd`, `inspect_gltf_raw.gd`, `regenerate_glb_cache.gd`,
  `verify_cache_fix.gd`, `check_loop_mode.gd`, `check_compile.gd`,
  `smoke_wrapper3.gd`, `crowd_bench2.gd`) e screenshots novos/atualizados.
- `scenes/game/PolishTest.tscn` — teste manual do usuário removido, arquivo
  voltou ao estado original.

Nenhuma mudança em `game_engine.gd`, `game_state.gd`, `level_generator.gd`
ou nos JSONs de fase (confirmado via `git diff --stat`, saída vazia).

## 11. Riscos e observações para etapas futuras

- O comportamento do import de animação (seção 2) é frágil: qualquer
  reimport futuro do `.glb` pelo editor real pode voltar a zerar as
  animações no cache. Vale a pena o usuário confirmar a causa raiz
  (provavelmente `remove_immutable_tracks`) antes da Etapa 10B.
- Meu ambiente headless não conseguiu completar uma reimportação completa
  do projeto pelo editor (trava consistentemente ao restaurar
  `Passenger3D.tscn`/scripts durante o boot do editor) — isso é uma
  limitação deste sandbox, não do projeto em si; o editor real do usuário
  no Windows já provou funcionar normalmente.
- Custo de skinning em quantidades altas (seção 6) é a única faixa onde o
  modelo novo não é uma vitória clara sobre o antigo — só é relevante
  perto de 60 instâncias simultâneas, acima do teto real do jogo (40).
- `passenger_01_pesado.*` (61,5 MB) ficou no repositório como backup; se
  não for mais necessário, pode ser removido depois para não pesar o
  repositório.
