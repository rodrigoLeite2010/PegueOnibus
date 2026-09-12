class_name PolishPalette
extends RefCounted

# ETAPA 6 -- paleta coerente EXCLUSIVA da PolishTest (fase 950). Nenhuma fase
# normal referencia esta classe; board/slots/cenario/HUD normais continuam
# com as cores tecnicas originais de cada script. Centralizar aqui evita cor
# solta espalhada pelo codigo (pedido explicito do item 13 da Etapa 6):
# qualquer recalibragem de tom acontece SO nestas linhas.

# Fundo (WorldEnvironment.background_color / topo do ceu da cena polida).
const BACKGROUND := Color("#cfe7f8")
# Grama ao redor do patio (EnvironmentController).
const GRASS := Color("#a9dfa2")
# Piso principal do tabuleiro/estacionamento (BoardController).
const ASPHALT := Color("#7c90ac")
const ASPHALT_SHADOW := Color("#54637e")
# Superficie das 4 vagas ativas (azul escuro suave, pedido item 13).
const SLOT_SURFACE := Color("#2f3b57")
const SLOT_SURFACE_LOCKED := Color("#3a4051")
# Bordas/curb -- off-white, nunca branco puro (fica "tecnico" demais).
const BORDER := Color("#f4f1e8")
# Unica cor reservada para recompensa/destaque (moedas, "+10", brilho de
# vitoria) -- nunca usada em elementos neutros de cenario.
const ACCENT_YELLOW := Color("#ffd233")
