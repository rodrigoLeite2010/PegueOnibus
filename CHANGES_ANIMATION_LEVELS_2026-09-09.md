# Alteracoes - animacoes e progressao

- Veiculos agora saem do tabuleiro, contornam a borda e vao ate uma vaga fisica de embarque.
- Veiculos parcialmente cheios permanecem visiveis na vaga; nao somem imediatamente.
- Passageiros 3D aparecem em fila, caminham ate o veiculo e encolhem ao entrar.
- Veiculo recebe bounce curto a cada embarque e, quando lota, acelera para fora da cena.
- HUD so e atualizado apos a animacao para evitar que a fila desapareca antes do embarque visual.
- Vitoria agora exibe botao "Proxima fase"; derrota exibe "Tentar novamente".
- Foram adicionadas fases level_002.json ate level_005.json.
- Progresso da fase atual e salvo em user://progress.cfg.
- Camera ganhou margem adicional para os PNGs 3/4 atuais nao serem cortados nas laterais.
- Posicoes das fases foram afastadas das bordas para reduzir estouro visual dos sprites enquanto os GLBs finais nao chegam.
