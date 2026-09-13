# ENTREGA — Etapa 10C: Dois modelos de passageiros 3D com variedade aleatória

## Resumo

`passenger_02.glb` (feminino) foi integrado ao sistema de passageiros 3D ao lado
de `passenger_01.glb` (masculino). Os dois modelos agora aparecem misturados na
mesma fila/multidão, cada um podendo assumir qualquer uma das 7 cores lógicas
do jogo (a cor continua sendo regra de gameplay, o modelo é só apresentação
visual — nunca o contrário). Testado no editor Godot: mistura dos dois
modelos, cores variadas, idle/walk/run funcionando nos dois, sem erro de
carregamento.

## Arquivos alterados

- **Novo:** `scripts/game/passenger_visual_variants.gd` — fonte única de
  configuração de cada modelo (variantes).
- `assets/vfx/passenger_shirt_tint.gdshader` — os 4 parâmetros da máscara de
  cor (matiz da roupa e faixas de transição) viraram `uniform` configurável
  por instância, em vez de `const` fixo (eram exclusivos do passenger_01).
- `scenes/passengers/Passenger3D.tscn` — não tem mais um `.glb` fixo dentro de
  `VisualRoot`; o modelo agora é instanciado em tempo de execução.
- `scripts/game/passenger_3d.gd` — novo método `configure(seed_key)` (escolhe
  e instancia a variante); `set_passenger_color()` passou a usar os
  parâmetros de matiz do perfil da variante ativa; correção do bug de loop
  de animação (ver abaixo).
- `scripts/game/passenger_controller.gd` — `_build_glb_visual()` chama
  `configure(color_id)` antes de `set_passenger_color(...)`.

Nenhum arquivo de gameplay (`GameEngine`, `GameState`, `LevelGenerator`,
lógica de fila/slots/capacidade) foi tocado.

## Arquitetura de variantes

`PassengerVisualVariants.PROFILES` é um array central com um "perfil" por
modelo:

```
PROFILES := [
    { scene: passenger_01.glb, scale, rotation_degrees, position_offset,
      shirt_hue, shirt_hue_full, shirt_hue_zero, shirt_sat_floor },
    { scene: passenger_02.glb, ... mesmos campos, valores próprios ... },
]
```

Adicionar um `passenger_03/04/05/06` no futuro é acrescentar mais uma entrada
neste array — nenhum outro arquivo do projeto precisa mudar.

`Passenger3D.configure(seed_key)` roda uma única vez por instância (guard
`_variant_configured`): calcula `hash(seed_key + str(get_instance_id()))`,
escolhe o índice da variante com `posmod(hash, PROFILES.size())`, instancia o
`.glb` daquela variante dentro de `VisualRoot` e aplica escala/rotação/offset
do perfil. `seed_key` é o `color_id` do passageiro (informação que
`PassengerController` já tinha) — `PassengerController` nunca fica sabendo
qual modelo foi escolhido, só pede `idle`/`walk`/`run` (Passo 8 do pedido).

Por que hash em vez de `randf()`/`randi()` cru: o mesmo hash sempre dá o
mesmo resultado para a mesma instância, então o modelo nunca troca sozinho
durante `idle`/`walk`/`run`/reorganização/embarque (garantido pelo guard
`_variant_configured`, não só pelo hash ser determinístico). O
`get_instance_id()` garante boa dispersão entre passageiros diferentes, mesmo
quando muitos compartilham o mesmo `color_id`.

## Distribuição observada

Não foi feita uma contagem estatística formal (não é o objetivo do pedido:
"não precisa ser exatamente 50/50 em grupos pequenos"). O usuário confirmou
visualmente, rodando a Fase 950, que os dois modelos aparecem misturados e
que a multidão não lê como "um monte de clones" — o `hash()` do Godot é bem
distribuído, então uma multidão de 40 passageiros tende a ficar perto de
50/50 sem favorecer nenhum dos dois modelos.

