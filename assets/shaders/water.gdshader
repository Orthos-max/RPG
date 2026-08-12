// L'eau du plateau : la tuile du pack, poussée par deux courants.
//
// Une case d'eau rendue en `StandardMaterial3D` est une flaque gelée : le
// terrain le plus reconnaissable du jeu était le seul à ne rien faire. Aucune
// image n'est ajoutée ici — c'est la tuile SSCAP de l'eau, échantillonnée deux
// fois et glissée dans deux directions. Ce sont les deux nappes qui font
// l'onde : une seule qui dérive donnerait un tapis roulant.
//
// Les UV sont pris en coordonnées **monde**, comme la projection triplanaire du
// reste du terrain : le motif traverse les cases au lieu de recommencer sur
// chacune, et une mare de six cases se lit comme une seule étendue.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D tile : source_color, filter_nearest_mipmap, repeat_enable;
/// Trace de la teinte de terrain gardée sous la tuile (voir TEXTURE_TINT_STRENGTH).
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
/// Motifs par unité monde : 1.0 = une tuile par case.
uniform float pattern_scale = 1.0;
/// Dérive du courant, en unités monde par seconde. Volontairement lente : à
/// la caméra tactique, l'œil suit un courant rapide au lieu de lire la carte.
uniform float speed = 0.035;
/// Amplitude du roulis qui empêche les deux nappes de glisser en ligne droite.
uniform float sway = 0.012;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.18;
uniform float surface_metallic : hint_range(0.0, 1.0) = 0.25;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_position.xz * pattern_scale;

	// Ni la même vitesse, ni le même sens : c'est leur battement qui fait l'onde.
	vec2 drift_near = vec2(TIME * speed, TIME * speed * 0.42);
	vec2 drift_far = vec2(TIME * -speed * 0.63, TIME * speed * 0.29);
	vec2 wobble = vec2(sin(uv.y * 3.0 + TIME * 0.6), cos(uv.x * 3.0 + TIME * 0.5)) * sway;

	vec3 near = texture(tile, uv + drift_near + wobble).rgb;
	vec3 far = texture(tile, uv * 1.07 + drift_far - wobble).rgb;

	ALBEDO = mix(near, far, 0.45) * tint.rgb;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
}
