defmodule WizHomeWeb.Components.Sidebar do
  @moduledoc """
  Renders the sidebar navigation component.
  """
  use WizHomeWeb, :html

  attr :current_section, :string, required: true
  attr :sidebar_open, :boolean, default: false

  def sidebar(assigns) do
    ~H"""
    <aside
      class={[
        "shadow-2 bg-white dark:bg-boxdark w-72.5 fixed top-22.5 lg:top-19.5 left-0 bottom-0",
        "-translate-x-full lg:translate-x-0 lg:overflow-y-auto no-scrollbar ease-linear duration-300",
        "z-[999]",
        if(@sidebar_open, do: "!translate-x-0 overflow-y-auto", else: "")
      ]}
    >
      <!-- Hamburger Toggle Button (Mobile) -->
      <button
        phx-click="toggle_sidebar"
        class={[
          "lg:hidden block absolute -right-9.5 z-99999 bg-white dark:bg-boxdark",
          "border border-stroke dark:border-strokedark p-1.5 shadow-sm rounded-md",
          if(@sidebar_open, do: "right-0", else: "")
        ]}
      >
        <span class="block relative cursor-pointer w-5.5 h-5.5">
          <span class="du-block absolute right-0 w-full h-full">
            <span
              class={[
                "block relative top-0 left-0 bg-black dark:bg-white rounded-sm h-0.5 my-1 ease-in-out duration-200",
                if(@sidebar_open, do: "w-0 delay-[0]", else: "w-full delay-300")
              ]}
            ></span>
            <span
              class={[
                "block relative top-0 left-0 bg-black dark:bg-white rounded-sm h-0.5 my-1 ease-in-out duration-200 delay-150",
                if(@sidebar_open, do: "w-0 delay-150", else: "w-full delay-400")
              ]}
            ></span>
            <span
              class={[
                "block relative top-0 left-0 bg-black dark:bg-white rounded-sm h-0.5 my-1 ease-in-out duration-200 delay-200",
                if(@sidebar_open, do: "w-0 delay-200", else: "w-full delay-500")
              ]}
            ></span>
          </span>
          <span class="du-block absolute right-0 w-full h-full rotate-45">
            <span
              class={[
                "block bg-black dark:bg-white rounded-sm ease-in-out duration-200 absolute left-2.5 top-0 w-0.5",
                if(@sidebar_open, do: "h-0 delay-[0]", else: "h-full delay-300")
              ]}
            ></span>
            <span
              class={[
                "block bg-black dark:bg-white rounded-sm ease-in-out duration-200 absolute left-0 top-2.5 w-full h-0.5",
                if(@sidebar_open, do: "h-0 delay-200", else: "delay-400")
              ]}
            ></span>
          </span>
        </span>
      </button>

      <!-- Sidebar Menu -->
      <nav class="py-4 px-4 lg:px-5 mt-5 lg:mt-7.5">
        <ul class="flex flex-col gap-1.5">
          <WizHomeWeb.Components.MenuItem.menu_item
            label="Register"
            icon="hero-clipboard-document-list"
            active={@current_section == "register"}
            patch={~p"/lights/register"}
          />
          <WizHomeWeb.Components.MenuItem.menu_item
            label="Admin"
            icon="hero-cog-6-tooth"
            active={@current_section == "admin"}
            patch={~p"/lights/admin"}
          />
        </ul>
      </nav>
    </aside>
    """
  end
end
