# ENTREGA — Etapa 9C: Robustez do LevelGenerator pelo controle de veículos livres

## 0. Resultado em uma frase

**A mudança foi revertida.** Testei três variantes de um algoritmo de posicionamento com viés de bloqueio geométrico + geração-e-pontuação de múltiplos candidatos. Todas as três melhoram a robustez **média** da amostra, mas nenhuma melhora a fase 948 (o alvo original do bug) de forma **significativa e confiável** — em duas das três variantes ela piora ou fica estatisticamente igual, e a variante em que melhora causa regressão forte em outro nível de dificuldade equivalente (fase 500). Isso viola o critério de aceitação nº4 do item 26. Por instrução explícita ("se a mudança não cumprir: REVERTER e reportar"), `scripts/core/level_generator.gd` foi restaurado ao estado exato do checkpoint anterior (commit `b88a6c2`), confirmado por `git diff` vazio.

---

## 1. O que foi tentado (algoritmo novo)

### 1.1 Algoritmo antigo (pristine, ponto de partida)

`_try_generate` monta os veículos em ordem **reversa** de índice e, para cada um, `_place_vehicle` aceita a **primeira** posição aleatória (até 60 tentativas) cujo próprio footprint e caminho de saída estejam livres das células já ocupadas pelos veículos posicionados antes dele (i.e., que partem depois, na ordem direta). Isso garante matematicamente que a ordem direta de partida sempre resolve a fase — mas, como a Etapa 9B mediu, aceitar a *primeira* posição válida raramente cria cadeias de bloqueio reais: em média ~7 de 18 veículos ficavam livres para sair ao mesmo tempo (pico de 12), contra só 4 vagas de espera.

### 1.2 Causa (herdada do diagnóstico da Etapa 9B)

Com tantos veículos simultaneamente livres, um jogador subótimo pode estacionar um veículo de cor "errada" (fora da cor da frente da fila) e ocupar uma das 4 vagas por muito tempo (capacidades de até 40 passageiros), esperando sua cor voltar ao topo da fila — sem alternativa física de progresso enquanto isso. A Etapa 9C tentou reduzir essa liberdade simultânea via **topologia de posicionamento**, sem tocar a fila de passageiros, o GameEngine ou o board visual.

### 1.3 Algoritmo novo

- `_place_vehicle` agora coleta até `MAX_CANDIDATES_PER_VEHICLE` posições fisicamente válidas (em vez de aceitar a primeira) e guarda, para cada uma, quantos caminhos de saída de veículos **já colocados** (que partem depois, na ordem direta) ela intersecta (`_count_blocked_paths`).
- `_choose_placement` prefere posições que bloqueiam 1–2 veículos já colocados ("sweet spot"); na ausência dessas, aceita qualquer bloqueio; na ausência de qualquer bloqueio, aceita uma posição livre (esperado para os primeiros veículos colocados, quando ainda não há nada para bloquear). O bloqueio nasce inteiramente de geometria real (footprint/posição/`exit_direction`) — nenhuma flag artificial; o `GameEngine.can_vehicle_exit` continua descobrindo sozinho se um veículo pode sair.
- `generate()` passou a gerar **vários candidatos completos de fase** (até `MAX_LEVEL_ATTEMPTS`, mais uma segunda rodada com folga extra de tabuleiro) e pontuar cada um via `_score_candidate`, retornando o de melhor pontuação — sempre exigindo solvabilidade real pelo `GameEngine` antes de aceitar qualquer candidato (nunca aceita um candidato inválido por causa da pontuação).

### 1.4 Fórmula de pontuação (`_score_candidate`)

Soma simples e documentada de termos (não é ML):

```
score  = 100                                   # solucionável (só chega aqui se venceu)
       + banda(veículos_livres_iniciais)       # até 20 pts
       + banda(veículos_livres_médios)         # até 20 pts
       + (20 se ≥1 veículo produtivo no passo 0, senão −50)
       + (15 se média de veículos produtivos ao longo de toda a solução ≥ 1,
          senão penalidade proporcional ao déficit)  # refinamento v2/v3
       − penalidade se pico de veículos livres > banda_max + 4
```

