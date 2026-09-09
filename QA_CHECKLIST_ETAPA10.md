# Checklist de QA — Etapa 10 (Polimento)

Este checklist existe porque não há Godot/CLI nem um dispositivo Android disponível neste ambiente para rodar o jogo de verdade — todas as edições da Etapa 10 (e das anteriores) foram validadas por leitura e comparação exata de texto, arquivo por arquivo, mas isso não substitui abrir o projeto e jogar. Use esta lista para validar manualmente, de preferência num celular Android real (a especificação pede testes em múltiplos aparelhos, não só no editor).

## 1. Novidades da Etapa 10 para testar

**Performance (fila de passageiros)**
- [ ] Jogue uma fase com fila longa (10+ passageiros) e toque em vários veículos rapidamente em sequência. A fila deve atualizar sem engasgar (esse era o ponto fraco: antes cada atualização destruía e recriava todos os ícones da fila).
- [ ] Depois de reduzir a fila várias vezes (embarques sucessivos), confirme que não sobra nenhum ícone "fantasma" nem o "+N" aparece quando não deveria.

**Acessibilidade a daltonismo**
- [ ] Abra Configurações (na Home ou na Pausa) e confirme que existe o toggle "Símbolos de cor (daltonismo)", ligado por padrão.
- [ ] Com o toggle ligado, confirme que aparece um símbolo (▲ ● ■ ★ ◆ ✚ ✖) sobre cada passageiro na fila, dentro de cada vaga de espera ocupada, e ao lado da seta de direção em cima de cada veículo — cada cor sempre com o mesmo símbolo.
- [ ] Desligue o toggle: os símbolos da fila e das vagas de espera devem sumir imediatamente (são redesenhados a cada atualização). **Limitação conhecida**: os veículos que já estavam no tabuleiro no momento em que você desligou vão continuar mostrando o símbolo junto da seta até a próxima vez que aparecerem (reiniciar a fase ou carregar outra atualiza). Confirme que esse comportamento é aceitável ou avise se preferir que eu feche essa lacuna.
- [ ] Ligue de novo e reinicie a fase: os veículos recém-criados devem vir com o símbolo.

**VFX e áudio extra**
- [ ] Ao um passageiro embarcar, confirme que aparecem pequenas partículas coloridas (na cor do passageiro) no ponto de embarque, além do "pulo" que já existia.
- [ ] Use a Dica (gasta moedas) e confirme que toca o som de moeda (o mesmo já usado na recompensa de vitória) no momento em que a dica é concedida — e que ele NÃO toca se não houver moedas suficientes nem se não houver jogada disponível (nesses casos as moedas são devolvidas, sem som).

## 2. Critérios de aceite visual (seção 19 da especificação)

- [ ] O jogo mantém uma taxa de quadros estável (alvo: 60 FPS) num celular Android real, inclusive em fases com tabuleiro grande e muitos veículos.
- [ ] Nenhum veículo "teleporta": todo movimento (ida até a vaga, saída após completar) é sempre animado.
- [ ] A recompensa de moedas ao vencer mostra a animação de moedas voando até o contador, com som.
- [ ] A câmera mantém o tabuleiro inteiro visível e fora das faixas da HUD em pelo menos 2-3 proporções de tela diferentes (celular estreito, celular mais largo, tablet se tiver).

## 3. Testes obrigatórios (seção 20 da especificação)

- [ ] Veículo livre em cada uma das 4 direções (cima/baixo/esquerda/direita) sai corretamente.
- [ ] Veículo bloqueado nas 4 direções mostra o feedback de bloqueado (tremor + som) e não se move.
- [ ] Veículos com capacidades diferentes (1, 2, 3+ passageiros) enchem e liberam a vaga corretamente.
- [ ] Uma mesma cor de passageiro pode reaparecer na fila depois de já ter sido usada antes, sem confundir o motor.
- [ ] Um veículo parcialmente cheio mantém o preenchimento certo se você sair da fase e voltar (restart) ou trocar de veículo no meio do processo.
- [ ] Game Over acontece exatamente quando não há mais nenhuma jogada válida (não antes, não depois).
- [ ] Cancelar/interromper uma animação no meio (ex: tocar em outro lugar enquanto um veículo anda) não deixa o estado do jogo inconsistente.
- [ ] Reiniciar a fase (botão Reiniciar) sempre volta ao estado exato do início da fase, sem "restos" da tentativa anterior.
- [ ] Trocar um veículo placeholder por um modelo GLB (quando/se isso for feito futuramente) não deveria quebrar nada nesta etapa — não há GLB novo aqui, mas vale conferir que os veículos placeholder atuais continuam OK.

## 4. Fluxo de Home/Mapa/Progressão (Etapa 9, para não esquecer)

- [ ] "Jogar" na Home abre direto a fase mais avançada ainda não vencida.
- [ ] "Mapa de fases" mostra as fases desbloqueadas com estrelas certas e um teaser de fases bloqueadas.
- [ ] Vencer uma fase leva de volta ao Mapa (não para a próxima fase automaticamente).
- [ ] As estrelas ganhas (3 = sem toques bloqueados, 2 = 1-2, 1 = 3+) aparecem certas no modal de vitória e persistem no Mapa.

## 5. Testes específicos de Android (também seção 20)

- [ ] Build gerado e instalado num aparelho Android real (não só emulador).
- [ ] Toque na tela funciona igual ao clique do mouse no editor (todas as interações: veículos, botões, toggles).
- [ ] Layout respeita a área segura do aparelho (notch, barra de gestos) em pelo menos um aparelho com notch/corte de tela.
- [ ] Áudio toca corretamente no aparelho (efeitos sonoros e, se aplicável, vibração).
- [ ] Vibração (haptic feedback) funciona nos momentos esperados (bloqueado, toques, etc.).
- [ ] Desempenho aceitável (sem quedas de frame perceptíveis) num aparelho de configuração mediana, não só no topo de linha.

---

Se algum item falhar, me avise apontando qual e o que aconteceu (print ou vídeo ajuda bastante) que eu já reviso o código correspondente.
