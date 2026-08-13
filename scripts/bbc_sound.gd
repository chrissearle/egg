class_name BbcSound
extends RefCounted

## Synthesises the game's sounds the way the BBC did.
##
## Every sound in Chuckie Egg is the BBC's own sound chip driven by OSWORD 7
## (channel, amplitude, pitch, duration), where amplitudes 1-4 select an
## ENVELOPE defined by OSWORD 8. Channel 0 is noise; 1-3 are square-wave tones.
##
## Nothing here is a recording. The parameters come from the original: the
## envelopes and the death tune's notes are in the public annotated disassembly
## at https://github.com/mungre/chuckie, and the per-state pitches are in
## MakeSound in the reference implementation's chuckie.c.
##
## This is synthesised at runtime rather than pre-rendered because the movement
## pitch changes every tick — a jump sweeps up then down, and a fall descends
## for as long as it lasts — so there is no fixed sample to bake.

const SAMPLE_RATE := 44100

## BBC pitch 64 is middle C, and the scale is 48 units to the octave.
const BASE_PITCH := 64
const BASE_FREQUENCY := 261.63
const UNITS_PER_OCTAVE := 48
const MAX_PITCH := 255

## SOUND durations are in twentieths of a second; ENVELOPE steps in hundredths.
const SECONDS_PER_DURATION := 1.0 / 20.0
const SECONDS_PER_ENVELOPE_STEP := 1.0 / 100.0

## Envelope amplitudes run 0-126.
const MAX_AMPLITUDE := 126

## Output level, leaving headroom so overlapping sounds do not clip.
const PEAK := 0.30

## `.envelope1` .. `.envelope3` from the disassembly, 14 bytes each, in ENVELOPE
## order: N, T, PI1, PI2, PI3, PN1, PN2, PN3, AA, AD, AS, AR, ALA, ALD.
const ENVELOPE_BEEP: Array[int] = [1, 1, 0, 0, 0, 0, 0, 0, 0x7E, 0xCE, 0x00, 0x00, 0x64, 0x00]
const ENVELOPE_TUNE: Array[int] = [2, 1, 0, 0, 0, 0, 0, 0, 0x7E, 0xFE, 0x00, 0xFB, 0x7E, 0x64]
const ENVELOPE_SQUIDGE: Array[int] = [3, 1, 0, 0, 0, 0, 0, 0, 0x32, 0x00, 0x00, 0xE7, 0x64, 0x00]

## `.dead_tune`: 16 (pitch, duration) pairs, played on a tone channel with
## envelope 2. The disassembly's leading count byte is 0x10, matching this.
const DEAD_TUNE: Array[Vector2i] = [
	Vector2i(0x21, 4), Vector2i(0x29, 2), Vector2i(0x21, 4), Vector2i(0x19, 2),
	Vector2i(0x15, 4), Vector2i(0x05, 2), Vector2i(0x0D, 4), Vector2i(0x01, 2),
	Vector2i(0x05, 0x0C), Vector2i(0x05, 1), Vector2i(0x0D, 1), Vector2i(0x15, 1),
	Vector2i(0x19, 1), Vector2i(0x21, 1), Vector2i(0x31, 1), Vector2i(0x35, 1),
]

## `.sound1`: the movement beep — envelope 1, duration 1, pitch per state.
const BEEP_DURATION := 1

## `.sound3`: the pickup — noise, envelope 3, duration 4. squidge(6) is an egg,
## squidge(5) a grain.
const SQUIDGE_DURATION := 4
const SQUIDGE_EGG_PITCH := 6
const SQUIDGE_GRAIN_PITCH := 5

## `.sound4`: the end-of-level bonus tick — noise, envelope 1, pitch 4.
const BONUS_PITCH := 4
const BONUS_DURATION := 1


## Frequency for a BBC pitch value.
static func frequency_for(pitch: int) -> float:
	return BASE_FREQUENCY * pow(2.0, float(pitch - BASE_PITCH) / UNITS_PER_OCTAVE)


## ENVELOPE rates are signed bytes; the disassembly lists them unsigned.
static func _signed(value: int) -> int:
	return value - 256 if value > 127 else value


