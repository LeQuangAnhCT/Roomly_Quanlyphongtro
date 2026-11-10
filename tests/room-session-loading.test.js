import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const source=readFileSync(new URL('../src/App.vue',import.meta.url),'utf8')

test('do not show room joining screen before membership lookup finishes',()=>{
 assert.match(source,/roomStatus=ref\('loading'\)/)
 assert.match(source,/booting\|\|\(user&&roomStatus==='loading'\)/)
 assert.match(source,/roomStatus==='none'&&!room/)
 assert.doesNotMatch(source,/v-else-if="!room"/)
})
test('room lookup distinguishes absence from API failure and offers retry',()=>{
 assert.match(source,/if\(!own\?\.length\)/)
 assert.match(source,/roomStatus\.value='none'/)
 assert.match(source,/roomStatus\.value='error'/)
 assert.match(source,/roomLoadError\.value=localErr\(e\)/)
 assert.match(source,/@click="loadEverything"/)
})
test('stale membership requests cannot replace a new authenticated session',()=>{
 assert.match(source,/const revision=sessionRevision/)
 assert.match(source,/revision!==sessionRevision\|\|user\.value\?\.id!==accountId/)
})

test('background realtime membership check keeps workspace visible',()=>{
 assert.match(source,/async function loadEverything\(\{silent=false\}=\{\}\)/)
 assert.match(source,/const background=silent&&roomStatus\.value==='ready'&&!!room\.value/)
 assert.match(source,/if\(!background\)roomStatus\.value='loading'/)
 assert.match(source,/loadEverything\(\{silent:true\}\)/)
})
test('focusing the app is rate-limited and does not force a visible loader',()=>{
 assert.match(source,/Date\.now\(\)-lastReconnect<30000/)
 assert.match(source,/queueLiveRefresh\(true\)/)
})

test('tab switching does not use out-in transition that blanks and remounts the page',()=>{
 assert.doesNotMatch(source,/<Transition name="page" mode="out-in">/)
 assert.match(source,/<template>\s*<section v-if="currentTab==='schedule'"/)
})
test('focus only refreshes background data, no unconditional whole-room reload',()=>{
 const start=source.indexOf('function checkReconnect(){')
 const end=source.indexOf('let dayWatcher=',start)
 const body=source.slice(start,end)
 assert.match(body,/queueLiveRefresh\(false\)/)
 assert.match(body,/liveState\.value==='reconnecting'/)
 assert.match(body,/\}else queueLiveRefresh\(true\)/)
})
