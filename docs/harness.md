# 하네스 — 무엇이 어디서 강제되나 (enforcement map)

COOA 개발 규율을 "문서(사람이 기억)"에서 "기계적 게이트(어기면 차단)"로 옮긴 층들의 지도.
하네스 엔지니어링의 3장치: ① 가시성(로그·`bin/smoke`·Playwright E2E) ② 점진적 컨텍스트(`../CLAUDE.md` 허브 → 토픽 문서) ③ **강제 훅**(이 문서의 핵심). 규율 진실원천은 [dev-discipline.md](dev-discipline.md)(R1~R8) — 이 문서는 그것을 *어떻게 강제하는지*.

## 강제 층 (바깥→안 · 되돌릴 수 없는 것 우선)

| 층 | 무엇 | 트리거 | 어기면 | 위치 |
|---|---|---|---|---|
| **P0 Claude 가드** | outer→web-demo push · 공유브랜치 force-push 차단 | Claude가 Bash로 git push 시도 (PreToolUse) | exit 2 · 차단 | `~/.claude/hooks/git-topology-guard.sh` + `~/.claude/settings.json` `hooks` |
| **pre-commit** | ① 스테이지된 `.rb` rubocop ② 마이그↔schema_cache 동봉(R1/R6) | `git commit` | 커밋 차단 | `lefthook.yml` · `bin/hooks/schema-cache-staged-check` |
| **commit-msg** | Claude 트레일러 완전성(둘 다 있거나 아예 없거나) | `git commit` | 커밋 차단 | `bin/hooks/commit-msg-trailers` |
| **pre-push** | 전체 게이트 `bin/ci` 발화 | `git push` | 푸시 차단 | `lefthook.yml` → `bin/ci` |
| **bin/ci** (전체 게이트) | setup → rubocop → security×3 → **RLS/grant/audit 자세** → rails test → seeds → **system** → **smoke** | 수동 `bin/ci` · pre-push | step 실패 시 중단 | `config/ci.rb` |
| **상시** | strong_migrations — unsafe DDL raise | `db:migrate` | 마이그 중단 | `config/initializers/strong_migrations.rb` |

**pre-push가 bin/ci를 발화**하는 것이 핵심 — 그 전엔 `bin/ci`가 "아무도 안 누르는 버튼"이었다(자동 트리거 0). 이제 push 순간 실제 Tier-A 강제가 된다.

## 환경 치트시트 (틀리면 결함 은폐)
- **자세 게이트**(`rls:audit`·`rls:grant_audit`·`audit:verify`) → **owner 연결**(`COOA_DB_USER=$USER`) · **development DB**. 카탈로그/해시체인 조회(read-only·무변형). grant·RLS·체인은 role-독립 사실이라 owner로 조회 가능. `config/ci.rb`는 `step`이 `system(*argv)`(셸 미경유)라 owner를 Ruby에서 계산해 `env` argv로 전달.
- **bin/smoke** → **cooa_app 연결**(기본) · **development**. 실제 런타임 권한 경로를 걷는다. **owner로 돌리면 권한 결함이 안 보인다**(test env=owner → `SMOKE_ENV=test` 금지). `SMOKE_REQUIRE_WRITE=1`이면 "제품 없어 쓰기경로 스킵"을 하드실패로(빈 DB 거짓통과 차단). **DB 자동시드 금지** — `db/seeds.rb`가 `delete_all` 후 재생성이라 bin/ci마다 dev DB를 날림.
- **rails test / test:system** → **owner · test DB**. owner는 RLS 우회라 권한축(R8)은 여기서 안 보임 → 그래서 smoke가 별도로 필요.

## 우회 (escape hatch)
- `git commit --no-verify` / `git push --no-verify` — lefthook 훅 스킵(컬럼 미변경 데이터 마이그, 긴급).
- `LEFTHOOK=0 git <cmd>` — lefthook 전체 비활성.
- `safety_assured { ... }` — strong_migrations 개별 우회.
- **P0 가드는 `--no-verify`로 못 뚫는다**(git 훅이 아니라 Claude 훅). Claude 자동실행만 차단하니, 정말 필요하면 **사람이 터미널에서 직접** 실행.

## P0 가드 — 알려진 특성
- 가드는 **명령 문자열을 검사**한다 → 명령이 `web-demo`나 `push --force … main`을 **데이터로 포함**(테스트·문서생성)해도 차단된다. 그런 명령은 스크립트 파일로 감싸 `bash <file>`로 실행(바깥 명령엔 토큰 없음).
- **fail-closed**: web-demo push인데 대상 리포 해석 실패 시 차단(안전측).
- **비-COOA 리포 no-op**: 하드코딩된 COOA 경로 밖에선 즉시 통과 → 전역 등록해도 무해.

