# Integração do primeiro carro 3D — v1

Objetivo desta etapa: provar o pipeline GLB -> VehicleController sem alterar regras do GameEngine.

## O que mudou

- `CarSmall.tscn` foi limpo: removido o override acidental de uma peça interna do GLB.
- `BoardingPoint` e `SelectionPoint` foram preservados.
- O recurso visual vermelho agora usa `CarSmall.tscn` como `model_scene`.
- O modelo recebe escala própria (`model_scale = 2.9`) e pequeno ajuste de altura.
- `VehicleController` agora conhece `orientation` e gira o GLB 90 graus quando o veículo é horizontal.
- `get_boarding_point()` usa o Marker3D real do modelo quando existir.
- `VehicleVisualLibrary` ganhou resolução por `type + color`, preparando o projeto para carro/van/ônibus diferentes da mesma cor.

## Escopo proposital

Nesta entrega somente o **carro vermelho** usa o GLB. Os demais veículos continuam com o visual atual. Isso permite comparar, medir desempenho e corrigir escala/orientação antes de replicar o pipeline.

## Teste recomendado

1. Abrir o projeto no Godot 4.7.2.
2. Rodar a Fase 5.
3. Confirmar que o `red_car` aparece como GLB 3D.
4. Conferir se veículos vermelhos horizontais (fases 1 e 3) giram corretamente.
5. Tocar no carro vermelho e verificar: bounce, rota até slot, passageiro chegando ao `BoardingPoint`, saída ao completar.
6. Se o carro parecer grande/pequeno, ajustar somente `model_scale` em `resources/vehicle_types/red.tres`.

## Observação mobile

O GLB de teste é pesado e detalhado. Ele serve para validar o pipeline, não como asset final de produção. Depois do fluxo aprovado, substituir por um modelo toy-like otimizado mantendo `CarSmall.tscn`/Markers e sem alterar o GameEngine.
