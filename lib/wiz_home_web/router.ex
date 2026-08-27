defmodule WizHomeWeb.Router do
  use WizHomeWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WizHomeWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", WizHomeWeb do
    pipe_through :browser

    live_session :lights do
      live "/", LightsLive, :index
      live "/register", LightsLive, :register

      # Legacy URLs from the previous /lights layout
      live "/lights", LightsLive, :legacy_home
      live "/lights/:section", LightsLive, :legacy
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", WizHomeWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:wiz_home, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If you do not have an admins-only section yet, you can
    # use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WizHomeWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