## Correção do bug de loop por modelo

O código que força as 3 animações para `Animation.LOOP_LINEAR` (o GLB exporta
com `loop_mode = NONE`) usava um único `static var _loop_configured: bool`
compartilhado por todas as instâncias — correto quando só existia um modelo,
porque o recurso `Animation` era o mesmo objeto para todo mundo. Com dois
modelos, cada `.glb` tem seu **próprio** recurso `Animation` (mesmos nomes,
objetos diferentes): o bool único configuraria o loop na primeira vez que
QUALQUER passageiro (de qualquer modelo) tocasse uma animação, e todas as
chamadas seguintes — inclusive as do OUTRO modelo — seriam ignoradas. Na
prática isso deixaria as animações de um dos dois modelos presas no
`loop_mode` `NONE` original (parando no último frame em vez de repetir),
dependendo de qual modelo aparecesse primeiro na sessão.

Corrigido trocando o bool único por um `Dictionary` (`_configured_loop_animations`)
chaveado pelo **recurso `Animation`** em si, não por uma flag global — cada
recurso (de cada modelo) é configurado exatamente uma vez, não importa quantos
modelos existam.

## Parâmetros de cor por modelo (medidos na textura albedo de cada `.glb`)

**passenger_01** (camiseta amarela original):
- `shirt_hue` = 0.1211 (~44°)
- `shirt_hue_full` = 0.028 (~10°, raio onde a máscara fica em 1.0)
- `shirt_hue_zero` = 0.050 (~18°, distância a partir da qual a máscara é 0.0)
- `shirt_sat_floor` = 0.25

**passenger_02** (moletom rosa original):
- `shirt_hue` = 0.9417 (~339°)
- `shirt_hue_full` = 0.028 (~10°)
- `shirt_hue_zero` = 0.050 (~18°)
- `shirt_sat_floor` = 0.25

Ambos medidos via histograma de matiz/saturação da textura basecolor de cada
GLB (fora do Godot, direto no glTF). Em ambos os modelos a roupa principal
fica isolada por matiz com boa folga de outras partes do corpo: no
passenger_01, pele (~25°) e calça/tênis azuis (~200-230°); no passenger_02,
cabelo (~15°), pele (~25°) e calça azul (~200-220°) — nenhum desses fica
dentro da faixa `shirt_hue_full..shirt_hue_zero` de nenhum dos dois modelos.

## Escala / rotação / offset por modelo

Auditoria da bounding box (`accessor POSITION`, eixo Y) de cada `.glb`:

- passenger_01: altura ~0.9811 (min y ≈ -0.0001, max y ≈ 0.9809) — pés
  praticamente em y=0.
- passenger_02: altura ~0.9790 (min y ≈ 0.0008, max y ≈ 0.9798) — pés
  praticamente em y=0.

Diferença de altura ~0.2%, pés a menos de 1mm de diferença: os dois modelos
vieram do mesmo pipeline de retopologia/rig e ficam indistinguíveis em jogo.
**Nenhuma correção foi necessária** — os dois perfis usam
`scale = 1.0`, `rotation_degrees = 0.0`, `position_offset = Vector3.ZERO`. Os
campos existem prontos no `PassengerVisualProfile` para quando um modelo
futuro vier com proporção diferente.

## Validação visual (feita pelo usuário no editor Godot)

Confirmado pelo usuário, rodando a Fase 950 (PolishTest):
- passenger_01 e passenger_02 aparecem simultaneamente na mesma multidão;
- cores variadas nos dois modelos, batendo com `color_id`;
- idle / walk / run funcionando nos dois;
- nenhum erro novo apareceu no console de carregamento.

Garantias de arquitetura (verificadas por revisão de código, não por teste
isolado de estresse):
- nenhum modelo troca durante a vida de um passageiro — `configure()` só
  aplica a escolha uma vez (`_variant_configured`), nunca mais depois disso;
