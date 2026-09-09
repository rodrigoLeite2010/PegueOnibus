# Pega Passageiro

Projeto base para o jogo mobile 3D em Godot.

## Versao alvo

- Engine: Godot 4.7.2 Stable
- Linguagem: GDScript tipado
- Renderizador: Mobile
- Plataforma principal: Android portrait

## Etapa 0 concluida

- Projeto Godot criado.
- Orientacao portrait configurada.
- Renderizador Mobile configurado.
- Mouse emulando toque e toque emulando mouse.
- Estrutura de pastas inicial criada.
- Cena principal vazia criada em `scenes/app/Main.tscn`.
- Export preset Android debug inicial criado.
- Git inicializado.

## Etapa 1 concluida

- `LevelDefinition`, `VehicleDefinition`, `GameState`, `VehicleState`, `WaitingSlotState` e `GameEvent` criados.
- `GameEngine` criado como core logico sem depender de Nodes 3D, UI ou animacoes.
- Estado inicial de fase criado a partir de dados.
- Fila de passageiros preserva ordem estrita.
- Veiculos possuem capacidade configuravel e ocupacao atual.
- Slots de espera possuem ocupacao por `vehicle_id`.
- Embarque automatico processa passageiros consecutivos da cor na frente da fila.
- Veiculo parcialmente cheio permanece no slot.
- Quando a mesma cor reaparece, o veiculo retoma o embarque.
- Vitoria quando a fila fica vazia.
- Derrota inicial quando todos os slots estao cheios sem veiculo compativel com a frente da fila.
- Testes de core adicionados em `tests/test_game_core.gd`.

## Etapa 2 concluida

- Footprint logico adicionado aos veiculos.
- Footprint padrao calculado por tipo e orientacao quando a fase nao informa tamanho manual.
- Grade logica usa linhas e colunas da fase.
- `GameEngine.get_vehicle_cells()` retorna as celulas ocupadas por cada veiculo.
- `GameEngine.get_exit_path_cells()` calcula o caminho ate a borda nas direcoes `up`, `down`, `left` e `right`.
- `GameEngine.can_vehicle_exit()` retorna `can_exit`, `blockers` e `path`.
- `try_send_vehicle_to_waiting_slot()` agora bloqueia a saida quando ha veiculo no caminho e emite `VehicleBlocked`.
- Game Over considera a disponibilidade real dos slots; com todos ocupados, um veiculo livre no tabuleiro nao conta como jogada valida porque nao ha vaga para recebe-lo.
- Testes cobrem footprint e bloqueio nas quatro direcoes.

## Etapa 3 concluida

- Cena `scenes/game/Game.tscn` criada.
- Cena `scenes/game/Board.tscn` criada.
- Cena `scenes/game/Vehicle.tscn` criada.
- `BoardController` cria chao e linhas de grade em 3D.
- `VehicleController` cria placeholders 3D toy-like com corpo, cabine, rodas e marcador de direcao.
- `GameController` cria uma fase visual de preview usando o core logico.
- `Camera3D` ortografica configurada com visao superior inclinada.
- `DirectionalLight3D` e `WorldEnvironment` configurados para iluminacao mobile simples.
- `Main.tscn` agora instancia a cena `Game.tscn`.

Esta etapa ainda nao tem interacao de toque, animacoes, passageiros ou UI final. Isso comeca nas proximas etapas.

## Etapa 4 concluida

- A cena 3D agora usa o `GameEngine` como fonte oficial de regra.
- Veiculos do tabuleiro sao instanciados a partir do `GameState`.
- HUD atualiza fase, movimentos, fila restante e slots a partir do estado real.
- Toque/click em veiculo chama `try_send_vehicle_to_waiting_slot()`.
- Veiculo bloqueado nao altera estado e mostra mensagem de bloqueio.
- Veiculo livre atualiza slots, fila, embarque automatico, vitoria e Game Over.
- Botao de reiniciar recria o estado inicial da fase.

