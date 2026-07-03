# docs/solutions — 엔지니어링 교훈 저장소

`/ce-compound`(compound-engineering)이 최근 해결한 문제·durable 패턴을 여기에 마크다운으로 축적한다.
**커밋되는 팀 공유 지식** — 리뷰·PR·온보딩에서 참조한다. (세션간 *개인* 컨텍스트는 별개 — Claude 메모리에.)

## 무엇이 여기 오나
- 재현 어려웠던 버그의 근본원인 + 재발방지 방법
- 프로젝트 고유 함정 — 예: stale `schema_cache`(R1/R6), owner-run 테스트가 권한결함 은폐(R8), Turbo 교차출처 리다이렉트, INCI 매칭·citation rot
- 되풀이되는 설계 결정의 정립된 답

## 무엇이 안 오나
- 코드가 이미 기록하는 것(구조·git 히스토리) · [dev-discipline.md](../dev-discipline.md)/[harness.md](../harness.md)가 덮는 규율.

파일 하나 = 교훈 하나. 관련: [../dev-discipline.md](../dev-discipline.md) · [../harness.md](../harness.md).
