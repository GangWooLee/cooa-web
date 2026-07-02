# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# PDF.js(pdfjs-dist 5.4.149 legacy ESM) — vendored(vendor/javascript, 공급망 안전·오프라인). PDF 아트워크
# 뷰어에서 동적 import로만 로드(이미지 버전엔 미로드). worker는 모듈이 아니라 URL이라 핀하지 않고
# asset_path로 뷰에서 주입(artwork_viewer_controller). 메인·worker 동일 버전 필수.
# 확장자 .js — propshaft가 .mjs엔 JS content-type 미부여로 모듈 로드 실패(모듈성은 importmap이 부여).
# preload:false — 기본 modulepreload가 452KB를 모든 페이지에 선로드해 "PDF 뷰에서만 동적 import"
# 의도를 무효화(PERF-1). 뷰어의 import("pdfjs-dist") 시점에만 fetch.
pin "pdfjs-dist", to: "pdfjs.min.js", preload: false
pin_all_from "app/javascript/controllers", under: "controllers"
