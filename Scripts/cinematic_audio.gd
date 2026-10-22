extends RefCounted
static var cache: Dictionary = {}
const RATE := 22050
static func score(chapter: int) -> AudioStreamWAV:
	if cache.has(chapter): return cache[chapter]
	var seconds := 8.0
	var count: int = int(RATE*seconds)
	var data := PackedByteArray()
	data.resize(count*2)
	var random := RandomNumberGenerator.new()
	random.seed = 7124+chapter
	var low: float = 0
	for i in range(count):
		var t: float = float(i)/RATE
		var noise: float = random.randf_range(-1,1)
		low = lerpf(low,noise,.025)
		var pulse: float = exp(-fmod(t,1.2)*13)
		var frequency: float = [43.65,36.71,49.0,55.0][posmod(chapter,4)]
		var pad: float = sin(t*TAU*frequency)*.16+sin(t*TAU*frequency*1.5)*.08+sin(t*TAU*frequency*2.003)*.05
		var value: float = pad*(.65+.15*sin(t*.9))+low*.5+pulse*sin(t*TAU*65)*.1
		if chapter == 1: value += sin(t*TAU*(360+80*sin(t*2.5)))*.055+noise*exp(-fmod(t+1.8,4)*20)*.12
		if chapter == 2: value += noise*.06+sin(t*TAU*80)*exp(-fmod(t,.7)*16)*.07
		if chapter == 3: value += sin(t*TAU*164.81)*.04+sin(t*TAU*220)*.03
		var seam: float = minf(1.0,float(mini(i,count-i-1))/440)
		data.encode_s16(i*2,int(clampf(value*seam,-1,1)*24000))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = count
	cache[chapter] = stream
	return stream
