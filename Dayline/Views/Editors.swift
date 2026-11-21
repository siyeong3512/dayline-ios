import SwiftUI

struct ScheduleEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var item: ScheduleItem
    let isNew: Bool
    @State private var dateValue: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var nextDay: Bool
    @State private var error: String?
    @State private var confirmDelete = false

    init(item: ScheduleItem, isNew: Bool) {
        _item = State(initialValue: item)
        self.isNew = isNew
        _dateValue = State(initialValue: Day.date(item.date))
        _startTime = State(initialValue: Day.time(fromMinutes: item.start))
        _endTime = State(initialValue: Day.time(fromMinutes: item.end))
        _nextDay = State(initialValue: item.end >= 1440)
    }

    private var isTimetable: Bool { item.kind == .timetable }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(isTimetable ? "수업 이름" : "약속 이름", text: $item.title)
                    TextField("장소 (강의실, 카페, 온라인…)", text: $item.place)
                }

                Section {
                    DatePicker(isTimetable ? "반복 시작일" : "날짜", selection: $dateValue, displayedComponents: .date)
                    if isTimetable {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("반복 요일").font(.subheadline).foregroundStyle(.secondary)
                            WeekdayPicker(selection: $item.weekdays)
                        }
                    }
                    DatePicker("시작", selection: $startTime, displayedComponents: .hourAndMinute)
                    if isTimetable {
                        DatePicker("종료", selection: $endTime, displayedComponents: .hourAndMinute)
                        Toggle("다음 날 종료", isOn: $nextDay)
                    }
                } header: {
                    Text(isTimetable ? "반복" : "언제")
                }

                Section {
                    ReminderChips(selection: $item.reminders)
                } header: {
                    Text("미리 알림")
                } footer: {
                    Text("앱을 닫아도 아이폰이 직접 알려줘요. 말투와 목소리는 설정에서 바꿀 수 있어요.")
                }

                Section("색상") {
                    ColorGrid(selection: $item.color)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }

                if !isNew {
                    Section {
                        Button("삭제", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle((isTimetable ? "고정 일정" : "약속") + (isNew ? " 추가" : " 수정"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("삭제할까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("삭제하기", role: .destructive) {
                    store.delete(item)
                    dismiss()
                }
            } message: {
                Text(isTimetable ? "고정 일정은 모든 반복 요일에서 삭제돼요." : "이 약속을 삭제해요.")
            }
        }
    }

    private func save() {
        var x = item
        x.title = x.title.trimmingCharacters(in: .whitespacesAndNewlines)
        x.place = x.place.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !x.title.isEmpty else { error = "이름을 입력해 주세요."; return }
        x.date = Day.key(dateValue)
        let start = Day.minutesOfDay(startTime)
        x.time = Day.clock(start)
        if isTimetable {
            let duration = Day.minutesOfDay(endTime) - start + (nextDay ? 1440 : 0)
            guard duration > 0, duration <= 2880 else {
                error = "종료 시간을 시작보다 늦게 설정해 주세요. 자정을 넘기면 '다음 날 종료'를 켜세요."
                return
            }
            guard !x.weekdays.isEmpty else { error = "반복 요일을 하나 이상 선택해 주세요."; return }
            x.duration = duration
        } else {
            x.weekdays = []
        }
        x.reminders = Array(Set(x.reminders)).sorted()
        store.upsert(x)
        dismiss()
    }
}

struct TodoEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var todo: TodoItem
    let isNew: Bool
    @State private var hasDue: Bool
    @State private var dueDate: Date
    @State private var error: String?

    init(todo: TodoItem, isNew: Bool) {
        _todo = State(initialValue: todo)
        self.isNew = isNew
        _hasDue = State(initialValue: todo.due != nil)
        _dueDate = State(initialValue: todo.due.map(Day.date) ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("오늘 나를 위해 할 일", text: $todo.title)
                }
                Section {
                    Picker("반복 주기", selection: $todo.cadence) {
                        ForEach(Cadence.allCases) { c in Text(c.label).tag(c) }
                    }
                    .pickerStyle(.segmented)
                    Toggle("마감 기준일", isOn: $hasDue.animation())
                    if hasDue {
                        DatePicker("기준일", selection: $dueDate, displayedComponents: .date)
                    }
                } footer: {
                    Text(todo.cadence.help)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                if !isNew {
                    Section {
                        Button("삭제", role: .destructive) {
                            store.archiveTodo(todo)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "할 일 추가" : "할 일 수정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        var t = todo
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.title.isEmpty else { error = "할 일을 입력해 주세요."; return }
        t.due = hasDue ? Day.key(dueDate) : nil
        t.archived = false
        store.upsertTodo(t)
        dismiss()
    }
}