"Produtivo" = veículo fisicamente livre cuja cor aparece nos próximos `PRODUCTIVE_WINDOW=60` passageiros da fila. Banda-alvo por porte: ≤8 veículos → [2,4]; ≤14 → [3,5]; >14 → [3,6] (conforme itens 3 e 14 do briefing). `GOOD_ENOUGH_SCORE=150` permite aceitar um candidato assim que ele atinge esse patamar, sem esgotar o orçamento de tentativas.

### 1.5 Três variantes testadas

| Variante | `MAX_LEVEL_ATTEMPTS` / `MAX_CANDIDATES_PER_VEHICLE` | Termo "produtivo médio" (ao longo de toda a solução) |
|---|---|---|
| **V1** | 25 / 15 | não |
| **V2** | 40 / 20 | sim |
| **V3** | 25 / 15 (mesmo orçamento de V1) | sim |

V3 isola exatamente o efeito do termo "produtivo médio" (mesmo orçamento de busca que V1); V2 soma esse termo a uma busca mais ampla.

### 1.6 Custo de geração (medido, não estimado)

Instrumentei temporariamente `generate()` para contar tentativas por fase (variante V2, a mais ampla testada) e medi tempo de parede via `Time.get_ticks_usec()`:

| Fase | Tentativas usadas até aceitar | Tempo (algoritmo antigo) | Tempo (V2) |
|---|---|---|---|
| 6 | 1 | 1.6 ms | 1.4 ms |
| 10 | 1 | 1.9 ms | 1.8 ms |
| 20 | 2 | 3.7 ms | 3.8 ms |
| 50 | 2 | 6.7 ms | 6.1 ms |
| 100 | 3 | 7.0 ms | 6.2 ms |
| 250 | 1 | 6.8 ms | 9.6 ms |
| 500 | 2 | 7.8 ms | 6.8 ms |
| 948 | 1 | 7.0 ms | 8.3 ms |

O `GOOD_ENOUGH_SCORE=150` faz a maioria das fases aceitarem em 1–3 tentativas (bem dentro do orçamento de 10–30 sugerido no item 15); custo por fase permanece da ordem de milissegundos, comparável ao algoritmo antigo. **O custo nunca foi o problema** — o problema foi a confiabilidade do resultado, descrito abaixo.

---

## 2. Antes/depois — as 8 fases de amostra, três variantes

Todas as fases seguem **solvíveis** (`solvable=true`), **sem overlap** e **sem out-of-bounds** em todas as variantes — os critérios físicos/estruturais nunca falharam. `n_vehicles` idêntico ao original em todas as fases (6,7,8,12,18,18,18,18 → escala de dificuldade preservada).

### Veículos livres (simultaneamente exitáveis)

| Fase | init/avg/pico ANTES | init/avg/pico V1 | init/avg/pico V2 | init/avg/pico V3 |
|---|---|---|---|---|
| 6 | 7 / 4.00 / 7 | 4 / 2.71 / 4 | 4 / 2.57 / 4 | 4 / 2.71 / 4 |
| 10 | 7 / 4.12 / 7 | 3 / 2.12 / 3 | 5 / 2.75 / 5 | 3 / 2.12 / 3 |
| 20 | 11 / 6.17 / 11 | 8 / 4.08 / 8 | 7 / 3.33 / 7 | 8 / 4.08 / 8 |
| 50 | 12 / 7.22 / 12 | 7 / 3.72 / 7 | 11 / 6.17 / 11 | 10 / 5.61 / 10 |
| 100 | 13 / 7.67 / 13 | 8 / 4.22 / 8 | 11 / 5.17 / 11 | 10 / 5.67 / 10 |
| 250 | 12 / 7.72 / 12 | 7 / 4.44 / 7 | 7 / 4.83 / 7 | 10 / 5.33 / 10 |
| 500 | 10 / 7.22 / 11 | 7 / 4.17 / 8 | 10 / 5.89 / 10 | 12 / 6.67 / 12 |
| **948** | **12 / 6.28 / 12** | **8 / 5.61 / 9** | **11 / 5.56 / 11** | **8 / 5.61 / 9** |

