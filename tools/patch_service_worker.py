# Run by deploy_web.sh after exporting. Godot's service worker (the script that
# keeps the web game's offline copy) downloads files through the browser's
# normal download cache, which GitHub Pages lets keep a file for 10 minutes.
# So a new version installed soon after an earlier visit could be stored with
# the OLD game files inside it. This makes it ask the server every time
# (cheap: the server answers "unchanged" when the file is the same).
import io
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "build/web/index.service.worker.js"
text = io.open(path, encoding="utf-8").read()
replacements = [
	("cache.addAll(CACHED_FILES)",
	 "cache.addAll(CACHED_FILES.map((name) => new Request(name, { cache: 'no-cache' })))"),
	# The game was called ChessPlus until 26 Oct 2026: its old offline copy goes too.
	("key.startsWith(CACHE_PREFIX) && key !== CACHE_NAME",
	 "(key.startsWith(CACHE_PREFIX) || key.startsWith('ChessPlus-sw-cache-')) && key !== CACHE_NAME"),
	("response = await self.fetch(event.request);",
	 "response = await self.fetch(event.request.mode === 'navigate' ? event.request : new Request(event.request, { cache: 'no-cache' }));"),
]
for old, new in replacements:
	if text.count(old) != 1:
		sys.exit("patch_service_worker: couldn't find " + old)
	text = text.replace(old, new)
# Tapping a "your move" notification (TurnNotifier) brings the game to the front.
text += '''
self.addEventListener('notificationclick', (event) => {
	event.notification.close();
	event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
		if (windows.length > 0) {
			return windows[0].focus();
		}
		return self.clients.openWindow('./');
	}));
});
'''
io.open(path, "w", encoding="utf-8", newline="").write(text)
print("Service worker patched.")
