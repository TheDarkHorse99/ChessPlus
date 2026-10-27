// Plusfish in the web version of Overchess: runs plusfish.wasm (the engine
// compiled to WebAssembly, from engine/plusfish) in a background thread (a Web
// Worker), so working out the eval bar never freezes the game or its sounds
// (it took ~45 ms a position on a PC, longer on phones, and made sounds late).
//   window.plusfish.ready          true once it's loaded
//   window.plusfish.submit(json)   start evaluating; returns a job number
//   window.plusfish.take(job)      the reply lines (JSON) once done, else null
//   window.plusfish.run(json)      the old way (on the page's own thread), kept
//                                  for browsers that can't start the worker
// The game calls it through JavaScriptBridge (scenes/game/plusfish_link.gd).
// Loaded by the page: export_presets.cfg's head include; copied next to
// index.html by tools/deploy_web.sh.
(function () {
	var pf = { ready: false, error: "", worker: null, replies: {}, next: 1 };
	window.plusfish = pf;
	var wasmUrl = new URL("plusfish.wasm", document.baseURI).href;

	// Evaluate `input` with the engine's exports: returns its reply text.
	var runWith = "function runWith(ex, input) {" +
		"var bytes = new TextEncoder().encode(input);" +
		"var ptr = ex.pf_alloc(bytes.length);" +
		"new Uint8Array(ex.memory.buffer, ptr, bytes.length).set(bytes);" +
		"var out = ex.pf_run(ptr, bytes.length);" +
		"var len = ex.pf_out_len();" +
		// Read the reply before freeing (the memory may move as it grows).
		"var text = new TextDecoder().decode(new Uint8Array(ex.memory.buffer, out, len));" +
		"ex.pf_free(ptr, bytes.length);" +
		"return text; }";

	var workerSource = runWith +
		"var ex = null;" +
		"onmessage = function (e) {" +
		"  var d = e.data;" +
		"  if (d.load) {" +
		"    fetch(d.load).then(function (r) { if (!r.ok) throw new Error('plusfish.wasm: ' + r.status); return r.arrayBuffer(); })" +
		"      .then(function (b) { return WebAssembly.instantiate(b, {}); })" +
		"      .then(function (r) { ex = r.instance.exports; postMessage({ ready: true }); })" +
		"      .catch(function (err) { postMessage({ loadError: String(err) }); });" +
		"    return;" +
		"  }" +
		"  var text;" +
		"  try { text = ex ? runWith(ex, d.input) : JSON.stringify({ error: 'Plusfish is not loaded' }); }" +
		"  catch (err) { text = JSON.stringify({ error: String(err) }); }" +
		"  postMessage({ id: d.id, out: text });" +
		"};";

	// The page's own copy, for run() (and if the worker can't start).
	var exports = null;
	function loadHere() {
		fetch(wasmUrl)
			.then(function (r) {
				if (!r.ok) throw new Error("plusfish.wasm: " + r.status);
				return r.arrayBuffer();
			})
			.then(function (bytes) { return WebAssembly.instantiate(bytes, {}); })
			.then(function (result) {
				exports = result.instance.exports;
				pf.exports = exports;
				pf.ready = true;
			})
			.catch(function (e) { pf.error = String(e); });
	}

	try {
		var blob = new Blob([workerSource], { type: "text/javascript" });
		pf.worker = new Worker(URL.createObjectURL(blob));
		pf.worker.onmessage = function (e) {
			var d = e.data;
			if (d.ready) {
				pf.ready = true;
			} else if (d.loadError) {
				// No worker engine: fall back to running on the page.
				pf.worker = null;
				loadHere();
			} else {
				pf.replies[d.id] = d.out;
			}
		};
		pf.worker.onerror = function () {
			pf.worker = null;
			loadHere();
		};
		pf.worker.postMessage({ load: wasmUrl });
	} catch (e) {
		pf.worker = null;
		loadHere();
	}

	pf.submit = function (input) {
		var id = pf.next++;
		if (pf.worker) {
			pf.worker.postMessage({ id: id, input: input });
		} else {
			pf.replies[id] = pf.run(input);
		}
		return id;
	};

	pf.take = function (id) {
		if (!(id in pf.replies)) return null;
		var out = pf.replies[id];
		delete pf.replies[id];
		return out;
	};

	pf.run = function (input) {
		if (!exports) return '{"error":"Plusfish is not loaded on the page"}';
		try {
			var bytes = new TextEncoder().encode(input);
			var ptr = exports.pf_alloc(bytes.length);
			new Uint8Array(exports.memory.buffer, ptr, bytes.length).set(bytes);
			var out = exports.pf_run(ptr, bytes.length);
			var len = exports.pf_out_len();
			var text = new TextDecoder().decode(new Uint8Array(exports.memory.buffer, out, len));
			exports.pf_free(ptr, bytes.length);
			return text;
		} catch (e) {
			return JSON.stringify({ error: String(e) });
		}
	};
})();
