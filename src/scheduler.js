// Deterministic 7-day scheduling with round-robin cooking, time-specific
// availability, and workload balancing across previous weeks.
export function dateAt(start, offset) {
  const d = new Date(start + 'T00:00:00Z')
  d.setUTCDate(d.getUTCDate() + offset)
  return d.toISOString().slice(0, 10)
}
export function mondayOf(date) {
  const d = new Date(date + 'T00:00:00Z')
  d.setUTCDate(d.getUTCDate() - ((d.getUTCDay() + 6) % 7))
  return d.toISOString().slice(0, 10)
}
const minutes = value => Number(String(value).slice(0, 2)) * 60 + Number(String(value).slice(3, 5))
export function overlap(a, b) {
  const s = minutes(a.start_time), t = minutes(b.start_time)
  return s < t + Number(b.duration_minutes) && t < s + Number(a.duration_minutes)
}
export function isCooking(chore) {
  const icon = String(chore?.icon || '').toLowerCase()
  const name = String(chore?.name || '').toLowerCase()
  return icon === 'lunch' || icon === 'dinner' || /nấu|cơm|bếp/.test(name)
}
export function isBusy({userId, date, weekday, chore, busySlots = [], availability = []}) {
  if (availability.some(v => v.user_id === userId && Number(v.weekday) === weekday && v.available === false)) return true
  return busySlots.some(slot => slot.user_id === userId &&
    (slot.busy_date === date || (slot.busy_date == null && Number(slot.weekday) === weekday)) &&
    minutes(slot.starts_at) < minutes(chore.start_time) + Number(chore.duration_minutes) &&
    minutes(chore.start_time) < minutes(slot.ends_at))
}
/**
 * Every member finishes one round of cooking before that member gets the
 * next turn (when available). Lunch and dinner share a cooking queue.
 * Scores for other chores balance weighted work, history and repetitions.
 * Date-specific or repeating busy slots remove only conflicting hours.
 * No impossible shift is silently assigned.
 */
export function generateWeek({members, chores, availability = [], busySlots = [], history = [], weekStart}) {
  const active = members.filter(m => m.active !== false).slice()
    .sort((a, b) => String(a.user_id).localeCompare(String(b.user_id)))
  if (!active.length) return {rows: [], warnings: ['Nhóm chưa có thành viên.']}
  const loads = new Map(active.map(m => [m.user_id, 0]))
  const cookCounts = new Map(active.map(m => [m.user_id, 0]))
  const choreCounts = new Map()
  const lastCook = new Map()
  const lastChore = new Map()
  const rows = [], warnings = []
  const choreById = new Map(chores.map(c => [c.id, c]))
  const historical = history.filter(a => a.status !== 'skipped')
    .slice().sort((a, b) => String(a.work_date).localeCompare(String(b.work_date)))
  for (const a of historical) {
    if (!loads.has(a.assignee_id)) continue
    const c = choreById.get(a.chore_id)
    const weight = Number(a.weight || c?.weight || 1)
    loads.set(a.assignee_id, loads.get(a.assignee_id) + weight)
    const key = a.assignee_id + ':' + a.chore_id
    choreCounts.set(key, (choreCounts.get(key) || 0) + 1)
    lastChore.set(key, a.work_date)
    if (isCooking(c)) {
      cookCounts.set(a.assignee_id, cookCounts.get(a.assignee_id) + 1)
      lastCook.set(a.assignee_id, a.work_date)
    }
  }
  const tasks = chores.filter(c => c.enabled !== false).slice()
    .sort((a, b) => Number(isCooking(b)) - Number(isCooking(a)) ||
      String(a.start_time).localeCompare(String(b.start_time)) ||
      String(a.id).localeCompare(String(b.id)))
  for (let day = 0; day < 7; day++) {
    const work_date = dateAt(weekStart, day), weekday = day + 1, used = []
    const today = tasks.filter(c => (c.weekdays || []).map(Number).includes(weekday))
    for (const chore of today) {
      const cooking = isCooking(chore)
      const possible = active.filter(m =>
        !isBusy({userId: m.user_id, date: work_date, weekday, chore, availability, busySlots}) &&
        !used.some(row => row.assignee_id === m.user_id && overlap(row, chore))
      )
      // Avoid allocating both meals to the same person on one day if another
      // qualified cook can take the other meal.
      const unusedCooks = cooking ? possible.filter(m =>
        !used.some(row => row.assignee_id === m.user_id && isCooking(choreById.get(row.chore_id)))) : possible
      const candidates = unusedCooks.length ? unusedCooks : possible
      if (!candidates.length) {
        warnings.push(work_date + ': Không có người rảnh để làm ' + chore.name)
        continue
      }
      const ranked = candidates.map(m => {
        const key = m.user_id + ':' + chore.id
        const daysSince = lastChore.has(key) ? Math.round((Date.parse(work_date) -
          Date.parse(lastChore.get(key))) / 86400000) : 999
        const recent = daysSince <= 2 ? 6 : daysSince <= 6 ? 2 : 0
        const score = cooking
          ? [
              cookCounts.get(m.user_id) || 0, // hard rotation: fewest completed turns first
              lastCook.has(m.user_id) ? Date.parse(lastCook.get(m.user_id)) : -1,
              loads.get(m.user_id) || 0
            ]
          : [
              loads.get(m.user_id) || 0,
              (choreCounts.get(key) || 0) * 3 + recent,
              0
            ]
        return {m, score}
      }).sort((a, b) => {
        for (let i = 0; i < a.score.length; i++)
          if (a.score[i] !== b.score[i]) return a.score[i] - b.score[i]
        return String(a.m.user_id).localeCompare(String(b.m.user_id))
      })
      const selected = ranked[0].m
      const row = {
        room_id: chore.room_id, chore_id: chore.id, work_date,
        assignee_id: selected.user_id, status: 'pending',
        start_time: chore.start_time, duration_minutes: chore.duration_minutes,
        weight: chore.weight, name: chore.name
      }
      rows.push(row)
      used.push(row)
      loads.set(selected.user_id, loads.get(selected.user_id) + Number(chore.weight || 1))
      const key = selected.user_id + ':' + chore.id
      choreCounts.set(key, (choreCounts.get(key) || 0) + 1)
      lastChore.set(key, work_date)
      if (cooking) {
        cookCounts.set(selected.user_id, cookCounts.get(selected.user_id) + 1)
        lastCook.set(selected.user_id, work_date)
      }
    }
  }
  return {rows, warnings}
}