## Etapa 5 concluida

- Veiculos placeholder possuem area clicavel 3D.
- Toque valido gera micro escala/bounce.
- Veiculo bloqueado gera shake curto.
- Veiculo livre anima saida na direcao configurada.
- Veiculo removido do tabuleiro apos a animacao.
- Fila visual agora usa pequenas silhuetas de pessoas coloridas em 2D.
- Slots visuais mostram veiculos aguardando e ocupacao/capacidade.
- Painel simples de vitoria/derrota aparece quando o estado terminal e atingido.

Ainda nao ha passageiros 3D caminhando ate o veiculo, audio, haptics, moedas ou particulas. Isso entra na vertical slice/polimento das proximas etapas.

## Etapa 6 concluida

- A imagem fornecida `carros.png` foi copiada para `assets/textures/vehicles/carros_source.png`.
- Foram gerados recortes PNG por cor/tipo em `assets/textures/vehicles/`.
- Os veiculos agora usam os carros recortados como sprites 2.5D no tabuleiro, mantendo a area clicavel e o footprint logico.
- A escala dos veiculos foi normalizada pelo footprint logico para manter leitura consistente e evitar cortes.
- Passageiros 3D simples foram adicionados em `scenes/game/Passenger.tscn`.
- Quando passageiros embarcam, pequenas pessoas coloridas aparecem e se movem ate o veiculo.
- Toques validos e bloqueados usam vibracao basica quando o aparelho suporta.
- Vitoria gera particulas/confete simples em 3D.
- A cena `Game.tscn` agora separa `Vehicles`, `Passengers` e `VFX`.

Ainda faltam audio real, moedas animadas ate o contador, modelos GLB finais e ajuste fino em aparelho Android real.

## Etapa 7 concluida

- Recursos configuraveis de veiculo foram adicionados em `resources/vehicle_types/`.
- Cada cor agora pode apontar para sprite PNG ou para uma cena/modelo 3D futuro sem alterar o `GameEngine`.
- `VehicleVisualResource` centraliza textura, escala visual, altura clicavel e ponto de porta para embarque.
- `VehicleController` deixou de depender de um mapa fixo de sprites e passou a ler os dados pelo `VehicleVisualLibrary`.
- O ponto de destino dos passageiros agora usa a porta configurada no asset do veiculo.
- A cena `scenes/game/VehiclePreview.tscn` foi criada para revisar escala, pivô, orientação e enquadramento dos carros.

Para ajustar um carro, abra o arquivo da cor em `resources/vehicle_types/` e altere `sprite_scale`, `sprite_vertical_offset`, `collider_height` ou `door_offset`.

## Etapa 8 concluida

- Sistema de audio adicionado como singleton `AudioManager` (`scripts/audio/audio_manager.gd`, registrado em `[autoload]` no `project.godot`).
- Efeitos sonoros de toque valido, bloqueio, embarque, veiculo completo, moeda, vitoria e derrota adicionados em `assets/audio/*.ogg`. Sao placeholders **sinterizados por codigo** (sem nenhum asset de terceiros, zero risco de licenciamento) - trocar por audio definitivo depois e so substituir os arquivos `.ogg`, sem tocar em nenhum script.
- Vibracao (haptics) agora passa por `AudioManager.vibrate()`, respeitando o toggle.
- Botao "Pause" da HUD deixou de mostrar uma mensagem placeholder e agora abre um popup real de configuracoes com toggles de "Efeitos sonoros" e "Vibracao" (persistidos em `user://audio_settings.cfg`). Nao ha toggle de musica ainda porque nao ha trilha musical - um controle sem efeito repetiria o problema dos botoes mortos que foi corrigido nesta mesma leva de ajustes.
- Contador de moedas cosmetico adicionado (`Wallet`, autoload em `scripts/core/wallet.gd`, persistido em `user://wallet.cfg`). Badge visivel no canto superior esquerdo da HUD.
- Vencer uma fase agora recompensa moedas com uma pequena animacao: moedinhas voam em curva do centro da tela at o contador (escala, rotacao e trajetoria), com som e um "bump" no contador ao chegar.
- Ainda NAO existe loja, gasto de moedas ou economia real - isso e a etapa de Progressao do roadmap oficial da especificacao (item 9), fora do escopo deste passo.

