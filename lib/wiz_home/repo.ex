defmodule WizHome.Repo do
  use Ecto.Repo,
    otp_app: :wiz_home,
    adapter: Ecto.Adapters.SQLite3
end
