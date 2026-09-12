# ENTREGA — Etapa 9B: Auditoria de Solvabilidade das Fases Procedurais

## Resumo executivo

O GameOver visto na fase 948 (~34s, POLISHED, muitos veículos e passageiros ainda em tela) **não é bug de bloqueio nem fase impossível**. A fase 948 é **matematicamente solvável** (existe sequência vencedora, reproduzida e confirmada abaixo com o GameEngine real) mas é **genuinamente frágil**: com jogo levemente subótimo (heurísticas "80% útil/20% aleatório" e "70/30") a taxa de vitória cai para 50% e 38%; com jogo aleatório a taxa é 0%.

Foi tentada uma correção na fila de passageiros (hipótese inicial do brief: blocos rígidos de uma cor só, do tamanho da capacidade do veículo, seriam a causa da fragilidade). Essa correção foi **implementada, testada rigorosamente e revertida**, porque os dados mostram que ela **piora** a robustez em vez de melhorar. A causa raiz real é outra (ver Seção 6) e fica documentada para uma etapa futura dedicada — não alterei o `LevelGenerator` nesta entrega porque nenhuma correção que testei passou na validação empírica sem regressão. `scripts/core/level_generator.gd` está devolvido ao estado original (sem diffs).

---

## 1. Não assumir que era bug — o que de fato aconteceu

Testado com o `GameEngine` real (nenhuma regra alterada), para a fase 948 exatamente como o `LevelGenerator` a gera hoje:

| Hipótese | Veredito |
|---|---|
| A) Deadlock legítimo causado pelo jogador | **Compatível** — jogo subótimo (não necessariamente "errado") causa GameOver com alta frequência |
| B) Fase solucionável, porém frágil | **Confirmada** — ver Seção 4 |
| C) Fase gerada impossível | **Descartada** — existe sequência vencedora (Seção 3) |
| D) Inconsistência veículos/capacidades/cores/passenger_queue | **Descartada** — demanda por cor bate exatamente (Seção 2) |

A detecção de deadlock do `GameEngine` **não foi tocada** e continua sendo a fonte da verdade.

## 2. Reprodução da fase 948 e demanda por cor

`LevelGenerator.generate(level_number)` usa `rng.seed = level_number` (determinístico). Reproduzi a fase 948 chamando exatamente esse caminho de código (via Godot 4.3 headless, mesmo motor do jogo).

**Tabuleiro:** 12 linhas × 10 colunas · 4 waiting_slots · 18 veículos · 480 passageiros.

**Veículos** (id, tipo, cor, capacidade, posição, orientação, direção de saída):

| id | tipo | cor | cap | pos (row,col) | orientação | saída |
|---|---|---|---|---|---|---|
| red_0 | medium_car | red | 24 | (0,8) | vertical | up |
| yellow_1 | bus | yellow | 40 | (3,6) | vertical | up |
| green_2 | small_car | green | 16 | (7,1) | horizontal | left |
| blue_3 | small_car | blue | 16 | (6,3) | horizontal | left |
| orange_4 | small_car | orange | 16 | (11,0) | horizontal | left |
| purple_5 | medium_car | purple | 24 | (0,4) | vertical | up |
| pink_6 | small_car | pink | 16 | (10,3) | horizontal | left |
| red_7 | small_car | red | 16 | (1,0) | horizontal | left |
| yellow_8 | medium_car | yellow | 24 | (0,1) | horizontal | right |
| green_9 | bus | green | 40 | (2,0) | vertical | up |
| blue_10 | medium_car | blue | 24 | (7,4) | vertical | down |
| orange_11 | bus | orange | 40 | (5,7) | horizontal | right |
| purple_12 | small_car | purple | 16 | (8,6) | horizontal | right |
| pink_13 | bus | pink | 40 | (2,9) | vertical | up |
| red_14 | bus | red | 40 | (7,6) | horizontal | left |
| yellow_15 | medium_car | yellow | 24 | (4,3) | horizontal | right |
| green_16 | bus | green | 40 | (5,0) | horizontal | right |
| blue_17 | medium_car | blue | 24 | (10,7) | horizontal | right |

**Demanda por cor (capacidade somada dos veículos vs. passageiros na fila):**

| cor | capacidade somada | passageiros na fila |
|---|---|---|
| red | 80 | 80 |
| yellow | 88 | 88 |
| green | 96 | 96 |
| blue | 64 | 64 |
| orange | 56 | 56 |
| purple | 40 | 40 |
| pink | 56 | 56 |

