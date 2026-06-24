class AddNameToComponents < ActiveRecord::Migration[8.1]
  def up
    add_column :components, :name, :string
    # 기존 enum 라벨로 백필
    { "outer_box" => "단상자", "container" => "용기", "insert" => "인서트지",
      "barcode" => "바코드", "etc" => "기타" }.each do |type, label|
      execute "UPDATE components SET name = '#{label}' WHERE component_type = '#{type}'"
    end
    # 자유 이름 구성요소는 type 없이 생성되므로 nullable로
    change_column_null :components, :component_type, true
  end

  def down
    change_column_null :components, :component_type, false
    remove_column :components, :name
  end
end
