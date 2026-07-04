# frozen_string_literal: true

# 관측 골격(E7 · docs/error-handling.md). Rails.error(ActiveSupport::ErrorReporter)에 보고된 모든 예외를
# 구조화된 한 줄 로그로 남긴다. PII(이메일·이름·요청 본문)는 남기지 않는다 — 식별자(tenant / request_id /
# controller#action)와 예외 클래스·메시지만. controller/action/request_id는 Rails가 요청 중 error 컨텍스트에
# 실어주는 컨트롤러 인스턴스(context[:controller])에서 파생한다 — 이 예약 키를 우리가 String으로 덮어쓰면
# Rails 내부가 인스턴스로 기대하고 .action_name을 호출하다 깨진다(그래서 set_context를 쓰지 않는다).
#
# 배포 시 이 지점이 외부 리포터(Sentry 등) 연결 지점이다 — Sentry.init(dsn:) 후 Sentry가 자체 subscriber를
# 등록하거나, 아래 report 본문에서 Sentry.capture_exception(error, ...)를 호출하면 된다. APM 연동도 여기.
module CooaErrorReporting
  def self.report(error, handled:, severity:, context:, source: nil, **)
    ctrl = context[:controller]
    path = ctrl.respond_to?(:controller_path) ? ctrl.controller_path : nil
    action = ctrl.respond_to?(:action_name) ? ctrl.action_name : nil
    request_id = ctrl.respond_to?(:request) && ctrl.request ? ctrl.request.request_id : context[:request_id]
    Rails.logger.error(
      "[error_report] class=#{error.class} handled=#{handled} severity=#{severity} " \
      "source=#{source} controller=#{path} action=#{action} " \
      "request_id=#{request_id} tenant=#{Current.tenant_id} " \
      "msg=#{error.message.to_s.truncate(200)}"
    )
  rescue StandardError => e
    # 리포터 자신은 절대 요청/잡을 깨뜨리면 안 된다(best-effort).
    Rails.logger.error("[error_report] reporter failed: #{e.class}")
  end
end

Rails.error.subscribe(CooaErrorReporting)
