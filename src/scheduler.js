// Week scheduler: strict per-category, all-member rounds with carry-over history.
// One cooking turn = either lunch OR dinner. One laundry turn = wash AND dry.
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
export function isAnytime(chore) {
  return chore?.time_mode === 'anytime' ||
    (chore?.time_mode == null && (
      ['wash','dry','water'].includes(String(chore?.icon || '').toLowerCase()) ||
      /giặt|phơi|quét|lau nhà|chùi nhà|dọn nhà|đổi nước/i.test(String(chore?.name || ''))
    ))
}
export function overlap(a, b) {
  if (isAnytime(a) || isAnytime(b)) return false
  const s = minutes(a.start_time), t = minutes(b.start_time)
  return s < t + Number(b.duration_minutes) && t < s + Number(a.duration_minutes)
}
export function isCooking(chore) {
  const icon = String(chore?.icon || '').toLowerCase()
  const name = String(chore?.name || '').toLowerCase()
  return icon === 'lunch' || icon === 'dinner' || /nấu|cơm|bếp/.test(name)
}
export function isLaundry(chore) {
  const icon = String(chore?.icon || '').toLowerCase()
  const name = String(chore?.name || '').toLowerCase()
  return icon === 'wash' || icon === 'dry' || /giặt|phơi/.test(name)
}
export function choreCategory(chore) {
  if (isCooking(chore)) return 'cooking'
  if (isLaundry(chore)) return 'laundry'
  const icon = String(chore?.icon || '').toLowerCase()
  if (icon === 'dishes_lunch' || icon === 'dishes_dinner' ||
      /rửa\s*(chén|bát)/i.test(String(chore?.name || ''))) return 'dishes'
  const name = String(chore?.name || '').toLowerCase()
  if (icon === 'water' || /đổi.*nước|thay.*nước/.test(name)) return 'water'
  return 'chore:' + String(chore?.id || chore?.name || 'other')
}
export function isBusy({userId, date, weekday, chore, busySlots = [], availability = []}) {
  if (availability.some(v => v.user_id === userId && Number(v.weekday) === weekday && v.available === false)) return true
  return busySlots.some(slot => slot.user_id === userId &&
    (slot.busy_date === date || (slot.busy_date == null && Number(slot.weekday) === weekday)) &&
    (isAnytime(chore)
      ? minutes(slot.starts_at) <= 0 && minutes(slot.ends_at) >= 23 * 60 + 59
      : minutes(slot.starts_at) < minutes(chore.start_time) + Number(chore.duration_minutes) &&
        minutes(chore.start_time) < minutes(slot.ends_at)))
}
/**
 * Each member must receive a turn in a category before anyone can receive
 * another turn. Rounds survive Sunday/Monday via full preceding history.
 * If all members who still owe a turn are unavailable, issue a warning and
 * leave that shift unassigned; NEVER skip an unavailable member's turn.
 * Completed/assigned historical jobs count, but skipped jobs do not.
 * Ties are broken by last assignment (oldest first), workload and stable ID.
 */
export function generateWeek({members, chores, availability = [], busySlots = [], history = [], weekStart}) {
  const active = members.filter(m => m.active !== false).slice()
    .sort((a, b) => String(a.user_id).localeCompare(String(b.user_id)))
  if (!active.length) return {rows: [], warnings: ['Nhóm chưa có thành viên.']}
  const loads = new Map(active.map(m => [m.user_id, 0]))
  const countsByCategory = new Map()
  const lastByCategory = new Map()
  const rows = [], warnings = []
  const choreById = new Map(chores.map(c => [c.id, c]))
  function categoryCounts(category) {
    if (!countsByCategory.has(category))
      countsByCategory.set(category, new Map(active.map(m => [m.user_id, 0])))
    return countsByCategory.get(category)
  }
  const historical = history.filter(a => a.status !== 'skipped')
    .slice().sort((a, b) => String(a.work_date).localeCompare(String(b.work_date)) ||
      String(choreById.get(a.chore_id)?.start_time || '').localeCompare(String(choreById.get(b.chore_id)?.start_time || '')) ||
      String(a.id || '').localeCompare(String(b.id || '')))
  const countedLaundryLegacy = new Set()
  for (const a of historical) {
    if (!loads.has(a.assignee_id)) continue
    const c = choreById.get(a.chore_id)
    if (!c) continue
    const category = choreCategory(c)
    // The old database stored washing and drying as two tasks in a day.
    // Count the combined duty once when reconstructing historical rounds.
    if (category === 'laundry') {
      const once = a.work_date + ':' + a.assignee_id
      if (countedLaundryLegacy.has(once)) continue
      countedLaundryLegacy.add(once)
    }
    const counts = categoryCounts(category)
    counts.set(a.assignee_id, (counts.get(a.assignee_id) || 0) + 1)
    const k = category + ':' + a.assignee_id
    lastByCategory.set(k, a.work_date)
    loads.set(a.assignee_id, loads.get(a.assignee_id) + Number(a.weight || c.weight || 1))
  }
  const tasks = chores.filter(c => c.enabled !== false).slice()
    .sort((a, b) => Number(isCooking(b)) - Number(isCooking(a)) ||
      String(a.start_time).localeCompare(String(b.start_time)) ||
      String(a.id).localeCompare(String(b.id)))
  for (let day = 0; day < 7; day++) {
    const work_date = dateAt(weekStart, day), weekday = day + 1, used = []
    for (const chore of tasks.filter(c => (c.weekdays || []).map(Number).includes(weekday))) {
      const category = choreCategory(chore)
      const counts = categoryCounts(category)
      // Hard round boundary: candidate's count must be the minimum of ALL
      // active members, not just the people available at this time.
      const minimumTurns = Math.min(...active.map(m => counts.get(m.user_id) || 0))
      const eligible = active.filter(m => (counts.get(m.user_id) || 0) === minimumTurns &&
        !isBusy({userId: m.user_id, date: work_date, weekday, chore, availability, busySlots}) &&
        !used.some(row => row.assignee_id === m.user_id && overlap(row, chore)))
      if (!eligible.length) {
        warnings.push(work_date + ': Chưa phân ' + chore.name +
          ' — người chưa đến lượt tiếp theo đều bận hoặc trùng giờ; không tự lặp người đã làm.')
        continue
      }
      const ranked = eligible.sort((a, b) => {
        const lastA = lastByCategory.get(category + ':' + a.user_id) || ''
        const lastB = lastByCategory.get(category + ':' + b.user_id) || ''
        return lastA.localeCompare(lastB) ||
          (loads.get(a.user_id) || 0) - (loads.get(b.user_id) || 0) ||
          String(a.user_id).localeCompare(String(b.user_id))
      })
      // Within the same day, favor different cooks for lunch vs dinner,
      // without breaking the all-member round rule.
      const chosen = isCooking(chore)
        ? ranked.find(m => !used.some(row => row.assignee_id === m.user_id &&
            choreCategory(choreById.get(row.chore_id)) === 'cooking')) || ranked[0]
        : ranked[0]
      const row = {
        room_id: chore.room_id, chore_id: chore.id, work_date,
        assignee_id: chosen.user_id, status: 'pending',
        start_time: chore.start_time, duration_minutes: chore.duration_minutes,
        weight: chore.weight, name: chore.name
      }
      rows.push(row)
      used.push(row)
      counts.set(chosen.user_id, minimumTurns + 1)
      lastByCategory.set(category + ':' + chosen.user_id, work_date)
      loads.set(chosen.user_id, (loads.get(chosen.user_id) || 0) + Number(chore.weight || 1))
    }
  }
  return {rows, warnings}
}