Bate exatamente para todas as 7 cores (nenhuma sobra, nenhuma falta) — 480 no total. Isso é garantido estruturalmente por `LevelDefinition._normalized_passengers`, que corrige qualquer fila recebida para bater exatamente com a soma das capacidades; a hipótese D fica descartada com segurança para qualquer fase procedural, não só a 948.

## 3. Solvabilidade real — sequência vencedora

Rodando o `GameEngine` de verdade (nenhum atalho, nenhuma regra nova), a ordem direta de partida (a mesma ordem usada para montar o tabuleiro e a fila) **vence**:

```
red_0 → yellow_1 → green_2 → blue_3 → orange_4 → purple_5 → pink_6 → red_7 →
yellow_8 → green_9 → blue_10 → orange_11 → purple_12 → pink_13 → red_14 →
yellow_15 → green_16 → blue_17
```

18 movimentos, vitória confirmada (`GameState.status == WON`, fila de passageiros vazia). A fase **não é impossível**.

## 4. Fragilidade medida (200 partidas simuladas, fase 948, GameEngine real)

Estratégias definidas: a cada turno, dentre os veículos fisicamente livres para sair (`can_vehicle_exit`) e com vaga disponível, o "jogador" escolhe:

- **Guloso pela frente da fila**: prioriza qualquer veículo cuja cor bate com a cor na frente da fila; sem opção, escolhe ao acaso entre os livres.
- **80/20**: 80% das vezes escolhe um veículo que bate com a cor da frente (se houver); 20% escolhe ao acaso entre todos os livres.
- **70/30**: mesma lógica, 70%/30%.
- **Aleatória**: sempre ao acaso entre os veículos fisicamente livres.

| Estratégia | Vitórias/200 | Taxa | Movimentos médios até travar (derrotas) | Ocupação média das 4 vagas |
|---|---|---|---|---|
| Guloso pela frente | 172 | **86%** | 7,1 | 1,10 |
| 80% útil / 20% aleatório | 100 | **50%** | 7,7 | 1,52 |
| 70% útil / 30% aleatório | 76 | **38%** | 7,5 | 1,66 |
| Aleatória | 0 | **0%** | 4,8 | 2,38 |

**Critério do brief:** 80/20 deveria ter taxa alta de vitória e 70/30 margem razoável. Nenhuma das duas cumpre isso na fase 948 → **fase confirmadamente frágil demais** (hipótese B).

**Maior sequência de passageiros da mesma cor na fila:** 40 (um veículo de capacidade 40 gera um bloco contíguo de 40 passageiros da mesma cor).

### Diagnóstico do deadlock típico

Nas partidas perdidas, o padrão é sempre o mesmo (capturado com o `GameEngine` real, não estimado): as **4 vagas de espera ficam ocupadas por veículos que não são a cor da frente da fila** — cada um esperando parcialmente cheio (ex.: `purple 8/24`, `blue 3/24`, `yellow 21/24`, `green 19/40`) — e o veículo que **precisa** sair (cor da frente da fila) continua no tabuleiro, fisicamente livre para sair, mas **sem vaga**. Isso confirma exatamente o sintoma relatado: GameOver com muitos veículos/passageiros ainda em tela.

## 5. Auditoria do `level_generator.gd`

- **Seed determinística por `level_number`:** confirmado (`rng.seed = level_number if rng_seed < 0 else rng_seed`), sem qualquer normalização/alteração — a mesma fase é sempre reproduzida.
- **Nenhum limite antigo ligado a `COLORS.size()`:** `vehicle_count = clampi(7 + int((n-6)/2.4), 6, 18)` — o teto é `18`, fixo, independente de `COLORS.size()` (7). O comentário no código já documenta a decisão consciente de repetir a paleta embaralhada quando `vehicle_count > 7` (fases densas). Confirmado: **não há regressão nem limite residual aqui.**
- **Validação de solvabilidade na geração (`_validate_solvable`):** já existia e reproduz a solução canônica inteira com o `GameEngine` real antes de aceitar qualquer fase — isto é o que garante que nenhuma fase gerada seja impossível (hipótese C sempre descartada por construção, confirmado também empiricamente na amostra da Seção 7).
- **Causa raiz da fragilidade (validada por medição, não suposição):** a combinação de (a) capacidades de veículo grandes (16/24/40, vindas de `VehicleCapacityTable`, que **já está** conectada ao `LevelGenerator` — não é código morto como o comentário do arquivo sugere), (b) apenas 4 vagas de espera, e (c) alta liberdade física de movimento: medi uma média de **7,1 veículos simultaneamente livres para sair** a qualquer momento (chegando a 12 de 18) durante uma partida 80/20 na fase 948. Isso dá ao jogador muitas oportunidades "plausíveis" de estacionar um veículo que não é o necessário no momento — e, como cada veículo carrega até 40 passageiros de uma cor só, um veículo estacionado "errado" ocupa uma vaga por muito tempo até sua cor voltar à frente da fila. Com apenas 4 vagas, bastam 4 escolhas assim para travar o jogo mesmo com tabuleiro e fila corretos.