Nota sobre numeracao: o roadmap oficial da especificacao (secao 17/tabela "Etapa | Entrega") define a Etapa 8 como "Tutorial/fases: primeiras 10-30 fases, solver/validador e dificuldade progressiva" - isso ja foi entregue (e superado) pelo `LevelGenerator` com construcao garantidamente soluvel, adicionado numa leva de ajustes anterior. O que este bloco chama de "Etapa 8" segue a numeracao deste README (que apos a Etapa 7 apontava audio/moedas/polimento de HUD como proximo passo), nao a tabela oficial - registrando aqui para nao confundir quem comparar os dois documentos.

## Como abrir

1. Abra o Godot 4.7.2 Stable.
2. Importe a pasta `C:\Alilu\Jogos\PegaPassageiro`.
3. Abra o projeto.
4. Rode a cena principal com F5.

## Como testar pelo terminal

Se o Godot estiver no PATH:

```powershell
godot --path "C:\Alilu\Jogos\PegaPassageiro"
```

Para validar o projeto sem abrir janela:

```powershell
godot --headless --path "C:\Alilu\Jogos\PegaPassageiro" --quit
```

Para rodar os testes do core:

```powershell
godot --headless --path "C:\Alilu\Jogos\PegaPassageiro" --script res://tests/test_game_core.gd
```

## Proxima etapa

Seguindo o roadmap oficial da especificacao: Etapa 9 - Progressao (home, mapa de fases, moedas gastavel/estrelas, save local mais completo e configuracoes). Etapa 10 (polimento/VFX/performance/QA) e Etapa 11 (loja/publicacao) ficam para depois, e a 11 nao deve ser feita sem autorizacao explicita.

## Ajuste visual da Etapa 3

A prévia 3D foi refinada para ficar mais próxima de um jogo casual mobile moderno:

- veículos placeholder mais arredondados, com corpo tipo brinquedo, cabine, rodas, sombra e marcador de direção;
- tabuleiro com tons pastel, linhas suaves e portões de saída;
- câmera ortográfica mais próxima e inclinada;
- HUD 2D de referência com título de fase, fila de passageiros, slots e botões inferiores;
- fundo e iluminação mais claros para lembrar a composição da referência enviada.

Esses elementos ainda são placeholders. Os modelos GLB/glTF finais poderão substituir `Vehicle.tscn` sem alterar o `GameEngine`.

## Revisao de estabilidade e layout - 08/09/2026

Foi feita uma revisao estrutural depois do prototipo apresentar carros fora do enquadramento, escalas inconsistentes e Game Over incorreto.

Principais mudancas:

- `GameController` carrega a fase real de `levels/level_001.json`.
- `HUD` agora existe como cena editavel em `scenes/ui/HUD.tscn`; abra essa cena no Godot para mover/redimensionar os elementos visualmente.
- A camera calcula o enquadramento em portrait com margem lateral para evitar sprites cortados.
- O board usa um visual limpo; a grade logica continua existindo, mas as linhas de debug ficam ocultas.
- Footprints nao sao mais forçados para `1x1` na fase.
- Sprites de veiculos sao escalados de forma uniforme pelo maior eixo do footprint.
- Slots ocupados exibem miniatura do veiculo e capacidade.
- Corrigida a regra de Game Over quando todos os slots estao cheios e nenhum deles atende a cor da frente.
- A fase 1 foi reorganizada para nao ter sobreposicao e para usar seis cores.

Consulte tambem `FIXES_2026-09-08.md`.
# PegueOnibus
