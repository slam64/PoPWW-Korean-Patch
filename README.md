# 페르시아의 왕자: 전사의 길 한글 패치

**Prince of Persia: The Warrior Within (Steam PC) — Korean translation patch**

> **v0.9** · 한글화: **슬램백호**
> 대사 검수를 아직 모두 마치지 않은 버전이라 0.9로 시작합니다. 어색한 번역이나 오역, 깨지는 글자를 발견하시면 [이슈](../../issues)로 알려 주세요.

## 다운로드

[**Releases**](../../releases/latest)에서 `PoPWW_Korean_v0.9.zip`을 받으세요.

## 이 패치의 특징

- **완전 한글화** — 메뉴, 설정, 조작 설명, 튜토리얼, 지도, 저장/불러오기, 대화, 영상 자막까지 게임의 모든 글자를 한국어로 옮겼습니다. 영어 원문에 충실하면서도 인물마다 말투를 살린 자연스러운 구어체입니다.
- **원작에 없던 음성 자막** — 원래 자막이 없어 영어로만 들리던 음성에도 한국어 자막을 붙였습니다. 왕자의 혼잣말과 힌트, 여제·샤디·노인 같은 보스와 주요 인물의 대사, 전투 중 왕자의 도발. (전투를 어수선하게 만드는 잡병들의 외침에는 일부러 넣지 않았습니다.)
- **영상 건너뛰기** — 유비소프트 로고, 인트로, 이야기 영상, 엔딩 크레딧을 키보드 `ESC` 또는 게임패드로 건너뛸 수 있습니다.
- **인기 모드와 함께** — 4K 텍스처 팩(제작자 허락을 받아 호환 처리, 시작 튕김 문제도 해결), 게임 오류 수정 모음(Fix Compilation, 한국어 + Xbox식 버튼 이름), 비공식 패치 2.1(천·바람·머리카락 물리, 불·연기 효과, 마우스 수정 — 포함)과 함께 쓰도록 만들었습니다.
- **안전하고 가벼운 설치** — 게임 파일을 통째로 담지 않고 바뀌는 부분만 담았습니다. 파일마다 버전을 확인하고, 바꾸기 전의 원래 내용을 자동으로 보관해 `UNINSTALL.bat` 한 번으로 되돌립니다. 다음 버전은 새 `INSTALL.bat`만 실행하면 됩니다.
- **무료 글꼴** — 한글은 [Pretendard](https://github.com/orioncactus/pretendard)(SIL OFL)로 그렸습니다.

## 함께 설치하면 좋은 모드

각 모드는 제작자의 원 배포처에서 직접 받아 주세요.

| 모드 | 하는 일 | 받는 곳 |
|---|---|---|
| **게임 오류 수정 모음** (Warrior Within Fix Compilation) | 와이드스크린·고해상도, 게임패드(Xidi), 3D 음향, 안개·텍스처 오류 수정, 59프레임 제한 | [ModDB](https://www.moddb.com/games/prince-of-persia-warrior-within/downloads/warrior-within-fix-compilation) |
| **4K 텍스처 팩** (PoPWW 4K Texture Pack, Evgeshajk) | 텍스처를 4K로. 재업로드가 허락되지 않으니 반드시 원 배포처에서 | [Nexus Mods](https://www.nexusmods.com/princeofpersiawarriorwithin/mods/38) |
| **프롤로그 영상 깨짐 수정** | 노인과의 대화 영상이 깨지는 문제 수정. Fix 모음에 같은 파일이 들어 있어, Fix 모음을 설치했다면 따로 필요 없음 | [Nexus Mods](https://www.nexusmods.com/princeofpersiawarriorwithin/mods/17) |
| **비공식 패치 2.1** (The Unofficial Patch, Dawid Freeman) | 천·바람·머리카락 물리, 불·연기 효과 속도, 마우스 반응 수정. **이 패치에 포함** (Fix 모음이 있을 때 적용) | [Nexus Mods](https://www.nexusmods.com/princeofpersiawarriorwithin/mods/10) |

> 비공식 패치의 원 배포판 파일을 게임 폴더에 따로 넣지 마세요. 그 안의 `dinput8.dll`이 Fix 모음의 게임패드 파일을 덮어써 패드가 동작하지 않게 됩니다.

## 설치 방법

1. (모드를 쓸 때) 모드를 먼저 각자의 설명대로 설치합니다.
   - Fix 모음: `Main Patch` 폴더 안의 내용을 게임 폴더에 넣습니다. `Xbox Button Prompts`는 넣지 않아도 됩니다.
   - 4K 팩: `d3d9.dll`과 `Evgesha.JK`를 게임 폴더에 넣습니다.
2. 게임을 끈 상태에서 받은 압축 파일을 아무 곳에나 풀고 `INSTALL.bat`을 실행합니다.
   - 게임 폴더(Steam 라이브러리)를 자동으로 찾습니다. 못 찾으면 폴더를 고르는 창이 뜹니다.
   - "Windows의 PC 보호" 창이 뜨면 **추가 정보 → 실행**을 누르세요.
3. Steam에서 평소처럼 실행합니다.

모드를 나중에 설치하거나 다시 설치했을 때, Steam "게임 파일 무결성 검사"를 했을 때는 `INSTALL.bat`을 한 번 더 실행하세요. 한글 패치는 항상 마지막에 설치합니다.

**지원:** Steam판(영어), Windows 10/11. 다른 판이거나 다른 패치가 적용된 파일이면 설치 프로그램이 아무것도 바꾸지 않고 멈춥니다.

## 영상 건너뛰기 조작

- 키보드: `ESC`
- 게임패드: 조작 설정의 '시작' 동작에 지정된 버튼 (Fix 모음 + Xbox 패드 기본 설정에서는 View(Back) 버튼)

## 제거

`UNINSTALL.bat`을 실행하면 설치 전 상태로 되돌립니다. 게임 폴더의 `KoPatch_backup` 폴더를 쓰므로 지우지 마세요.

## 설치 프로그램이 하는 일

설치 프로그램은 Windows 기본 PowerShell 스크립트(`patcher/KoPatch.ps1`)라 메모장으로 열어 볼 수 있습니다.

- `prince.bf`, `POP2.EXE`, `POPData.BF`, `Menu/*.MGM`에 한글 차분을 적용합니다.
- Fix 모음이 있으면: `POP2WW.EXE`도 한글판으로 바꾸고, Fix 런처(`launcher.json`)가 `POP2.EXE`(한글판, 4GB 메모리 설정)를 실행하게 합니다. 비공식 패치가 `POP2.EXE`라는 이름의 게임에서만 동작하기 때문입니다. `scripts/POP_WW.asi`(비공식 패치)와, 원하면 한국어 + Xbox 버튼판 `update/POPData.BF`를 넣습니다.
- 4K 팩이 있으면: `Evgesha.JK` 목록에서 한글 글꼴이 들어간 월드 4개 항목만 끕니다(팩 제작자의 허락을 받은 방법). 팩 데이터는 이 패치에 들어 있지 않습니다.
- 바꾸기 전의 원래 내용은 `KoPatch_backup`에, 설치 기록은 `KoPatch_log.txt`에 남습니다.

## 알려진 문제

- **Xbox 패드가 인식되지 않을 때:** 듀얼센스(PS5 패드) 같은 다른 게임패드가 함께 연결되어 있으면 Fix 모음의 Xidi가 그 패드를 먼저 잡을 수 있습니다. 다른 패드를 끄고 실행하세요.
- **게임 중 가끔 창이 내려갈 때:** 다른 프로그램(프린터 관리 도구, 메신저 알림 등)이 화면 앞으로 튀어나오는 경우입니다. 해당 프로그램의 알림을 끄거나 게임 중에는 닫아 두세요.
- 60프레임을 넘겨 실행하면 게임 자체의 진행 불가 버그가 생길 수 있습니다. Fix 모음은 59프레임으로 제한합니다.

## 만든 사람과 고마운 분들

- 한글화: **슬램백호**
- 원작: Ubisoft Montreal
- The Unofficial Patch 2.1: Dawid Freeman — Nexus Mods 배포 허용 조건(제작자 표기)에 따라 원본 그대로 포함
- PoPWW 4K Texture Pack: Evgeshajk — 목록 조정 방식에 대해 허락을 받았습니다
- Warrior Within Fix Compilation: vini1264 및 참여 제작자들
- 글꼴: Pretendard © Kil Hyung-jin, SIL Open Font License 1.1

이 패치는 비공식 팬 번역이며 Ubisoft와 관계가 없습니다. 게임 파일은 들어 있지 않으며, 정품 게임의 원본 파일에 적용하는 차분만 담고 있습니다.