Em todas as variantes, a liberdade simultânea de veículos caiu de forma consistente e mensurável — a mudança de topologia **funciona como pretendido no nível físico**.

### Taxas de vitória estocásticas (150 execuções por estratégia)

| Fase | 80/20 ANTES | V1 | V2 | V3 | 70/30 ANTES | V1 | V2 | V3 |
|---|---|---|---|---|---|---|---|---|
| 6 | 1.000 | 1.000 | 1.000 | 1.000 | 0.967 | 1.000 | 1.000 | 1.000 |
| 10 | 1.000 | 1.000 | 0.993 | 1.000 | 0.953 | 1.000 | 0.987 | 1.000 |
| 20 | 0.893 | 0.953 | 0.967 | 0.953 | 0.720 | 0.853 | 0.847 | 0.853 |
| 50 | 0.240 | **0.707** | 0.187 | 0.173 | 0.220 | **0.747** | 0.147 | 0.147 |
| 100 | 0.447 | **0.880** | 0.540 | 0.167 | 0.273 | **0.780** | 0.360 | 0.140 |
| 250 | 0.427 | 0.467 | **0.973** | 0.880 | 0.280 | 0.460 | **0.827** | 0.707 |
| 500 | 0.467 | 0.340 | 0.253 | **0.793** | 0.313 | 0.247 | 0.193 | **0.533** |
| **948** | **0.507** | 0.440 | 0.607 | 0.440 | **0.427** | 0.360 | 0.440 | 0.360 |
| **Média (8 fases)** | **0.623** | **0.723** | **0.690** | **0.676** | **0.519** | **0.681** | **0.600** | **0.593** |

---

## 3. Por que isso não passa no critério de aceitação (item 26.4)

A **média** das 8 fases melhora em todas as três variantes (80/20: +10 a +16 p.p.; 70/30: +7 a +16 p.p.) — o item 26.3 é satisfeito. Mas o item 26.4 exige que **a fase 948 especificamente** melhore de forma significativa, e isso não se sustenta:

- **V1**: 948 piora (0.507→0.440 no 80/20; 0.427→0.360 no 70/30).
- **V2**: 948 melhora no 80/20 (0.507→0.607, ganho real de ~10 p.p., acima do ruído estatístico de ±4 p.p. para n=150), mas fica **estatisticamente igual** no 70/30 (0.427→0.440, dentro do ruído). Ao mesmo tempo, a fase 500 — mesmo porte (18 veículos), mesma banda-alvo — **piora fortemente** (0.467→0.253 no 80/20, uma queda de 21 p.p.).
- **V3** (isolando o termo "produtivo médio" do orçamento de busca ampliado): 948 fica **idêntica a V1** (0.440/0.360) — ou seja, o termo de pontuação sozinho não mudou nada para esta fase; quem mudou o resultado em V2 foi a busca mais ampla, não a fórmula de pontuação. E V3 quebra a fase 100 (0.447→0.167) para "consertar" a fase 500.

O padrão que emerge across as três variantes é de **"tira-daqui-põe-ali"**: cada ajuste na fórmula/orçamento de busca reordena qual candidato "vence" a pontuação para cada fase, e essa reordenação tem uma relação fraca e inconsistente com a taxa de vitória real contra jogo subótimo. Nenhuma configuração testada melhora a fase 948 de forma clara e robusta **sem** causar regressão forte em outra fase do mesmo porte. Isso é, mecanicamente, o mesmo tipo de resultado frágil que a Etapa 9B já havia encontrado com a intercalação de fila (uma mudança que ajuda "na média" mas não é confiável fase a fase) — só que desta vez pelo lado da topologia em vez da fila.

Diagnóstico provável: `free_counts`/`productive_counts` medidos sobre a única solução canônica (ordem direta) são um proxy barato mas **imperfeito** da robustez real contra estratégias estocásticas — a pontuação não "vê" as jogadas específicas que um jogador 70/30 ou 80/20 faria, só a contagem de opções físicas disponíveis. Duas fases com o mesmo `avg_free`/`peak_free` podem ter taxas de vitória muito diferentes dependendo de *quais* veículos (e cores) ficam livres em cada momento relativo à fila real — algo que o termo "produtivo" tenta capturar, mas só parcialmente.

