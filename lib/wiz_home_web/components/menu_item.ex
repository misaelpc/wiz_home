defmodule WizHomeWeb.Components.MenuItem do
  @moduledoc """
  Renders a menu item for the sidebar navigation.
  """
  use WizHomeWeb, :html

  attr :label, :string, required: true
  attr :icon, :string, default: nil
  attr :active, :boolean, default: false
  attr :navigate, :string, default: nil
  attr :patch, :string, default: nil
  attr :phx_click, :string, default: nil
  attr :class, :string, default: nil

  def menu_item(assigns) do
    ~H"""
    <li>
      <.link
        navigate={@navigate}
        patch={@patch}
        phx-click={@phx_click}
        class={[
          "group relative font-medium flex items-center gap-2.5 rounded-md ease-in-out duration-300 py-2.5 px-4",
          "hover:text-white hover:bg-primary",
          if(@active, do: "text-white bg-primary", else: "text-body dark:text-bodydark"),
          @class
        ]}
      >
        <span :if={@icon} class="flex items-center justify-center">
          <.icon name={@icon} class="w-5 h-5 fill-current" />
        </span>
        {@label}
      </.link>
    </li>
    """
  end
end
