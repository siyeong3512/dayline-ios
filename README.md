# Dayline (iOS 네이티브)

웹앱 Dayline을 SwiftUI 네이티브 앱으로 옮긴 버전이에요. Mac 없이 **GitHub에서 빌드 → SideStore로 설치·갱신**합니다.

| | 웹앱 | 네이티브 |
|---|---|---|
| 닫힌 상태 알림 | Cloudflare 서버가 1분마다 확인 | 아이폰이 직접 예약 (서버·인터넷 불필요) |
| "from 데이라인" 표시 | 못 없앰 | 없음 |
| 잔소리 말투 | – | 담백 / 순한 응원 / 친구 / 빡센 잔소리 |
| 목소리 알림 | 불가 | 잔소리를 음성 파일로 만들어 알림음으로 재생 |
| 저장 | 브라우저 + 서버 백업 | 아이폰 안 JSON + 자동 백업 30개 + 내보내기 |

화면 구성은 웹앱과 같아요: 하단 반투명 탭바(홈·시간표·캘린더·설정), 홈 할 일(Daily/Weekly/Monthly + 완료율 링), 에브리타임식 시간표, 하루·주간·월간 캘린더(스와이프로 페이지 넘김).

---

## 1. GitHub에 올리기 (처음 한 번)

1. GitHub에서 **새 공개(Public) 저장소** 만들기. 이름은 `dayline-ios` 추천. README 추가는 체크하지 않기.
2. 이 폴더에서:
   ```powershell
   git init -b main
   git add .
   git commit -m "Dayline 네이티브 첫 버전"
   git remote add origin https://github.com/<내아이디>/dayline-ios.git
   git push -u origin main
   ```
3. 저장소 **Actions** 탭에서 `Build & publish Dayline`이 초록 체크가 되면 끝. (약 5~10분)
   빨간 X면 실행 기록의 `빌드 실패` 아래 `error:` 줄을 확인하세요.

이후엔 **main에 push할 때마다** 자동으로 새 버전이 빌드되고 Release에 올라가요.

## 2. SideStore에 소스 추가 → 설치

1. 아이폰 SideStore → **Sources → + → 아래 주소 입력**
   ```
   https://github.com/<내아이디>/dayline-ios/releases/latest/download/source.json
   ```
2. 소스에 Dayline이 보이면 **설치(FREE)**.
3. 새 버전이 빌드되면 SideStore **업데이트** 탭에 뜨고, 눌러서 업데이트하면 돼요. 데이터는 유지돼요.

> 무료 Apple 계정 제한: 활성 앱 3개(SideStore 포함), 7일에 앱 ID 10개. 번들 ID(`app.dayline.ios`)는 바꾸지 마세요.

## 3. 7일 갱신 자동화 (단축어)

SideStore 앱이 이미 있고 LocalDevVPN(또는 예전 이름 StosVPN)이 설정돼 있다는 전제예요.

**단축어 앱 → 자동화 → + → 특정 시간**

- 시간: 매일 새벽 4시 (폰이 충전 중이고 Wi-Fi에 붙어 있을 시간)
- **즉시 실행** 선택, "실행 시 알림" 끔
- 동작:
  1. **VPN 설정** → LocalDevVPN **연결**
  2. **대기** 3초
  3. **SideStore → Refresh All Apps** (모든 앱 새로 고침)
  4. **VPN 설정** → LocalDevVPN **연결 해제**

팁:
- 하루 1번이면 충분해요. 7일 중 며칠 실패해도 괜찮아요.
- 자동화가 VPN을 켠 채로 끝나는 경우가 있어서, **4시 10분에 VPN 연결 해제만 하는 자동화**를 하나 더 두면 안전해요.
- 처음 한 번은 SideStore 안에서 직접 새로 고침해서 잘 되는지 확인하세요.
- iOS 업데이트나 기기 초기화 뒤에는 페어링 파일을 다시 넣어야 할 수 있어요 (Windows의 iloader).

## 4. 웹앱 기록 옮기기

1. PC 브라우저에서 Dayline 웹앱을 열고 로그인 상태 확인
2. `F12` → **Console** 탭 → [`tools/export-from-web.js`](tools/export-from-web.js) 내용 전체 붙여넣기 → Enter
   (크롬이 붙여넣기를 막으면 `allow pasting` 입력 후 다시)
3. `dayline-export.json`이 내려받아지면 아이폰으로 보내기 (카톡 나에게 보내기, iCloud Drive 등 → **파일 앱에 저장**)
4. Dayline 앱 → **설정 → 웹앱 기록 가져오기** → 파일 선택

브라우저 기록과 서버 백업을 합쳐서 내보내요. 같은 파일을 두 번 가져와도 중복되지 않아요.

## 5. 알림 동작 방식

- iOS는 앱당 대기 알림을 64개까지만 둬서, **가장 가까운 60개**를 예약하고 앱을 열 때마다 다시 채워요.
- 시간표는 **매주 반복 알림**이라 앱을 오래 안 열어도 계속 울려요. 약속은 가까운 순서로 들어가요.
- 목소리 알림: 잔소리 문장을 기기 TTS로 `.caf` 파일로 만들어 알림음으로 써요. 무음·집중 모드에선 안 들릴 수 있어요.
  - 설정 > 손쉬운 사용 > 읽기 및 말하기 > 음성에서 **향상된 한국어 음성**을 받으면 훨씬 자연스러워요.
  - **개인 음성**은 내 아이폰에서 내 목소리로 만든 것만 쓸 수 있어요. 친구 목소리는 이 방식으론 불가.

## 폴더 구조

```
project.yml                 XcodeGen 설정 (Xcode 프로젝트는 CI에서 생성)
Dayline/
  DaylineApp.swift          앱 시작, 포그라운드 알림 표시
  Model/                    날짜 유틸, 모델(웹앱 JSON 호환), 저장소·백업
  Notifications/            로컬 알림 예약, 잔소리 문구, TTS 음성 파일
  Views/                    탭바·홈·시간표·캘린더·설정·편집 화면
.github/workflows/build.yml 빌드 → Release(IPA + source.json)
tools/export-from-web.js    웹앱 기록 내보내기
```
