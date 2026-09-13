shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// ETAPA 10B: recolore SOMENTE a roupa principal do passageiro 3D
// (camiseta do passenger_01, moletom do passenger_02 -- ETAPA 10C
// generalizou os parametros abaixo para funcionar com qualquer modelo,
// ver passenger_visual_variants.gd).
//
// Por que um shader e nao um material/surface separado: a auditoria (ver
// ENTREGA_ETAPA_10B.md/ENTREGA_ETAPA_10C.md) confirmou que cada GLB tem UM
// UNICO MeshInstance3D, UMA UNICA surface e UM UNICO material
// ("tripo_mat_..."), com pele/cabelo/roupa/calca/tenis todos pintados na
// MESMA textura albedo (atlas de UV "explodido" tipico de auto-rig). Nao
// existe separacao por material/surface (Preferencia A do pedido nao se
// aplica aqui) -- entao a unica forma segura de mudar so a roupa, sem
// tocar o GLB original, e uma mascara calculada em tempo real dentro do
// proprio shader (Preferencia B).
//
// Como a mascara e calculada: a roupa original de cada modelo tem uma cor
// propria no atlas -- amarelo (~44 graus) no passenger_01, rosa (~339
// graus) no passenger_02, cada um com seus proprios "shirt_hue*" (ver
// uniforms abaixo, preenchidos por Passenger3D.set_passenger_color() a
// partir do profile da variante). Convertemos cada pixel do albedo
// original para HSV e comparamos o MATIZ (H) dele com o da roupa original
// -- perto o bastante (dentro da faixa shirt_hue_full..shirt_hue_zero) e
// considerado "roupa" (mask -> 1); longe disso (pele, calca/tenis, cabelo)
// e considerado "resto do corpo" (mask -> 0) e nunca e alterado.
// shirt_sat_floor evita recolorir pixels quase cinza/brancos (reflexos de
// luz na propria roupa), que ficam como estao -- e exatamente isso que
// preserva o "brilho"/detalhe de tecido em vez de virar uma cor chapada.
//
// Como a cor final e aplicada (Passo 6 do pedido -- preservar
// sombra/textura): dentro da mascara, o pixel NAO vira a cor solida do
// passageiro. Em vez disso: pega-se o MATIZ e a SATURACAO da cor logica do
// passageiro, mas mantem-se o VALOR (V do HSV, ou seja, o brilho/sombra que
// ja estava pintado na textura). O resultado e a mesma dobra/sombra da
// camiseta original, so que na cor nova -- nunca uma cor chapada sem
// volume.
//
// Normal map e o ORM (roughness=G/metallic=B, packing padrao glTF, ver
// auditoria) passam directo, sem nenhuma alteracao -- luz/sombra/brilho da
// pele, cabelo, calca e tenis ficam bit a bit identicos ao material
// original importado.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
// Cor logica do passageiro (PassengerController.COLOR_MAP). Default = o
// amarelo original do GLB, para nunca ficar "sem cor" antes do primeiro
// set_passenger_color().
uniform vec3 tint_color : source_color = vec3(1.0, 0.8235, 0.2118);

// ETAPA 10C: os 4 parametros da mascara viraram uniform (eram const) --
// cada modelo (passenger_01, passenger_02, ...) tem a roupa principal
// numa cor/matiz diferente no atlas original, entao a faixa que define
// "isto e a roupa a recolorir" precisa ser configuravel por instancia.
// Passenger3D.set_passenger_color() preenche estes 4 valores a partir do
// PassengerVisualVariants.PROFILES da variante escolhida (ver
// passenger_visual_variants.gd) -- nunca reaproveita o valor de outro
// modelo. Os defaults abaixo sao os do passenger_01 (matiz ~44 graus,
// camiseta amarela original), so como fallback caso o material seja usado
// sem configuracao explicita.
uniform float shirt_hue : hint_range(0.0, 1.0) = 0.1211;
uniform float shirt_hue_full : hint_range(0.0, 0.25) = 0.028;
uniform float shirt_hue_zero : hint_range(0.0, 0.25) = 0.050;
uniform float shirt_sat_floor : hint_range(0.0, 1.0) = 0.25;

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec4 k = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + k.xyz) * 6.0 - k.www);
	return c.z * mix(k.xxx, clamp(p - k.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec3 hsv = rgb2hsv(tex.rgb);

	float dist = abs(hsv.x - shirt_hue);
	dist = min(dist, 1.0 - dist); // distancia circular de matiz (0..0.5)
	float hue_mask = 1.0 - smoothstep(shirt_hue_full, shirt_hue_zero, dist);
	float sat_mask = smoothstep(0.0, shirt_sat_floor, hsv.y);
	float mask = hue_mask * sat_mask;

	vec3 tint_hsv = rgb2hsv(tint_color);
	vec3 recolored = hsv2rgb(vec3(tint_hsv.x, tint_hsv.y, hsv.z));

	ALBEDO = mix(tex.rgb, recolored, mask);
	ALPHA = tex.a;

	NORMAL_MAP = texture(normal_texture, UV).rgb;
	vec4 orm = texture(orm_texture, UV);
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
}