## 진실원천 백업 — 가드 스크립트 전문
가드는 리포 밖(`~/.claude/hooks/`)에 살아 버전관리가 안 된다. 아래는 **리뷰·복구용 사본**(실체가 진실원천 — 드리프트 시 실체 우선).

```bash
#!/usr/bin/env bash
# Claude Code PreToolUse(Bash) 가드 — 되돌릴 수 없는 두 git 패턴만 차단한다.
#   exit 0 = 허용(기본) · exit 2 = 차단. 매칭 안 되는 모든 명령은 그대로 통과.
#   (1) inner web 리포 이외에서 `web-demo` 로 push  → 웹앱 배포 히스토리 파괴
#   (2) 공유 브랜치(main / web-demo / feat/foundation-tenant-rls)로의 force-push
# 비-COOA 리포에서는 즉시 no-op → 전역 등록해도 무해.
set -uo pipefail

INNER="/Users/igangu/COOA/web"
PROT='(^|[:/+[:space:]])(main|web-demo|feat/foundation-tenant-rls)($|[[:space:]])'

input="$(cat)"
case "$input" in
  *push*) : ;;
  *) exit 0 ;;
esac

cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // ""'            2>/dev/null || true)"

printf '%s' "$cmd" | grep -qE '(^|[;&|[:space:]])git([[:space:]]|$)' || exit 0
printf '%s' "$cmd" | grep -qE '(^|[[:space:]])push([[:space:]]|$)'   || exit 0

dir="$cwd"
if [[ "$cmd" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  dir="${BASH_REMATCH[1]}"
elif [[ "$cmd" =~ (^|[\&\;])[[:space:]]*cd[[:space:]]+([^[:space:]\;\&\|]+) ]]; then
  dir="${BASH_REMATCH[2]}"
fi
case "$dir" in
  /*) : ;;
  "") dir="${cwd:-.}" ;;
  *)  dir="${cwd:-.}/$dir" ;;
esac
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)"

deny() { printf '⛔ COOA git-topology 가드: %s\n' "$1" >&2; exit 2; }

if printf '%s' "$cmd" | grep -qE '(^|[:/+[:space:]])web-demo($|[[:space:]])'; then
  if [ "$root" != "$INNER" ]; then
    deny "outer/미상 리포에서 web-demo 로 push 감지 — 웹앱 배포 히스토리 파괴 위험.
   web-demo push 는 오직 inner web 리포($INNER)에서만 허용됩니다.
   의도한 배포면 web 리포 안에서 직접 실행하세요."
  fi
fi

force=0
printf '%s' "$cmd" | grep -qE '(^|[[:space:]])(--force|-f|--force-with-lease)([[:space:]=]|$)' && force=1
if [ "$force" = 1 ] && printf '%s' "$cmd" | grep -qE "$PROT"; then
  deny "공유 브랜치(main/web-demo/feat/foundation-tenant-rls)로의 force-push 감지 — 공유 히스토리 재작성 금지.
   정말 필요하면 사람이 직접 실행하세요 (이 가드는 Claude 자동 실행만 차단)."
fi
if printf '%s' "$cmd" | grep -qE '[[:space:]]\+[^[:space:]]*(main|web-demo|feat/foundation-tenant-rls)'; then
  deny "공유 브랜치로의 +refspec force-push 감지 — 공유 히스토리 재작성 금지.
   정말 필요하면 사람이 직접 실행하세요."
fi

exit 0
```

## STRICT 트레일러 변형 (문서화 · 기본 비활성)
현재 `commit-msg`는 "트레일러가 있으면 완전해야" 검증(사람 커밋 무영향). 모든 커밋에 트레일러를 강제하려면 `bin/hooks/commit-msg-trailers`의 `[ $((has_co + has_ses)) -eq 0 ] && exit 0` 조기반환을 제거. **비권장** — 사람의 한국어 수동 커밋을 막는다.

## 유지보수 — 각 층 테스트
- **P0 가드**: 가짜 훅 JSON(`{tool_input:{command},cwd}`)을 스크립트에 파이프해 exit 2/0 확인(실푸시 없이).
- **pre-commit / commit-msg**: 스크래치 git repo·임시 메시지 파일로 훅 스크립트를 직접 실행(실 repo 무변경).
- **bin/ci**: `bin/ci` 적→녹 — grant 하나 빼면 `rls:grant_audit` abort · 빈 dev DB면 `smoke` 실패.
