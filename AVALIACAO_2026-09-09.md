# Pega Passageiro - Avaliacao tecnica e plano (09/09/2026)

Revisao completa do projeto (etapas 0 a 7 do documento de especificacao v3), lendo o core (`scripts/core`), os controllers visuais (`scripts/game`, `scripts/ui`), as cenas, as 5 fases (`levels/level_00X.json`), os testes (`tests/test_game_core.gd`) e os `.md` de historico ja existentes no projeto (`FIXES_2026-09-08.md`, `CHANGES_ANIMATION_LEVELS_2026-09-09.md`).

## 1. O que ja esta solido (nao precisa reescrever)

- O motor de regras (`GameEngine`/`GameState`/`VehicleState`) esta corretamente separado da parte visual, exatamente como a especificacao pede. Fila ordenada, capacidades por veiculo, bloqueio nas 4 direcoes, veiculo parcialmente cheio retomando embarque, vitoria/derrota: tudo isso funciona e tem testes cobrindo cada regra em `tests/test_game_core.gd`.
- Fases sao dados (`levels/*.json`), nao codigo. Boa base para crescer.
- Recursos de veiculo por cor (`resources/vehicle_types/*.tres`) evitam nomes de arquivo hardcoded no motor, como a especificacao pede.

## 2. Por que hoje "nao parece jogo" - causas encontradas no codigo

1. **Carro sempre de frente para a camera.** O sprite do veiculo (`vehicle_controller.gd -> _add_sprite_visual`) usa `Sprite3D` com `billboard = BILLBOARD_ENABLED`. Isso faz a imagem girar para sempre encarar a camera, entao o carro nunca inclina/gira ao se mover: ele so desliza como um recorte de papel na tela. Essa e a causa tecnica mais provavel da sensacao de "pagina HTML" em vez de diorama 3D.
2. **Carro e onibus da mesma cor sao literalmente a mesma imagem, so esticada.** `VehicleVisualLibrary` escolhe o visual **apenas pela cor** (`RESOURCE_BY_COLOR`), nunca pelo tipo (`car`/`van`/`bus`). O footprint logico ja diferencia comprimento (`VehicleDefinition._apply_default_footprint_if_needed`: carro = 2, onibus/van = 3), mas a arte nao acompanha - um "onibus" vermelho e so o carro vermelho esticado.
3. **Nenhuma fase usa veiculo grande.** As 5 fases (`level_001.json` a `level_005.json`) usam **somente** `"type":"car"`, capacidade 2, em todas. O motor ja suporta `van`/`bus`/`mini_bus` (inclusive ha um `assets/textures/vehicles/bus.png` ja recortado e **nunca usado** em lugar nenhum), mas isso nunca aparece em uma fase real.
4. **Tabuleiro muito vazio.** O chao e uma cor solida quase branca (`board_controller.gd`, `#e9eef8`), sem nenhuma marcacao de vaga/pista, e os "portoes" de saida sao brancos quase invisiveis sobre fundo quase branco.
5. **Passageiro "desliza" em vez de andar.** `passenger_controller.gd` move uma capsula em 2 passos com uma leve inclinacao lateral; nao ha perna/pe articulado, entao a leitura de "andando" e fraca.
6. **3 botoes mortos na HUD.** `VIP`, `Organizar` e `Dica` existem na cena (`HUD.tscn`) mas `hud_controller.gd` nunca conecta o `pressed` deles a nada - tocar neles hoje nao faz nada, o que costuma ser o tipo de coisa que mais entrega "prototipo" para quem esta jogando.
7. **2 vagas de espera sao decoracao.** Alem dos slots reais, a HUD sempre desenha 2 cards extra com "+" que sao so visual (`hud_controller._render_slots`, comentario "aparecem apenas como teaser visual") e nao fazem nada ao tocar.
8. **Sem audio nenhum ainda** (isso ja estava anotado como proxima etapa no README).
9. **Progressao de fase e um loop fixo de 5 fases.** `game_controller.next_level()` percorre as 5 fases descobertas em `levels/` e, ao acabar, **volta para a fase 1** ("apenas para testes", segundo o proprio comentario no codigo). Isso nao atende ao pedido de "sempre uma fase nova aumentando a dificuldade": hoje nao existe gerador de fases nem validador de solubilidade (a propria especificacao, secao 12, pede um solver offline que ainda nao foi criado).

