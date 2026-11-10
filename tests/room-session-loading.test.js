import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const source=readFileSync(new URL('../src/App.vue',import.meta.url),'utf8')

test('join screen only appears after a real negative membership lookup',()=>{
 assert.match(source,/roomStatus=ref\('loading'\)/)
 assert.match(source,/booting\|\|\(user&&roomStatus==='loading'\)/)
 assert.match(source,/roomStatus==='none'&&!room/)
 assert.doesNotMatch(source,/v-else-if="!room"/)
})
test('session and room updates are scoped to current identity',()=>{
 assert.match(source,/const revision=sessionRevision/)
 assert.match(source,/revision!==sessionRevision\|\|user\.value\?\.id!==accountId/)
 assert.match(source,/async function loadEverything\(\{silent=false\}=\{\}\)/)
 assert.match(source,/if\(!background\)roomStatus\.value='loading'/)
})
test('auth token updates and repeated SIGNED_IN events do not re-bootstrap',()=>{
 assert.match(source,/if\(nextId===previousId\)/)
 assert.match(source,/event==='USER_UPDATED'/)
 assert.match(source,/return\s*\}\s*user\.value=next/)
})
test('internal tabs render directly inside main and never perform navigation',()=>{
 assert.doesNotMatch(source,/<Transition name="page" mode="out-in">/)
 assert.doesNotMatch(source,/<main class="main-area">\s*<template>/)
 assert.match(source,/<main class="main-area">\s*<section v-if="currentTab==='schedule'"/)
 assert.match(source,/@click="currentTab=item.id"/)
})
test('moving between browser tabs triggers a soft update only when stale',()=>{
 const start=source.indexOf('function checkReconnect(){')
 const end=source.indexOf('let dayWatcher=',start)
 const block=source.slice(start,end)
 assert.match(block,/lastDataSyncAt>180000/)
 assert.match(block,/void queueLiveRefresh\(\['all'\]\)/)
 assert.doesNotMatch(block,/reset\(\)/)
})
test('no direct full-page reload calls occur in App',()=>{
 assert.doesNotMatch(source,/location\.reload\(/)
 assert.doesNotMatch(source,/document\.location=/)
 assert.doesNotMatch(source,/window\.location\.href\s*=/)
})
