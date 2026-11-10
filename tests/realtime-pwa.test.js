import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync,existsSync} from 'node:fs'
import {join} from 'node:path'
const app=readFileSync(new URL('../src/App.vue',import.meta.url),'utf8')
const main=readFileSync(new URL('../src/main.js',import.meta.url),'utf8')
const page=readFileSync(new URL('../index.html',import.meta.url),'utf8')
const manifest=JSON.parse(readFileSync(new URL('../public/manifest.webmanifest',import.meta.url),'utf8'))
const sw=readFileSync(new URL('../public/sw.js',import.meta.url),'utf8')

test('removing other members only syncs data and does not reload workspace',()=>{
 const start=app.indexOf('// Live synchronization')
 const end=app.indexOf('function checkReconnect(){',start)
 const live=app.slice(start,end)
 assert.match(live,/if\(table==='rooms'\)syncRoomInfo\(\)/)
 assert.match(live,/queueLiveRefresh\(false\)/)
 assert.doesNotMatch(live,/if\(table==='rooms'\|\|table==='room_members'\)queueLiveRefresh\(true\)/)
 assert.match(app,/async function removeMember\(id\)/)
 assert.doesNotMatch(app,/location\.reload\(\)/)
})
test('background syncing coalesces overlapping refreshes',()=>{
 assert.match(app,/if\(refreshInFlight\)\{refreshAgain=true;return refreshInFlight\}/)
 assert.match(app,/refreshInFlight=null/)
 assert.match(app,/if\(refreshAgain\)\{refreshAgain=false;queueLiveRefresh\(false\)\}/)
})
test('PWA manifest has standalone display, start URL and correct bitmap icon headers',()=>{
 assert.equal(manifest.display,'standalone')
 assert.equal(manifest.start_url,'/')
 assert.equal(manifest.scope,'/')
 for(const size of [192,512]){
  const icon=manifest.icons.find(x=>x.sizes===size+'x'+size)
  assert.ok(icon)
  const file=new URL('..'+icon.src,import.meta.url)
  // tests reside in /tests; icons are in /public
  const data=readFileSync(new URL('../public'+icon.src,import.meta.url))
  assert.deepEqual([...data.subarray(0,8)],[137,80,78,71,13,10,26,10])
  assert.equal(data.readUInt32BE(16),size)
  assert.equal(data.readUInt32BE(20),size)
 }
})
test('PWA is registered without caching authenticated data or JS bundles',()=>{
 assert.match(page,/rel="manifest"/)
 assert.match(page,/apple-touch-icon/)
 assert.match(main,/serviceWorker\.register\('\/sw\.js'\)/)
 assert.match(sw,/request\.mode==='navigate'/)
 assert.doesNotMatch(sw,/cache\.put\(/)
})
test('install app button supports native prompt and iOS Safari instructions',()=>{
 assert.match(app,/beforeinstallprompt/)
 assert.match(app,/installPrompt\.value/)
 assert.match(app,/@click="installRoomly"/)
 assert.match(app,/Thêm vào Màn hình chính/)
 assert.match(app,/Cài Roomly lên màn hình chính/)
})