## 6. Correção tentada na `passenger_queue` — resultado negativo (documentado, não aplicado)

A hipótese do brief (Seção 8 do pedido) era que os blocos rígidos de uma cor só (do tamanho da capacidade do veículo) na fila fossem a causa da fragilidade, e que intercalar 2–4 cores em janelas curtas (como a fase 950 manual) resolveria.

**Implementei e testei rigorosamente** essa correção (`_build_passenger_queue`, substituindo o bloco contíguo por veículo por uma intercalação em janela deslizante, com `_validate_solvable` trocado por uma busca com backtracking e orçamento de nós, já que a ordem canônica direta deixa de ser a única prova possível quando a fila é intercalada). Resultado:

| Configuração da fila (fase 948) | Maior sequência de 1 cor | Guloso p/ frente | 80/20 | 70/30 |
|---|---|---|---|---|
| **Original (blocos contíguos por veículo)** | 40 | 86% | 50% | 38% |
| Janela=4, blocos de 2–4 | 19 (cauda) | 2,5% | 1% | 0% |
| Janela=2, blocos de 6–10 | 10 | 28,5% | 19,5% | 12,5% |
| Janela=2, blocos de 15–20 | 20 | 29% | 19,5% | 12% |
| Janela=2, blocos de 30–40 (quase sem intercalar) | 38 | 60,5% | 30,5% | 23% |

Em **todas** as configurações testadas, intercalar cores piorou a robustez em vez de melhorar, mesmo mantendo a fase solucionável pela ordem canônica (validado a cada tentativa com o `GameEngine` real). O padrão é consistente com a causa raiz da Seção 5: fragmentar a demanda de um veículo em múltiplas aparições não-contíguas na fila faz esse veículo passar **mais tempo total** ocupando uma vaga (precisa de vários "retornos" da sua cor à frente da fila, não um só), o que piora exatamente o gargalo real (poucas vagas, veículos de capacidade grande) em vez de aliviá-lo.

**Por isso a correção foi revertida.** `scripts/core/level_generator.gd` está devolvido ao estado original, sem diffs. Aplicar essa intercalação em produção pioraria a experiência, não melhoraria — não é uma correção que eu poderia entregar de boa fé apesar de ser a solução mais intuitiva pedida no brief.

### Recomendação para uma etapa futura (não implementada aqui)

Os dados apontam o alavanca real para a Seção 7 do roadmap de preferências do brief — "melhorar ordem/posicionamento dos bloqueios" —, não a fila nem a escolha de cores:

- A escolha de cores (`_shuffled(COLORS, rng)` repetida ciclicamente a cada 7 veículos) não é a causa: veículos da mesma cor ficam ~7 índices afastados na ordem de partida, ou seja, o primeiro já teria saído havia muito tempo quando o segundo aparece em jogo real.
- O alavanca com sinal mais forte nos dados é a **alta liberdade física simultânea** (7,1 em média, até 12 veículos livres ao mesmo tempo). Reduzir isso exigiria tornar o algoritmo de posicionamento (`_place_vehicle`/ordem reversa) mais "encadeado" — ou seja, aumentar a densidade de bloqueios físicos entre veículos vizinhos na ordem de partida, para que menos veículos fiquem "prematuramente" livres para sair ao mesmo tempo — sem quebrar a garantia matemática de que a ordem direta sempre vence.
- Essa é uma mudança mais estrutural (mexe no algoritmo de colocação, não só na fila) e merece sua própria rodada de validação dedicada (200+ simulações por configuração, como fiz aqui), por isso não a implementei nesta auditoria — o escopo pedido era auditar e, se a correção óbvia (fila) não se sustentasse, reportar honestamente em vez de aplicar uma mudança maior sem validação equivalente.

