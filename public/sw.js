const CACHE='roomly-offline-v1'
self.addEventListener('install',event=>{
 event.waitUntil(caches.open(CACHE).then(cache=>cache.add('/offline.html')).then(()=>self.skipWaiting()))
})
self.addEventListener('activate',event=>{
 event.waitUntil(caches.keys().then(keys=>Promise.all(keys.filter(key=>key.startsWith('roomly-offline-')&&key!==CACHE).map(key=>caches.delete(key)))).then(()=>self.clients.claim()))
})
// Never cache app JavaScript or authenticated data. Always request the latest
// deployment; only serve the static offline explanation when navigation fails.
self.addEventListener('fetch',event=>{
 if(event.request.mode==='navigate'){
  event.respondWith(fetch(event.request).catch(()=>caches.match('/offline.html')))
 }
})
