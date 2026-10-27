// Sound after switching apps, in the web version of Overchess (Mac's report,
// Oct 2026): after leaving the app for another one and coming back, sounds
// played later and later until the app was restarted. iPhones interrupt a
// page's audio when it goes into the background, and the audio can come back
// with a long delay. So this pauses the game's audio itself as soon as the page
// is hidden, and resumes it when the page is shown again (and on the next
// touch, in case the browser wants a tap first), instead of leaving it to iOS.
// Loaded by the page before the game (export_presets.cfg's head include);
// copied next to index.html by tools/deploy_web.sh.
(function () {
	var Original = window.AudioContext || window.webkitAudioContext;
	if (!Original) return;
	var contexts = [];
	// Remember every audio context the game makes.
	function Tracked(options) {
		var context = options === undefined ? new Original() : new Original(options);
		contexts.push(context);
		return context;
	}
	Tracked.prototype = Original.prototype;
	window.AudioContext = Tracked;
	if (window.webkitAudioContext) window.webkitAudioContext = Tracked;

	function pause() {
		contexts.forEach(function (context) {
			if (context.state === "running") context.suspend();
		});
	}
	function wake() {
		if (document.hidden) return;
		contexts.forEach(function (context) {
			if (context.state !== "running" && context.state !== "closed") context.resume();
		});
	}
	document.addEventListener("visibilitychange", function () {
		if (document.hidden) pause(); else wake();
	});
	window.addEventListener("pagehide", pause);
	window.addEventListener("pageshow", wake);
	window.addEventListener("focus", wake);
	["touchend", "pointerup", "keydown"].forEach(function (name) {
		document.addEventListener(name, wake, true);
	});
	window.cpAudio = { contexts: contexts };
})();
