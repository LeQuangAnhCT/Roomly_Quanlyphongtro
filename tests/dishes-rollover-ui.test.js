import test from 'node:test'
import assert from 'node:assert/strict'
import {readFileSync} from 'node:fs'
const app=readFileSync(new URL('../src/App.vue',import.meta.url),'utf8')
const scheduler=readFileSync(new URL('../src/scheduler.js',import.meta.url),'utf8')

test('completed task has a visible check icon rather than text state',()=>{
 assert.match(app,/<Check v-if="a\.status==='done'"/)
 assert.doesNotMatch(app,/a\.status==='done'\?'Đã xong'/)
})
test('unfinished dishes are checked on entry and on Vietnam day change',()=>{
 assert.match(app,/room_rollover_dishes/)
 assert.match(app,/await maybeRolloverDishes\(r\.id\)/)
 assert.match(app,/localVietnamDay\(\)/)
 assert.match(app,/setInterval\(/)
})
test('dish carryover is distinguished from debt',()=>{
 assert.match(app,/a\.rollover_source_id/)
 assert.match(app,/Đã chuyển/)
 assert.match(app,/Rửa chén tồn/)
})
test('lunch and dinner dishwashing use the same round',()=>{
 assert.match(scheduler,/icon === 'dishes_lunch' \|\| icon === 'dishes_dinner'/)
 assert.match(scheduler,/return 'dishes'/)
})
