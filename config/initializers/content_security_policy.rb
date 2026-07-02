# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

# 사용자 업로드(PDF 포함)를 다루는 앱의 최소 하드닝. 앱이 실제로 쓰지 않는 표면만 차단해 무회귀:
#  - object_src :none      → <object>/<embed> 플러그인 기반 PDF/Flash 실행 차단(우리는 PDF.js 캔버스로 렌더)
#  - base_uri :self        → <base> 태그 주입으로 상대경로 하이재킹 차단
#  - frame_ancestors :self → 외부 사이트 프레이밍(클릭재킹) 차단
# script_src/style_src는 인라인 스타일·importmap 인라인 JSON이 많아 nonce 정비가 선행되어야 하므로
# 이번엔 설정하지 않는다(default_src 미설정 → 해당 지시문은 무제한 = 무회귀). 후속 보안 트랙에서
# nonce 기반 script/style 제한을 도입. PDF.js CVE-2024-4367은 isEvalSupported:false + 버전 고정(5.4.149
# ≥ 4.2.67)으로 이미 완화됨(artwork_viewer_controller).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.object_src      :none
    policy.base_uri        :self
    policy.frame_ancestors :self
  end
end
