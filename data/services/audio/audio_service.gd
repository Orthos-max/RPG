extends Node
## Audio (autoload) — lecture des sons et musiques, réglages de volume.
##
## Le jeu n'a pas encore de fichiers audio. Ce service existe pour que l'arrivée
## des assets ne demande aucun recâblage : il écoute déjà [BattleRecorder] et
## joue le son que [SoundDB] associe à chaque événement. Tant qu'un fichier
## manque, l'appel est simplement silencieux — jamais une erreur, jamais un
## plantage — et [method missing_cues] dit lesquels restent à fournir.
##
## Trois bus sont créés au démarrage (SFX, Music, UI) sous Master, pour que le
## joueur puisse baisser la musique sans perdre les bruitages.

signal cue_played(key: String)
## Émis quand un son manque à l'appel (une fois par clé)
signal cue_missing(key: String)
signal volume_changed(bus: String, linear: float)

const SETTINGS_FILE: String = "user://settings.json"
## Nombre de lecteurs simultanés pour les bruitages
const SFX_VOICES: int = 8
## Durée du fondu entre deux musiques
const MUSIC_FADE: float = 0.8
## Volume minimal avant coupure franche (en linéaire)
const SILENCE_THRESHOLD: float = 0.001

## Volumes par bus, en linéaire (0.0 → 1.0)
var volumes: Dictionary = {
	"Master": 1.0,
	SoundDB.BUS_SFX: 1.0,
	SoundDB.BUS_MUSIC: 0.7,
	SoundDB.BUS_UI: 1.0,
}
## Musique en cours ("" si aucune)
var current_music: String = ""

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer = null
var _next_voice: int = 0
## Clés déjà signalées manquantes — on ne prévient qu'une fois par son
var _reported: Dictionary = {}
## Flux chargés, pour ne pas relire le disque à chaque coup d'épée
var _cache: Dictionary = {}


func _ready() -> void:
	_ensure_buses()
	_build_players()
	load_settings()

	# Une seule prise : le journal de bataille sait déjà tout ce qui se passe.
	var recorder: Node = get_node_or_null("/root/BattleRecorder")
	if recorder:
		recorder.event_recorded.connect(_on_battle_event)


#region Lecture
## Joue un son du catalogue. Sans fichier, l'appel ne fait rien (et le dit une fois).
func play(key: String) -> bool:
	if key.is_empty():
		return false
	if SoundDB.is_music(key):
		return play_music(key)

	var stream: AudioStream = _stream_for(key)
	if not stream:
		return false

	var entry: Dictionary = SoundDB.cue(key)
	var player: AudioStreamPlayer = _free_voice()
	player.stream = stream
	player.bus = str(entry.get("bus", SoundDB.BUS_SFX))
	player.volume_db = float(entry.get("volume_db", 0.0))
	player.pitch_scale = randf_range(
		float(entry.get("pitch_min", 1.0)), float(entry.get("pitch_max", 1.0))
	)
	player.play()
	cue_played.emit(key)
	return true


## Lance une musique en boucle, avec un fondu depuis la précédente.
func play_music(key: String) -> bool:
	if key == current_music:
		return true

	var stream: AudioStream = _stream_for(key)
	if not stream:
		# La musique demandée n'existe pas : on coupe plutôt que de laisser
		# tourner celle de l'écran précédent, qui n'a plus rien à voir.
		stop_music()
		return false

	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true

	current_music = key
	var entry: Dictionary = SoundDB.cue(key)
	_music_player.stream = stream
	_music_player.volume_db = float(entry.get("volume_db", -6.0))
	_music_player.play()
	cue_played.emit(key)
	return true


## Coupe la musique en cours.
func stop_music() -> void:
	current_music = ""
	if _music_player:
		_music_player.stop()
#endregion


#region Réglages
## Règle le volume d'un bus (0.0 → 1.0) et le retient.
func set_volume(bus: String, linear: float) -> void:
	var value: float = clampf(linear, 0.0, 1.0)
	volumes[bus] = value
	var index: int = AudioServer.get_bus_index(bus)
	if index != -1:
		AudioServer.set_bus_mute(index, value <= SILENCE_THRESHOLD)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, SILENCE_THRESHOLD)))
	volume_changed.emit(bus, value)


## Volume courant d'un bus.
func get_volume(bus: String) -> float:
	return float(volumes.get(bus, 1.0))


## Écrit les réglages dans `user://settings.json`.
func save_settings() -> bool:
	var f := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if not f:
		push_warning("[Audio] Réglages non enregistrés : %s illisible." % SETTINGS_FILE)
		return false
	f.store_string(JSON.stringify({"volumes": volumes}, "\t"))
	f.close()
	return true


## Relit les réglages (valeurs par défaut si le fichier est absent ou abîmé).
func load_settings() -> void:
	if FileAccess.file_exists(SETTINGS_FILE):
		var f := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
		if f:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary and parsed.has("volumes"):
				for bus: String in parsed["volumes"]:
					if volumes.has(bus):
						volumes[bus] = clampf(float(parsed["volumes"][bus]), 0.0, 1.0)

	for bus: String in volumes:
		set_volume(bus, float(volumes[bus]))
#endregion


#region Diagnostic
## Sons du catalogue dont le fichier n'existe pas encore.
##
## Sert à la fois de liste de courses pour les assets et de garde-fou : le jour
## où tout est fourni, elle doit être vide.
func missing_cues() -> Array[String]:
	var out: Array[String] = []
	for key: String in SoundDB.keys():
		if not ResourceLoader.exists(SoundDB.path_of(key)):
			out.append(key)
	return out


#endregion


#region Internes
## Crée les bus manquants sous Master (aucun `.tres` de layout à maintenir).
func _ensure_buses() -> void:
	for bus: String in [SoundDB.BUS_SFX, SoundDB.BUS_MUSIC, SoundDB.BUS_UI]:
		if AudioServer.get_bus_index(bus) != -1:
			continue
		var index: int = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, bus)
		AudioServer.set_bus_send(index, "Master")


func _build_players() -> void:
	for _i in SFX_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = SoundDB.BUS_SFX
		add_child(player)
		_sfx_players.append(player)

	_music_player = AudioStreamPlayer.new()
	_music_player.bus = SoundDB.BUS_MUSIC
	add_child(_music_player)


## Lecteur libre, ou le plus ancien si tous sont pris (tourniquet).
func _free_voice() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _sfx_players:
		if not player.playing:
			return player
	_next_voice = (_next_voice + 1) % _sfx_players.size()
	return _sfx_players[_next_voice]


## Charge (et retient) le flux d'un son ; null tant que le fichier n'existe pas.
func _stream_for(key: String) -> AudioStream:
	if _cache.has(key):
		return _cache[key]

	var path: String = SoundDB.path_of(key)
	if path.is_empty() or not ResourceLoader.exists(path):
		if not _reported.has(key):
			_reported[key] = true
			cue_missing.emit(key)
		return null

	var stream: AudioStream = load(path) as AudioStream
	_cache[key] = stream
	return stream


func _on_battle_event(event: Dictionary) -> void:
	play(SoundDB.cue_for_event(event))
#endregion
