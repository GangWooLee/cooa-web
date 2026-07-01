# 마이그레이션 안전 게이트(R4 · docs/dev-discipline.md).
# 채택 이전 마이그(≤ 20260701000004)는 이미 배포/검증됨 → 검사 제외. 신규 마이그만 unsafe 패턴
# (컬럼 drop·NOT NULL 즉시 추가·인덱스 비동시 생성 등)에서 실패시키고 expand-contract 대안을 안내.
StrongMigrations.start_after = 2026_07_01_000004

# 대상 Postgres 메이저(17) — 버전별 안전 규칙(add_index CONCURRENTLY, NOT NULL 검증 분리 등)을 정밀화.
StrongMigrations.target_version = 17
