import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const app=readFileSync(new URL('../src/App.vue',import.meta.url),'utf8')
const main=readFileSync(new URL('../src/main.js',import.meta.url),'utf8')
const page=readFileSync(new URL('../index.html',import.meta.url),'utf8')
const manifest=JSON.parse(readFileSync(new URL('../public/manifest.webmanifest',import.meta.url),'utf8'))
const sw=readFileSync(new URL('../public/sw.js',import.meta.url),'utf8')

test('a member removal never reinitializes the entire app',()=>{
 const realtime=app.slice(app.indexOf('// Single room-scoped Realtime'),app.indexOf('function checkReconnect(){'))
 assert.match(realtime,/topicsForTable\(table\)/)
 assert.match(realtime,/void queueLiveRefresh\(/)
 assert.doesNotMatch(realtime,/if\(table==='rooms'\|\|table==='room_members'\)queueLiveRefresh\(true\)/)
 assert.match(app,/async function removeMember\(id\)/)
 assert.match(app,/await refresh\(\['room_members','room_profiles','assignments'\]\)/)
})
test('every Realtime event updates only affected tables',()=>{
 assert.match(app,/const dataFetchers=/)
 assert.match(app,/const dataRefs=/)
 assert.match(app,/const syncQueue=createSyncController\(/)
 assert.match(app,/const wanted=new Set\(topics\.includes\('all'\)\?ROOM_TOPICS:topics\)/)
 assert.doesNotMatch(app,/let refreshInFlight=null,refreshAgain=false/)
})
test('PWA is standalone with real PNG icons',()=>{
 assert.equal(manifest.display,'standalone')
 assert.equal(manifest.start_url,'/')
 for(const size of [192,512]){
  const icon=manifest.icons.find(item=>item.sizes===size+'x'+size)
  assert.ok(icon)
  const data=readFileSync(new URL('../public'+icon.src,import.meta.url))
  assert.deepEqual([...data.subarray(0,8)],[137,80,78,71,13,10,26,10])
  assert.equal(data.readUInt32BE(16),size)
  assert.equal(data.readUInt32BE(20),size)
 }
})
test('PWA never caches authenticated responses or versioned JS',()=>{
 assert.match(page,/rel="manifest"/)
 assert.match(main,/serviceWorker\.register\('\/sw\.js'\)/)
 assert.match(sw,/request\.mode==='navigate'/)
 assert.doesNotMatch(sw,/cache\.put\(/)
 assert.match(app,/Cài Roomly lên màn hình chính/)
})
