require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Web
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # RLS policies, FORCE flags, and role grants live in raw SQL (ADR-002 §7).
    # :sql (structure.sql) preserves them across schema load / test DB prep — :ruby (schema.rb) cannot.
    config.active_record.schema_format = :sql

    # Local account-picker login (no password) — dev/test only; production uses the OIDC broker (Phase 2b).
    config.x.local_login_enabled = !Rails.env.production?

    # 승인 서명 step-up(TOTP) 강제 — 기본 ON(prod·test·dev 전부). 데모 한정 단락은 development.rb에서만
    # opt-out(prod에선 production.rb가 무조건 true로 재단언; Part-11 §11.200 불변식).
    config.x.step_up_required = true

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
