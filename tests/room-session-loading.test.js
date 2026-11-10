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