---

## 4. Verificações de segurança (todas passaram, independentemente da decisão de reverter)

- **Zero overlap / zero out-of-bounds**: confirmado nas 8 fases de amostra em todas as variantes testadas.
- **Escala de dificuldade preservada**: `n_vehicles` idêntico ao original em todas as fases (nenhuma redução de contagem de veículos).
- **Nenhuma flag artificial**: o bloqueio nasce só de geometria (footprint × caminho de saída já ocupado); `GameEngine.can_vehicle_exit` nunca foi tocado e continua sendo a única fonte de verdade sobre se um veículo pode sair.
- **`GameEngine`/`GameState`**: `git diff --stat -- scripts/core/game_engine.gd scripts/core/game_state.gd` retorna vazio — zero alterações, confirmado antes e depois de cada experimento.
- **JSON de fases**: `git status`/`git diff` confirmam `levels/level_001..005.json`, `level_900.json` e `level_950.json` intocados durante toda a Etapa 9C.
- **Nenhum cap residual de `COLORS.size()`**: reconfirmado — `vehicle_count` vem só de `clampi(7 + int((n-6)/2.4), 6, 18)`, sem relação com o tamanho da paleta de cores (7).
- **Testes pré-existentes**: `tests/test_game_core.gd` continua com as mesmas 3 falhas de asserção já documentadas na Etapa 9B (`_test_create_state_from_level`, `_test_no_slot_available`, `_test_full_slots_without_front_color_is_game_over`) — nenhuma falha nova foi introduzida (o arquivo final é bit-idêntico ao checkpoint anterior, então isso é garantido por construção, e foi reconfirmado rodando a suíte).
- **Presentation/board visual/câmera/docks/HUD/animações**: nenhum desses arquivos foi tocado em nenhum momento desta etapa.

---

## 5. Decisão final

`scripts/core/level_generator.gd` foi restaurado via `git checkout` ao estado do commit `b88a6c2` (checkpoint pré-Etapa 9C, que já continha só a ferramenta de auditoria `tests/audit9c/runner.gd` da Etapa 9C-A). `git diff --stat` confirma **zero diferença** em relação a esse checkpoint. Nenhum código de produção foi alterado ao final desta etapa.

Mantidos como evidência (não fazem parte do jogo, não são carregados em runtime): `tests/audit9c/before_sample.json`, `after_sample.json` (V1), `after_sample_v2.json` (V2), `after_sample_v3.json` (V3), `smoke_948.json` — as medições brutas por trás das tabelas acima.

## 6. Recomendação para trabalho futuro

O mecanismo de viés de bloqueio geométrico é fisicamente correto e barato (custo de geração inalterado, poucos ms por fase), e melhora a robustez **média** de forma consistente nas três variantes — não é um beco sem saída, mas também não está pronto para produção como está. Dois caminhos plausíveis para uma etapa futura, nenhum implementado aqui por estarem fora do escopo autorizado desta etapa:

1. Aceitar um número pequeno e limitado de simulações estocásticas *dentro* do próprio gerador (ex.: 3–5 jogadas simuladas com uma mistura 80/20 fixa, reaproveitando as mesmas chamadas de `GameEngine` já usadas em `_evaluate_candidate`) como termo adicional de pontuação — isso exigiria relaxar a restrição do item 15 ("nunca rodar simulação pesada no gerador real"), já que mesmo um número pequeno de simulações é qualitativamente diferente de uma única passagem determinística.
2. Investigar por que a mesma fórmula/orçamento ajuda certas fases (250, 100) e prejudica outras do mesmo porte (500, 948) — possivelmente relacionado à disposição específica de cores na paleta embaralhada (`_shuffled`) de cada fase, e não à topologia em si.

---

## 7. Encerramento

Conforme instruído, a Etapa 9C termina aqui. Nenhuma alteração de produção foi mantida; nenhum trabalho da Etapa 10 foi iniciado; nenhum arquivo de personagens/carros/assets foi tocado.
