class_name GameAudio
extends Node
## Central audio manager: a shuffled background-music playlist on the Music
## bus and a small pool of SFX players on the SFX bus. Created once by the
## app root; everything else calls the static helpers (GameAudio.sfx("...")),
## which are safe no-ops when the manager isn't in the tree (headless tests).
##
## NOTE: the four Suno tracks (and their "2" variants) are stylistically one
## ambient-folk family, so the playlist currently rotates ALL of them in both
## the menu and the game — Simon decides if any track should be context-bound.

static var _instance: GameAudio

const MUSIC := [
	"res://assets/audio/music/Dusk Village Table.mp3",
	"res://assets/audio/music/Dusk Village Table 2.mp3",
	"res://assets/audio/music/Dvor Večer.mp3",
	"res://assets/audio/music/Dvor Večer 2.mp3",
	"res://assets/audio/music/Fujara at Dusk.mp3",
	"res://assets/audio/music/Fujara at Dusk 2.mp3",
	"res://assets/audio/music/Moss on the Ridge.mp3",
	"res://assets/audio/music/Moss on the Ridge 2.mp3",
]

## key -> [path, max seconds (0 = play whole), volume dB offset]
const SFX := {
	"place_felt": ["res://assets/audio/sfx/Light_card_tap_on_gr_#1-1784055198728.wav", 0.0, 0.0],
	"place_wood": ["res://assets/audio/sfx/Card_tap_on_solid_wo_#1-1784055315612.wav", 0.7, 0.0],
	"slap": ["res://assets/audio/sfx/Playing_card_slapped_#2-1784055478431.wav", 0.0, 0.0],
	"slide": ["res://assets/audio/sfx/Playing_card_sliding_#4-1784055429882.wav", 0.0, -6.0],
	"pull": ["res://assets/audio/sfx/Single_playing_card__#1-1784055263357.wav", 0.0, -4.0],
	"flip": ["res://assets/audio/sfx/freesound_community-flipcard-91468.mp3", 0.0, 0.0],
	"shuffle": ["res://assets/audio/sfx/oxidvideos-shuffling-deck-of-cards-522518.mp3", 0.0, 0.0],
	"spalena1": ["res://assets/audio/sfx/spalena_part1.wav", 0.0, 0.0],
	"spalena2": ["res://assets/audio/sfx/spalena_part2.wav", 0.0, 0.0],
	"win": ["res://assets/audio/sfx/freesound_community-piglevelwin2mp3-14800.mp3", 0.0, 0.0],
	"lose": ["res://assets/audio/sfx/lose.mp3", 0.0, 0.0],
	"ui": ["res://assets/audio/sfx/ui_button_sounds.mp3", 0.0, -8.0],
}

const SFX_POOL_SIZE := 6

var _music_player: AudioStreamPlayer
var _sfx_players: Array[AudioStreamPlayer] = []
var _playlist: Array = []
var _streams := {}


func _ready() -> void:
	_instance = self
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.finished.connect(_play_next_track)
	add_child(_music_player)
	for _i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	for key in SFX:
		_streams[key] = load(SFX[key][0])
	_play_next_track()


func _play_next_track() -> void:
	if _playlist.is_empty():
		_playlist = MUSIC.duplicate()
		_playlist.shuffle()
	var stream: AudioStream = load(_playlist.pop_back())
	if stream != null:
		_music_player.stream = stream
		_music_player.play()


## Fire-and-forget sound effect by key; grabs a free pooled player.
static func sfx(key: String) -> void:
	var inst := _instance
	if inst == null or not is_instance_valid(inst) or not inst._streams.has(key):
		return
	for p in inst._sfx_players:
		if not p.playing:
			p.stream = inst._streams[key]
			p.volume_db = GameAudio.SFX[key][2]
			p.play()
			var max_len: float = GameAudio.SFX[key][1]
			if max_len > 0.0:
				# Some source files pack several takes; stop after the first.
				inst.get_tree().create_timer(max_len).timeout.connect(
						func():
							if p.stream == inst._streams[key]:
								p.stop(),
						CONNECT_ONE_SHOT)
			return


## The card-place sound matching the active table look (felt vs wood).
static func place_sfx() -> void:
	var look := TableLook.active().id
	if look.begins_with("felt") or look == "poker_green" or look == "felt_green":
		sfx("place_felt")
	else:
		sfx("place_wood")