- nenhuma instância contamina outra — cada `Passenger3D` monta seu **próprio**
  `ShaderMaterial` e usa `set_surface_override_material()` (nunca edita o
  material original compartilhado do GLB); a própria prova visual do usuário
  (várias cores diferentes ao mesmo tempo, nos dois modelos) já é evidência
  empírica disso — se o material fosse compartilhado, mudar uma cor mudaria
  todas;
- fila/embarque: nenhum arquivo de lógica de fila/embarque foi alterado nesta
  etapa; o teste na Fase 950 (que exercita fila + reorganização + embarque em
  cascata) não reportou problema.

## Performance

Não foi medido FPS numérico nesta rodada (nem no editor nem no device físico)
— o usuário confirmou apenas que a mistura dos dois modelos funcionou sem
travamento perceptível. Arquitetura pensada para não regredir a performance
da Etapa 10B: nenhuma textura é duplicada por passageiro (todas as
instâncias de um mesmo modelo compartilham os mesmos `Texture2D` do GLB
original, referenciados, não copiados); o `Shader` (`passenger_shirt_tint.gdshader`)
é um único recurso compartilhado por todas as instâncias, de ambos os
modelos; só o pequeno `ShaderMaterial` (parâmetros escalares/vetor) é
exclusivo por instância — mesmo padrão já validado na Etapa 10B.

## Problemas conhecidos / pendências

- **Teste no device físico (Passo 13 do pedido) não foi feito nesta rodada**
  — a validação relatada foi no editor Godot, não no Android. O ambiente
  isolado que uso para mexer no projeto (`device_bash`) está sem acesso a
  ADB/hardware Android desde o início da Etapa 10A.2, e segue sem
  conseguir executar comandos desde 8/set (ver abaixo) — o teste em
  aparelho real continua dependendo do usuário rodar e reportar.
- **Bridge de arquivos instável**: desde um update do Windows de 8/set, o
  canal de execução de comandos (`device_bash`) neste projeto está fora do
  ar (mensagem: "A Windows update released September 8 prevents Claude's
  workspace from reaching your files"). A escrita de arquivo por arquivo
  (`device_stage_files`/`device_commit_files`) continua funcionando na
  maior parte das vezes, mas nesta mesma etapa uma escrita (a flag
  `FORCE_GLB_PASSENGER_VISUAL_DEBUG`) reportou sucesso e não se manteve no
  disco depois de recarregada — sinal de que essa mesma instabilidade às
  vezes afeta escritas, não só comandos. Por causa disso:
  - o **checkpoint Git desta etapa não pôde ser criado remotamente** (sem
    `device_bash`, não há como rodar `git add`/`git commit` daqui) — ver
    comandos sugeridos abaixo;
  - a flag `FORCE_GLB_PASSENGER_VISUAL_DEBUG` deveria estar `false` (Passo 4
    do fechamento) mas precisa de confirmação manual: se o arquivo
    `scripts/game/game_controller.gd` estiver aberto em algum editor no seu
    PC, salvar por lá pode sobrescrever a mudança feita por fora. Confirme
    a linha ~80 antes de considerar isto fechado.
- Distribuição passenger_01/passenger_02 não foi contada estatisticamente
  (não era exigido) — só confirmada visualmente como "misturada".

## Checkpoint Git sugerido

Como não consigo rodar comandos no seu PC agora, os comandos abaixo fazem o
checkpoint desta etapa (rode no terminal do seu projeto):

```
git add scripts/game/passenger_visual_variants.gd ^
        assets/vfx/passenger_shirt_tint.gdshader ^
        scenes/passengers/Passenger3D.tscn ^
        scripts/game/passenger_3d.gd ^
        scripts/game/passenger_controller.gd ^
        scripts/game/game_controller.gd

git commit -m "Etapa 10C: passenger_02 (feminino) integrado com variedade de modelo deterministica e recolor por variante"
```

(No PowerShell/CMD troque `^` por continuar tudo na mesma linha, ou rode cada
`git add` separado.)
