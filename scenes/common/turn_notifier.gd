class_name TurnNotifier
extends RefCounted

## "Your move" notifications (Mac, Oct 2026): when it becomes your turn while
## the game isn't in front of you (another tab or app, or the window behind
## others), the system shows a notification. Only while the app is running: no
## push server, so a closed app (or a phone that has paused it) gets none.
##   Web: the browser's notifications, shown through the service worker where it
##     can (iPhones need that, and only allow it for the home-screen app). The
##     browser asks permission once, on the first tap after an online game starts.
##   Windows app: a Windows notification (sent through PowerShell), and the
##     taskbar button flashes.

## Off in tests: notifications are only recorded in `sent`, never shown.
static var deliver := true
## Tests: act as if the app were in the background.
static var force_background := false
## Every notification asked for, as "title: text" (for tests).
static var sent: PackedStringArray = []

## True if the player probably isn't looking at the game right now.
static func in_background() -> bool:
	if force_background:
		return true
	if not deliver:
		return false
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("document.hidden || !document.hasFocus()", true))
	var window := (Engine.get_main_loop() as SceneTree).root
	return not window.has_focus() or window.mode == Window.MODE_MINIMIZED

## It's the player's turn now: notify them if the app is in the background.
## `text` says what happened, e.g. "Your opponent played Nf3."
static func your_turn(text: String) -> void:
	# Switched off in Settings (Mac): nothing.
	if in_background() and UserSettings.notifications_on():
		notify("Overchess: your move", text)

static func notify(title: String, text: String) -> void:
	sent.append(title + ": " + text)
	if not deliver:
		return
	if OS.has_feature("web"):
		_web_notify(title, text)
		return
	DisplayServer.window_request_attention()
	if OS.get_name() == "Windows":
		_windows_notify(title, text)

## Web: ask for permission to show notifications on the player's next tap
## (browsers only allow asking during a tap). Does nothing once answered.
static func ask_permission_on_next_tap() -> void:
	if not OS.has_feature("web") or not deliver:
		return
	JavaScriptBridge.eval("""
(function () {
	if (!('Notification' in window) || Notification.permission !== 'default') return;
	window.cpNotify = window.cpNotify || {};
	window.cpNotify.want = true;
	if (window.cpNotify.hooked) return;
	window.cpNotify.hooked = true;
	var ask = function () {
		if (!window.cpNotify.want || Notification.permission !== 'default') return;
		window.cpNotify.want = false;
		Notification.requestPermission();
	};
	document.addEventListener('pointerup', ask, true);
	document.addEventListener('touchend', ask, true);
})();
""", true)

static func _web_notify(title: String, text: String) -> void:
	JavaScriptBridge.eval("""
(function (title, text) {
	if (!('Notification' in window) || Notification.permission !== 'granted') return;
	var options = { body: text, tag: 'chessplus-turn', renotify: true, icon: 'index.144x144.png' };
	var plain = function () {
		try {
			var shown = new Notification(title, options);
			shown.onclick = function () { window.focus(); shown.close(); };
		} catch (e) {}
	};
	if (navigator.serviceWorker && navigator.serviceWorker.getRegistration) {
		navigator.serviceWorker.getRegistration().then(function (reg) {
			if (reg) { reg.showNotification(title, options); } else { plain(); }
		}).catch(plain);
	} else {
		plain();
	}
})(%s, %s);
""" % [JSON.stringify(title), JSON.stringify(text)], true)

## A Windows notification ("toast"), sent through PowerShell (Windows 10 and 11
## have everything needed built in).
static func _windows_notify(title: String, text: String) -> void:
	var script := """
$template = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
$lines = $template.GetElementsByTagName('text')
$lines.Item(0).AppendChild($template.CreateTextNode('%s')) > $null
$lines.Item(1).AppendChild($template.CreateTextNode('%s')) > $null
$toast = [Windows.UI.Notifications.ToastNotification]::new($template)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe').Show($toast)
""" % [title.replace("'", "''"), text.replace("'", "''")]
	OS.create_process("powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", script])
