class_name Music
extends Node
## 背景音樂：換場景時兩軌交叉淡入淡出；過關小樂句播的時候背景音樂先壓小聲。
## 音樂檔在 res://audio/music/<名字>.ogg（tools/music/compose.py 寫譜，FluidSynth＋GeneralUser GS 播成音檔）

const VOLUME_DB := -9.0
const SILENT_DB := -60.0

var enabled := true
var current := ""
var _a: AudioStreamPlayer
var _b: AudioStreamPlayer
var _jingle: AudioStreamPlayer
var _tw: Tween


func _ready() -> void:
	_a = _player()
	_b = _player()
	_jingle = _player()
	_jingle.volume_db = VOLUME_DB + 2.0


func _player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = SILENT_DB
	add_child(p)
	return p


static func _stream(track: String, loop: bool) -> AudioStream:
	var path := "res://audio/music/%s.ogg" % track
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = loop
	return s


## 換背景音樂（同一首就不重播）；track = home / town / task
func play(track: String) -> void:
	if track == current:
		return
	current = track
	if not enabled:
		return
	_crossfade(_stream(track, true))


func _crossfade(s: AudioStream) -> void:
	if _tw:
		_tw.kill()
	var old := _a
	var nw := _b
	_a = nw
	_b = old
	if not old.playing and s == null:
		return
	_tw = create_tween().set_parallel()
	if old.playing:
		_tw.tween_property(old, "volume_db", SILENT_DB, 1.5)
		_tw.chain().tween_callback(old.stop)
	if s != null:
		nw.stream = s
		nw.volume_db = SILENT_DB
		nw.play()
		_tw.tween_property(nw, "volume_db", VOLUME_DB, 2.0)


## 過關的小樂句：背景音樂先壓小聲，播完再回來
func jingle(track: String = "clear") -> void:
	if not enabled:
		return
	var s := _stream(track, false)
	if s == null:
		return
	_jingle.stream = s
	_jingle.play()
	if _a.playing:
		var tw := create_tween()
		tw.tween_property(_a, "volume_db", VOLUME_DB - 14.0, 0.3)
		tw.tween_interval(maxf(s.get_length() - 0.8, 0.5))
		tw.tween_property(_a, "volume_db", VOLUME_DB, 1.5)


func set_enabled(on: bool) -> void:
	enabled = on
	if on:
		var t := current
		current = ""
		if t != "":
			play(t)
	else:
		if _tw:
			_tw.kill()
		for p in [_a, _b, _jingle]:
			p.stop()
