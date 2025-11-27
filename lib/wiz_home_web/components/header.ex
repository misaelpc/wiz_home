defmodule WizHomeWeb.Components.Header do
  @moduledoc """
  Renders the header component for the dashboard.
  """
  use WizHomeWeb, :html

  attr :user_dropdown_open, :boolean, default: false

  def header(assigns) do
    ~H"""
    <header class="fixed left-0 top-0 flex w-full bg-white dark:bg-boxdark ease-linear duration-300 z-999 shadow-2">
      <!-- App Name Section -->
      <div class="flex items-center shadow-2 lg:shadow-none lg:w-72.5 py-4 px-4 lg:px-5">
        <a class="flex items-center gap-3" href={~p"/lights/register"}>
          <span class="hidden lg:block text-[#0C1C2E] dark:text-white mt-2.5 font-semibold text-title-md">
            Elixir Home Control
          </span>
          <span class="lg:hidden text-[#0C1C2E] dark:text-white mt-2.5 font-semibold text-title-sm">
            Elixir Home Control
          </span>
        </a>
      </div>

      <!-- Right Section: User Menu -->
      <div class="flex flex-grow items-center justify-end shadow-2 py-4 px-4 md:px-6 2xl:px-11">
        <div class="flex items-center gap-7">
          <!-- User Area -->
          <div class="relative">
            <button
              phx-click="toggle_user_dropdown"
              class="flex items-center gap-4"
            >
              <span class="hidden lg:block text-right">
                <span class="block font-medium text-sm text-black dark:text-white">
                  misaelpc
                </span>
                <span class="block text-xs text-body dark:text-bodydark">User</span>
              </span>

              <span class="rounded-full border bg-gray border-stroke dark:border-strokedark p-1">
                <div class="w-8 h-8 rounded-full bg-primary flex items-center justify-center">
                  <span class="text-white text-sm font-semibold">M</span>
                </div>
              </span>

              <svg
                class={[
                  "fill-body dark:fill-bodydark hidden sm:block ease-linear duration-150",
                  if(@user_dropdown_open, do: "rotate-180", else: "")
                ]}
                width="12"
                height="8"
                viewBox="0 0 12 8"
                fill="none"
                xmlns="http://www.w3.org/2000/svg"
              >
                <path
                  fill-rule="evenodd"
                  clip-rule="evenodd"
                  d="M0.410765 0.910734C0.736202 0.585297 1.26384 0.585297 1.58928 0.910734L6.00002 5.32148L10.4108 0.910734C10.7362 0.585297 11.2638 0.585297 11.5893 0.910734C11.9147 1.23617 11.9147 1.76381 11.5893 2.08924L6.58928 7.08924C6.26384 7.41468 5.7362 7.41468 5.41077 7.08924L0.410765 2.08924C0.0853277 1.76381 0.0853277 1.23617 0.410765 0.910734Z"
                  fill=""
                />
              </svg>
            </button>

            <!-- Dropdown Menu -->
            <div
              phx-click-away="close_user_dropdown"
              class={[
                "dropdown bg-white dark:bg-boxdark w-62.5 right-0 mt-4",
                if(@user_dropdown_open, do: "block", else: "hidden")
              ]}
            >
              <ul class="flex flex-col gap-5 border-b border-stroke dark:border-strokedark px-6 py-7.5">
                <li>
                  <a
                    href="#"
                    class="font-medium text-sm lg:text-base flex items-center gap-3.5 ease-in-out duration-300 hover:text-primary"
                  >
                    <.icon name="hero-user-circle" class="w-5 h-5 fill-current" />
                    My Profile
                  </a>
                </li>
                <li>
                  <a
                    href="#"
                    class="font-medium text-sm lg:text-base flex items-center gap-3.5 ease-in-out duration-300 hover:text-primary"
                  >
                    <.icon name="hero-cog-6-tooth" class="w-5 h-5 fill-current" />
                    Account Settings
                  </a>
                </li>
              </ul>
              <button class="font-medium text-sm lg:text-base flex items-center gap-3.5 ease-in-out duration-300 hover:text-primary py-4 px-6 w-full text-left">
                <.icon name="hero-arrow-right-on-rectangle" class="w-5 h-5 fill-current" />
                Log Out
              </button>
            </div>
          </div>
          <!-- User Area End -->
        </div>
      </div>
    </header>
    """
  end
end
