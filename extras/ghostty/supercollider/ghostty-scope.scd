// Per-pattern waveform snapshots for ghostty-audio, which draws them behind each
// dN block in Neovim (shaders/audio-tidal-waves.glsl). Loaded from BootSuperDirt.scd after ~dirt.start.
//
// Each orbit gets a tap synth (reads the orbit's dry + effect buses, like SuperDirt's
// dirt_rms) that samples `points` values evenly over the last `window` seconds, `fps`
// times a second while the orbit is audible. Snapshots are forwarded once per Tidal
// pattern id (_id_, d1 -> 1) recently heard on that orbit:
//   /ghostty/scope <int id> <points floats>
(
var points = 48, window = 0.04, fps = 60, idHold = 2;  // fps: keep in sync with FPS in ghostty-audio
var target = NetAddr("127.0.0.1", 57130);
var lastSeen = Array.fill(~dirt.orbits.size, { IdentityDictionary.new });
var previousAction = ~dirt.receiveAction;
var numChannels = ~dirt.numChannels;

SynthDef(\ghostty_scope, { |dryBus, effectBus, orbitIndex|
	var sig = (In.ar(dryBus, numChannels) + In.ar(effectBus, numChannels)).sum;
	var taps = Array.fill(points, { |i|
		A2K.kr(DelayN.ar(sig, window, window * (points - 1 - i) / (points - 1)))
	});
	var audible = Amplitude.kr(sig, 0.01, 0.3) > 1e-4;
	SendReply.kr(Impulse.kr(fps) * audible, '/ghostty/scope', taps, orbitIndex);
}).add;

s.sync;

// Placed right after the orbit's group, not inside it: SuperDirt adds each event's
// synth group at the orbit group's tail, which would run after a tap placed there.
~ghosttyScopes.do(_.free);
~ghosttyScopes = ~dirt.orbits.collect { |orbit, i|
	Synth.after(Group.basicNew(s, orbit.group), \ghostty_scope, [
		dryBus: orbit.dryBus, effectBus: orbit.globalEffectBus, orbitIndex: i
	])
};

// Remember which pattern ids play on which orbit (several patterns may share one).
~dirt.receiveAction = { |event|
	var id = event[\_id_].asString.asInteger;
	var orbit = (event[\orbit] ? 0).asInteger;
	if(id > 0 and: { orbit < lastSeen.size }) { lastSeen[orbit][id] = Main.elapsedTime };
	previousAction.value(event);
};

OSCdef(\ghosttyScope, { |msg|
	var orbit = msg[2].asInteger, values = msg[3..];
	var now = Main.elapsedTime;
	lastSeen[orbit].keysValuesDo { |id, time|
		if(now - time < idHold) { target.sendMsg('/ghostty/scope', id, *values) };
	};
}, '/ghostty/scope', s.addr);

"ghostty-scope: tapping % orbits -> %:%".format(~dirt.orbits.size, target.ip, target.port).postln;
)
