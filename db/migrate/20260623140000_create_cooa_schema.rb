# COOA 데모 전체 스키마 — 한 번에 생성 (참조 순서대로 테이블 정의)
class CreateCooaSchema < ActiveRecord::Migration[8.1]
  def change
    # 사용자 / 팀원 (담당자)
    create_table :users do |t|
      t.string :name, null: false
      t.string :email
      t.string :role, null: false, default: "pm"   # designer/pm/ra/scm
      t.string :avatar_color, default: "#8e0300"
      t.timestamps
    end

    # 품목 (제품) — 자기참조 트리(노션형). 루트=상위 개념, 자식=변형(국가·용량 등)
    create_table :products do |t|
      t.references :parent, foreign_key: { to_table: :products }  # 트리 부모(루트는 null)
      t.references :owner, foreign_key: { to_table: :users }
      t.string :code                       # 품목코드 CO0000 (leaf SKU만)
      t.string :name, null: false          # 노드 표시명 (루트=레티놀 3% 세럼, 자식=미국/30ml)
      t.string :country                    # 국가 (미국/일본)
      t.string :channel                    # 채널 (Sephora/QTEN)
      t.string :product_type, default: "기획"
      t.string :notion_url
      t.date :deadline                     # 기한
      t.integer :position, default: 0
      t.timestamps
    end

    # 품목 팀멤버 (역할별)
    create_table :product_members do |t|
      t.references :product, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :role, null: false          # designer/pm/ra/scm
      t.timestamps
    end

    # 구성요소 (단상자/용기/인서트지/바코드/기타)
    create_table :components do |t|
      t.references :product, null: false, foreign_key: true
      t.string :component_type, null: false  # outer_box/container/insert/barcode/etc
      t.integer :position, default: 0
      t.timestamps
    end

    # 구성요소 버전 (v1..v6)
    create_table :component_versions do |t|
      t.references :component, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.integer :version_number, null: false
      t.string :label                       # [CO00001]
      t.string :change_reason               # 변경사유
      t.string :image_name                  # app/assets/images/cooa/box_v5.jpg
      t.boolean :current, default: false     # 현재 선택 버전(빨강 테두리)
      t.timestamps
    end

    # 성분 (INCI, 배합비 없음)
    create_table :ingredients do |t|
      t.references :component_version, null: false, foreign_key: true
      t.string :inci_name
      t.string :inci_canonical
      t.string :cas
      t.decimal :declared_pct, precision: 6, scale: 2  # 라벨에 선언된 농도(% — 배합비 아님)
      t.integer :position, default: 0
      t.timestamps
    end

    # 라벨/문구 텍스트
    create_table :label_texts do |t|
      t.references :component_version, null: false, foreign_key: true
      t.string :text_type, default: "label"   # label/ad/ingredient_list/other
      t.text :content
      t.string :language
      t.string :country
      t.timestamps
    end

    # 어노테이션 = 아트워크 위 바운딩박스 피드백 (위치 + 카테고리 + 해소상태)
    create_table :annotations do |t|
      t.references :component_version, null: false, foreign_key: true       # 제기된 버전
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :resolved_in_version, foreign_key: { to_table: :component_versions } # 반영 확인된 버전
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.integer :seq                          # 순번 1,2,3...
      t.float :box_x                          # 바운딩박스 % 좌표(0~100)
      t.float :box_y
      t.float :box_w
      t.float :box_h
      t.string :category                      # 오탈자/인허가/디자인/기타
      t.string :before_text                   # (선택) 이전 표기
      t.string :after_text                    # (선택) 수정 표기
      t.string :status, default: "open"       # open/resolved/dismissed
      t.datetime :resolved_at
      t.integer :position, default: 0
      t.timestamps
    end

    # 어노테이션 코멘트 스레드 (담당자 피드백 + 답글)
    create_table :annotation_comments do |t|
      t.references :annotation, null: false, foreign_key: true
      t.references :author, null: false, foreign_key: { to_table: :users }
      t.references :parent, foreign_key: { to_table: :annotation_comments }
      t.text :body
      t.string :attachment_name
      t.timestamps
    end

    # 인허가 스크리닝 실행 (검토 세션)
    create_table :screening_runs do |t|
      t.references :component_version, null: false, foreign_key: true
      t.references :requested_by, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.string :country, null: false
      t.string :status, default: "completed"  # pending/completed/approved
      t.string :decision                      # ok/warning/violation/unable
      t.text :summary
      t.datetime :approved_at
      t.timestamps
    end

    # 스크리닝 결과 (finding)
    create_table :screening_findings do |t|
      t.references :screening_run, null: false, foreign_key: true
      t.string :element_type                  # ingredient/label/ad/design
      t.string :decision                      # ok/warning/violation/unable
      t.string :severity                      # Critical/Major/Minor
      t.string :subject                       # 대상(성분명/항목명)
      t.text :issue_description
      t.text :recommended_action
      t.string :citation
      t.integer :confidence, default: 80
      t.boolean :human_review_required, default: false
      t.float :box_x                          # 아트워크 위 finding 위치(% 좌표)
      t.float :box_y
      t.float :box_w
      t.float :box_h
      t.integer :position, default: 0
      t.timestamps
    end

    # === 규제 데이터 (큐레이션 시드) ===
    create_table :ingredient_limits do |t|
      t.string :country, null: false
      t.string :inci_canonical, null: false
      t.string :cas
      t.string :restriction_type              # banned/max_concentration/unrestricted/...
      t.decimal :max_pct, precision: 8, scale: 4
      t.string :max_pct_unit
      t.string :category
      t.string :citation
      t.string :source_url
      t.string :fact_id
      t.string :status
      t.timestamps
    end

    create_table :label_requirements do |t|
      t.string :country, null: false
      t.string :item
      t.text :required_text
      t.string :location
      t.string :citation
      t.string :fact_id
      t.string :parent_law
      t.string :match_keyword   # 라벨 텍스트에서 충족 여부 탐지용(파이프 구분)
      t.timestamps
    end

    create_table :ad_risk_expressions do |t|
      t.string :country, null: false
      t.string :keyword_native
      t.string :keyword_ko
      t.string :risk_level
      t.text :classification_trigger
      t.string :citation
      t.string :fact_id
      t.timestamps
    end

    add_index :ingredient_limits, [ :country, :inci_canonical ]
    add_index :ad_risk_expressions, :country
    add_index :label_requirements, :country
    add_index :components, [ :product_id, :position ]
    add_index :component_versions, [ :component_id, :version_number ]
    add_index :annotations, [ :component_version_id, :seq ]
  end
end
