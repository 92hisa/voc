# オーディエンス（誰の声を集めるか）のテーブルを作る。slug は URL とタスク引数に使うので一意。
class CreateAudiences < ActiveRecord::Migration[8.1]
  def change
    create_table :audiences do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.text :description

      t.timestamps
    end

    add_index :audiences, :slug, unique: true
  end
end
