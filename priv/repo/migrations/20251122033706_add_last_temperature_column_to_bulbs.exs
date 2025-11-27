defmodule WizHome.Repo.Migrations.AddLastTemperatureColumnToBulbs do
  use Ecto.Migration

  def change do
    alter table(:bulbs) do
      add :last_temperature, :integer
    end
  end
end
