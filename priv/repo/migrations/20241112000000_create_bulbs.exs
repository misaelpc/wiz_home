defmodule WizHome.Repo.Migrations.CreateBulbs do
  use Ecto.Migration

  def change do
    create table(:bulbs) do
      add :ip, :string, null: false
      add :name, :string
      add :last_color_r, :integer
      add :last_color_g, :integer
      add :last_color_b, :integer
      add :last_brightness, :integer

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bulbs, [:ip])
  end
end