## 7. Fases de amostra (6, 10, 20, 50, 100, 250, 500, 948) — generator original

100 partidas simuladas por estratégia, por fase, usando o `GameEngine` real:

| Fase | Veículos | Tabuleiro | Densidade | Passageiros | Maior seq. 1 cor | 80/20 | 70/30 | Solvável? |
|---|---|---|---|---|---|---|---|---|
| 6 | 7 | 9×8 | 0,10 | 112 | 16 | 100% | 98% | Sim |
| 10 | 8 | 9×8 | 0,11 | 144 | 24 | 100% | 97% | Sim |
| 20 | 12 | 11×9 | 0,12 | 296 | 40 | 89% | 69% | Sim |
| 50 | 18 | 12×10 | 0,15 | 464 | 40 | 25% | 22% | Sim |
| 100 | 18 | 12×10 | 0,15 | 552 | 40 | 43% | 26% | Sim |
| 250 | 18 | 12×10 | 0,15 | 528 | 40 | 39% | 31% | Sim |
| 500 | 18 | 12×10 | 0,15 | 496 | 40 | 51% | 29% | Sim |
| 948 | 18 | 12×10 | 0,15 | 480 | 40 | 56%¹ | 43%¹ | Sim |

¹ Percentual da amostra de 100 partidas (Seção 7); a medição dedicada de 200 partidas da fase 948 está na Seção 4.

**Padrão claro:** todas as fases testadas são solucionáveis (nenhuma impossível), mas a robustez despenca assim que `vehicle_count` chega a 18 (a partir da fase ~20+): de ~90-100% de vitória com 7-12 veículos para 25-56% com 18. Isso confirma que a fragilidade não é peculiaridade da fase 948 — é sistêmica em qualquer fase procedural com o teto atual de veículos.

## 8. Maior sequência de mesma cor — resumo

Todas as fases com 18 veículos (a partir de ~fase 20) atingem o teto de maior sequência = **40** (um veículo `bus` sozinho). Fases menores (6, 10) já chegam a 16–24 (um `small_car`/`medium_car` sozinho). Isso é inerente a `VehicleCapacityTable` (16/24/40 por tipo) combinado com blocos contíguos por veículo — não uma anomalia da fase 948.

## 9. Custo computacional da validação

- Checagem original (`_validate_solvable`, ordem canônica): O(nº de veículos) — trivial, não mede na prática (< 1ms).
- Busca com backtracking implementada para validar a fila intercalada (Seção 6): 20.000 nós de orçamento; quando acionada, tipicamente resolvia ou desistia em 100ms–3s por tentativa de fase. Como a correção foi revertida, essa busca **não está em produção** — a validação em uso continua sendo a original O(n), sem impacto de performance na geração de fases.

## 10. Arquivos alterados

**Nenhum arquivo de produção foi alterado.** `scripts/core/level_generator.gd` foi modificado durante a investigação (duas versões experimentais da fila de passageiros) e **revertido ao estado original** após a validação mostrar regressão de robustez (Seção 6) — `git status` confirma zero diffs nesse arquivo ao final desta auditoria.

O ferramental de auditoria (script Godot headless para reproduzir fases, rodar as simulações e medir robustez) foi usado localmente durante a investigação e removido do projeto ao final (não fica nenhum arquivo extra em `tests/`). Se for útil manter esse ferramental para auditorias futuras (Etapa 17: regressão, ou para testar a correção estrutural recomendada na Seção 6), posso recriá-lo como uma suíte de teste permanente — não fiz isso agora para não deixar artefatos não solicitados no repositório.

---

## Conclusão

A fase 948 é **solucionável, não impossível** — mas **genuinamente frágil**, e essa fragilidade é **sistêmica** em qualquer fase procedural com 18 veículos (a partir de ~fase 20), não uma peculiaridade isolada. A causa raiz medida é a combinação de capacidades de veículo grandes (16–40) com apenas 4 vagas de espera e alta liberdade física simultânea de movimento (~7 veículos livres ao mesmo tempo, em média). A correção mais intuitiva (intercalar cores na fila) foi implementada, testada com rigor e **descartada por piorar os números** — um resultado negativo real, não uma suposição. A alavanca com sinal mais forte para uma correção futura é a densidade de bloqueios físicos no algoritmo de posicionamento, fora do escopo desta etapa.

Conforme solicitado, **parando aqui** — Etapa 10 não foi iniciada.
