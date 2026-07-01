source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# PostgreSQL — primary DB (tenant isolation + RLS; ADR-002 §7 / ADR-003 P1)
gem "pg", "~> 1.5"
# 마이그레이션 안전 — unsafe 마이그(컬럼 drop·NOT NULL 추가 등)를 dev/CI에서 차단하고 expand-contract 대안 제시.
# 리프레임 중 겪은 stale-schema/파괴적 변경 부류를 배포 전에 잡는 규율 게이트(R4).
gem "strong_migrations", "~> 2.0"
# sqlite3 retained transitionally (legacy demo storage / fallback); removable once fully on PG
gem "sqlite3", ">= 2.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Use Tailwind CSS [https://github.com/rails/tailwindcss-rails]
gem "tailwindcss-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Authorization (ADR-002 Layer B) — native Pundit policies; Cerbos at microservices extraction
gem "pundit", "~> 2.4"

# Authentication broker (ADR-003 Phase 2b) — OIDC RP for Keycloak (maintained underscore gem) +
# request-phase CSRF protection (CVE-2015-9284). Active only when KC_ISSUER is set (or in test).
gem "omniauth_openid_connect", "~> 0.8"
gem "omniauth-rails_csrf_protection", "~> 1.0"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
# gem "bcrypt", "~> 3.1.7"

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Audits gems for known security defects (use config/bundler-audit.yml to ignore issues)
  gem "bundler-audit", require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"

  # N+1 쿼리 감지 — dev에서 브라우저/로그로 즉시 노출(R5). prosopite(test)와 짝.
  gem "bullet"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"

  # N+1 게이트 — critical path 통합 테스트에서 Prosopite.scan으로 N+1이면 fail(R5). bullet보다 엄격.
  gem "prosopite"
  gem "pg_query" # prosopite의 SQL 지문(fingerprint) 정확화 — scan에 필수

end

gem "rotp", "~> 6.3"

gem "capybara-playwright-driver", "~> 0.5.9", group: :test