## Amplitude envelope across a note, one value per output frame, 0.0 to 1.0.
##
## Walks the attack, decay and sustain phases at one step per hundredth of a
## second, clamping at each phase's target level. Release is not modelled: these
## sounds either run back to back or are retriggered before it would be heard.
static func _amplitude(envelope: Array[int], seconds: float) -> PackedFloat32Array:
	var step := envelope[1] * SECONDS_PER_ENVELOPE_STEP
	var attack := _signed(envelope[8])
	var decay := _signed(envelope[9])
	var sustain := _signed(envelope[10])
	var attack_level := envelope[12]
	var decay_level := envelope[13]

	var frames := int(seconds * SAMPLE_RATE)
	var curve := PackedFloat32Array()
	curve.resize(frames)

	var level := 0.0
	var phase := 0  # 0 attack, 1 decay, 2 sustain
	var next_step := step

	for frame in frames:
		if float(frame) / SAMPLE_RATE >= next_step:
			next_step += step
			if phase == 0:
				level += attack
				if (attack >= 0 and level >= attack_level) or (attack < 0 and level <= attack_level):
					level = attack_level
					phase = 1
			elif phase == 1:
				level += decay
				if (decay >= 0 and level >= decay_level) or (decay < 0 and level <= decay_level):
					level = decay_level
					phase = 2
			else:
				level += sustain
			level = clampf(level, 0.0, float(MAX_AMPLITUDE))
		curve[frame] = level / MAX_AMPLITUDE
	return curve


static func _to_stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(clampf(samples[i] * PEAK, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	return stream


## A square-wave note, as channels 1-3 produce.
static func tone(pitch: int, duration: int, envelope: Array[int]) -> PackedFloat32Array:
	var seconds := duration * SECONDS_PER_DURATION
	var curve := _amplitude(envelope, seconds)
	var period := SAMPLE_RATE / frequency_for(clampi(pitch, 0, MAX_PITCH))
	var samples := PackedFloat32Array()
	samples.resize(curve.size())
	for frame in curve.size():
		var high := fmod(float(frame), period) < period * 0.5
		samples[frame] = (1.0 if high else -1.0) * curve[frame]
	return samples


## A noise burst, as channel 0 produces.
##
## The reference's audio.c picks the shift rate from `note & 3`, so only the low
## two bits of the pitch matter here, and uses this 16-bit shift register.
## (The register is named `shift` rather than `seed`, which is a global function.)
static func noise(pitch: int, duration: int, envelope: Array[int]) -> PackedFloat32Array:
	var curve := _amplitude(envelope, duration * SECONDS_PER_DURATION)
	# Whole numbers of samples per shift, as audio.c computes them.
	@warning_ignore("integer_division")
	var rates := {0: SAMPLE_RATE / 7000, 1: SAMPLE_RATE / 3500, 2: SAMPLE_RATE / 1750}
	var rate: int = rates.get(pitch & 3, 0)
	var samples := PackedFloat32Array()
	samples.resize(curve.size())

	var shift := 0x4000
	var level := 1.0
	var countdown := rate
	for frame in curve.size():
		if rate > 0:
			countdown -= 1
			if countdown <= 0:
				countdown = rate
				var bit := (shift & 1) ^ ((shift >> 1) & 1)
				shift = (shift >> 1) | (bit << 15)
				level = 1.0 if (shift & 1) else -1.0
		samples[frame] = level * curve[frame]
	return samples


## Renders a sequence of (pitch, duration) notes back to back.
static func tune(notes: Array[Vector2i], envelope: Array[int]) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	for note in notes:
		samples.append_array(tone(note.x, note.y, envelope))
	return samples


static func beep_stream(pitch: int) -> AudioStreamWAV:
	return _to_stream(tone(pitch, BEEP_DURATION, ENVELOPE_BEEP))


static func squidge_stream(pitch: int) -> AudioStreamWAV:
	return _to_stream(noise(pitch, SQUIDGE_DURATION, ENVELOPE_SQUIDGE))


static func bonus_stream() -> AudioStreamWAV:
	return _to_stream(noise(BONUS_PITCH, BONUS_DURATION, ENVELOPE_BEEP))


static func death_stream() -> AudioStreamWAV:
	return _to_stream(tune(DEAD_TUNE, ENVELOPE_TUNE))