## 3. Bug logico latente (nao disparado ainda, mas real)

`GameEngine.update_terminal_status` so declara derrota quando **todos** os slots estao cheios e nenhum veiculo em espera atende a cor da frente. Se os slots **nao** estiverem todos cheios mas nenhum veiculo do tabuleiro conseguir sair em nenhuma das 4 direcoes (tabuleiro travado com vaga livre), o jogo nunca declara Game Over - fica "jogando" para sempre sem jogada possivel. Existe uma funcao pronta pra cobrir isso, `has_any_valid_board_move()`, mas ela nao e chamada em lugar nenhum hoje (foi removida de `update_terminal_status` em uma correcao anterior, ver `backup_before_fix_2026_09_08/game_engine.gd`). Isso nao aparece com as 5 fases atuais porque foram desenhadas a mao, mas vira um risco real assim que houver geracao de fases nova.

## 4. Plano proposto

### Posso fazer só com codigo, sem arte nova
- Trocar o sprite billboard por uma orientacao "decal" (plano deitado seguindo a direcao do movimento) ou usar como padrao o carrinho 3D processual que ja existe no codigo (`_add_procedural_vehicle` - corpo, cabine, para-brisa) enquanto a arte final nao chega; ele ja gira e sombreia de verdade porque nao e billboard.
- Diferenciar tipos de veiculo mesmo sem arte nova (aproveitar o `bus.png` ja recortado e nao usado; dar proporcoes/detalhes distintos ao carrinho processual por tipo).
- Colocar veiculos van/onibus de verdade em pelo menos algumas fases (o motor ja suporta).
- Criar um gerador de fases + validador de solubilidade simples, com dificuldade crescente (mais cores, mais veiculos, fila maior, menos vagas conforme o numero da fase sobe) para nunca mais repetir a fase 1 como fallback.
- Cobrir o soft-lock: religar `has_any_valid_board_move()` na checagem de Game Over.
- Ligar os 3 botoes mortos a algo real (ou escondê-los ate terem funcao de verdade) e remover/ativar os 2 slots-fantasma.
- Melhorar a caminhada do passageiro (balanco de perna simples) e adicionar squash/stretch nos veiculos, como pede a secao 7-8 da especificacao.
- Adicionar audio com efeitos temporarios (toque valido, bloqueio, embarque, vitoria) e um botao de mudo, mesmo antes de haver trilha/SFX definitivos.
- Dar um pouco mais de textura ao tabuleiro (linhas de vaga, portao mais visivel) sem pesar no desempenho mobile.

### Preciso de uma decisao/material seu
- **Arte de veiculo por tipo**: preferencia entre (a) eu gerar sprites 2D estilizados por tipo (carro/van/micro-onibus/onibus) por enquanto, (b) partir para modelos 3D (GLB) reais mais pra frente, como a especificacao original pede, ou (c) voce fornecer/encomendar a arte e eu so ligo no sistema (que ja esta preparado pra isso via `VehicleVisualResource`).
- **Passageiros**: manter o estilo processual atual (capsula+esfera) com animacao melhorada, ou usar sprite/modelo?
- **Audio**: voce tem trilha/efeitos, ou posso buscar audio livre de direitos como placeholder ate ter algo definitivo?
- **Os 3 botoes (VIP/Organizar/Dica)**: sao features reais planejadas (o documento fala em nao adicionar loja/anuncios antes do core estar estavel) ou devo so escondê-los por enquanto?
- **Icone/nome definitivo** para publicacao Android quando chegar a hora.

## 5. O que eu NAO mudaria sem falar antes

Nada nas regras (`scripts/core`) precisa mudar - a logica de fila/vagas/capacidade ja segue a especificacao a risca e tem teste cobrindo. As mudancas propostas acima sao todas de apresentacao (visual/anima cao/UI) e de conteudo de fase (gerador), nunca de regra.
