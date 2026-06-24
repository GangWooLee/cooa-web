class AddKindToProducts < ActiveRecord::Migration[8.1]
  def up
    add_column :products, :kind, :string, null: false, default: "item"
    # 백필: 자식을 가진 노드(= 누군가의 parent_id)는 폴더, 나머지는 항목
    Product.reset_column_information
    Product.where(id: Product.where.not(parent_id: nil).select(:parent_id)).update_all(kind: "folder")
  end

  def down
    remove_column :products, :kind
  end
end
