{{flutter_js}}
{{flutter_build_config}}

if ('serviceWorker' in navigator) {
  // Registration is explicit so a fresh installation can cache the app.
  navigator.serviceWorker.register(new URL('quran_service_worker.js', document.baseURI))
    .catch(error => console.warn('Offline installation could not finish.', error));
}
_flutter.loader.load({
  config: {canvasKitBaseUrl: new URL('canvaskit/', document.baseURI).href}
});
