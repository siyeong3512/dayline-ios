// Dayline 웹앱 → 네이티브 앱 이전용 내보내기 스크립트
// 사용법: PC 브라우저에서 Dayline 웹앱(로그인된 상태)을 열고, F12 → Console 탭에 이 파일 내용을 붙여넣고 Enter.
//        dayline-export.json 파일이 내려받아진다. 이 파일을 아이폰으로 보내 Dayline > 설정 > 웹앱 기록 가져오기.
// 브라우저 저장소의 기록과 서버 백업(시간표·할 일)을 합쳐서 내보낸다. 웹앱 데이터는 건드리지 않는다(읽기만 함).
(async () => {
  const read = key => { try { const v = JSON.parse(localStorage.getItem(key) || '[]'); return Array.isArray(v) ? v : []; } catch { return []; } };
  const get = async path => { try { const r = await fetch(path, { cache: 'no-store', credentials: 'include' }); return r.ok ? await r.json() : null; } catch { return null; } };

  const localItems = read('dayline.web.v1');
  const localTodos = read('dayline.todos.v1');
  const serverItems = (await get('/api/backups'))?.backups?.[0]?.records || [];
  const serverTodos = (await get('/api/todo-backups'))?.backups?.[0]?.records || [];

  // 일정: 브라우저 기록 우선, 서버에만 있는 것 추가
  const items = new Map();
  for (const x of [...serverItems, ...localItems]) if (x && typeof x.id === 'string') items.set(x.id, x);
  // 할 일: 더 최근에 수정된 쪽
  const todos = new Map();
  for (const t of [...serverTodos, ...localTodos]) {
    if (!t || typeof t.id !== 'string') continue;
    const prev = todos.get(t.id);
    if (!prev || (t.updatedAt || 0) >= (prev.updatedAt || 0)) todos.set(t.id, t);
  }

  const out = { format: 'dayline-export', version: 1, exportedAt: new Date().toISOString(),
                items: [...items.values()], todos: [...todos.values()] };
  const blob = new Blob([JSON.stringify(out, null, 2)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = 'dayline-export.json';
  document.body.appendChild(a);
  a.click();
  a.remove();
  const msg = `Dayline 내보내기: 일정·시간표 ${out.items.length}개, 할 일 ${out.todos.length}개 ` +
              `(브라우저 ${localItems.length}/${localTodos.length}, 서버 ${serverItems.length}/${serverTodos.length})`;
  console.log(msg);
  try { alert(msg); } catch {}
})();
