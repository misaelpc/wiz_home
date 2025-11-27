defmodule WizHomeWeb.LightsLive do
  use Phoenix.LiveView,
    layout: {WizHomeWeb.Layouts, :dashboard}

  use WizHomeWeb, :html

  alias WizHome.Lights
  alias WizHome.Lights.Bulb

  import WizHomeWeb.Components.Card

  @impl true
  def mount(_params, _session, socket) do
    bulbs = Lights.list_bulbs()

    default_color = %{r: 255, g: 255, b: 255, brightness: 75, temperature: nil}
    default_hsl = rgb_to_hsl(default_color)

    socket =
      socket
      |> assign(:bulbs, bulbs)
      |> assign(:selected_bulb, nil)
      |> assign(:color, default_color)
      |> assign(:color_hsl, default_hsl)
      |> assign(:form, to_form(Bulb.changeset(%Bulb{}, %{})))
      |> assign(:current_section, "register")
      |> assign(:sidebar_open, false)
      |> assign(:user_dropdown_open, false)
      |> assign(:show_color_modal, false)
      |> assign(:color_modal_mode, :single) # :single or :all

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    section = Map.get(params, "section", "register")

    # Validate section - default to register if invalid
    current_section = if section in ["register", "admin"], do: section, else: "register"

    socket = assign(socket, :current_section, current_section)

    # Redirect if section was invalid
    socket =
      if current_section != section do
        push_patch(socket, to: ~p"/lights/#{current_section}")
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_sidebar", _params, socket) do
    {:noreply, assign(socket, :sidebar_open, !socket.assigns.sidebar_open)}
  end

  @impl true
  def handle_event("toggle_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :user_dropdown_open, !socket.assigns.user_dropdown_open)}
  end

  @impl true
  def handle_event("close_user_dropdown", _params, socket) do
    {:noreply, assign(socket, :user_dropdown_open, false)}
  end

  @impl true
  def handle_event("add_bulb", %{"bulb" => bulb_params}, socket) do
    case Lights.create_bulb(bulb_params) do
      {:ok, _bulb} ->
        bulbs = Lights.list_bulbs()

        socket =
          socket
          |> put_flash(:info, "Bulb added successfully")
          |> assign(:bulbs, bulbs)
          |> assign(:form, to_form(Bulb.changeset(%Bulb{}, %{})))

        {:noreply, socket}

      {:error, changeset} ->
        socket =
          socket
          |> put_flash(:error, "Failed to add bulb")
          |> assign(:form, to_form(changeset))

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_bulb", %{"id" => id}, socket) do
    bulb = Lights.get_bulb!(id)
    Lights.delete_bulb(bulb)

    bulbs = Lights.list_bulbs()

    socket =
      socket
      |> put_flash(:info, "Bulb removed")
      |> assign(:bulbs, bulbs)
      |> assign(:selected_bulb, if(socket.assigns.selected_bulb && socket.assigns.selected_bulb.id == String.to_integer(id), do: nil, else: socket.assigns.selected_bulb))

    {:noreply, socket}
  end

  @impl true
  def handle_event("select_bulb", %{"id" => id}, socket) do
    bulb = Lights.get_bulb!(id)

    color =
      cond do
        # If temperature is set, use it
        bulb.last_temperature ->
          {r, g, b} = kelvin_to_rgb(bulb.last_temperature)
          %{
            r: r,
            g: g,
            b: b,
            brightness: bulb.last_brightness || 75,
            temperature: bulb.last_temperature
          }
        # Otherwise use RGB if available
        bulb.last_color_r && bulb.last_color_g && bulb.last_color_b && bulb.last_brightness ->
          %{
            r: bulb.last_color_r,
            g: bulb.last_color_g,
            b: bulb.last_color_b,
            brightness: bulb.last_brightness,
            temperature: nil
          }
        # Default
        true ->
          %{r: 255, g: 255, b: 255, brightness: 75, temperature: nil}
      end

    hsl = rgb_to_hsl(color)

    socket =
      socket
      |> assign(:selected_bulb, bulb)
      |> assign(:color, color)
      |> assign(:original_color, color) # Store original color for cancel
      |> assign(:color_hsl, hsl)
      |> assign(:color_modal_mode, :single)
      |> assign(:show_color_modal, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("open_global_color_modal", _params, socket) do
    # Use default color or last used color
    color = Map.put_new(socket.assigns.color, :temperature, nil)
    hsl = rgb_to_hsl(color)

    socket =
      socket
      |> assign(:color, color)
      |> assign(:original_color, color) # Store original color for cancel
      |> assign(:color_hsl, hsl)
      |> assign(:color_modal_mode, :all)
      |> assign(:show_color_modal, true)

    {:noreply, socket}
  end

  @impl true
  def handle_event("close_color_modal", _params, socket) do
    # Restore original color when canceling
    original_color = socket.assigns.original_color || socket.assigns.color
    hsl = rgb_to_hsl(original_color)

    socket =
      socket
      |> assign(:show_color_modal, false)
      |> assign(:color, original_color)
      |> assign(:color_hsl, hsl)

    {:noreply, socket}
  end

  @impl true
  def handle_event("color_changed", %{"r" => r, "g" => g, "b" => b}, socket) do
    # When color wheel changes, clear temperature (using RGB mode)
    # Keep saturation at 100% and lightness at 50% for vibrant colors
    updated_color = Map.merge(socket.assigns.color, %{r: r, g: g, b: b, temperature: nil})
    hsl = rgb_to_hsl(updated_color)
    {:noreply, socket |> assign(:color, updated_color) |> assign(:color_hsl, hsl)}
  end

  @impl true
  def handle_event("update_color", params, socket) do
    # Handle both formats: %{"color" => %{"r" => "123"}} or direct params
    color_params = Map.get(params, "color", params)

    updated_color =
      socket.assigns.color
      |> Map.merge(atomize_color_params(color_params))

    # If temperature is being set, convert to RGB for preview
    updated_color =
      if Map.has_key?(updated_color, :temperature) && updated_color.temperature do
        {r, g, b} = kelvin_to_rgb(updated_color.temperature)
        Map.merge(updated_color, %{r: r, g: g, b: b})
      else
        updated_color
      end

    hsl = rgb_to_hsl(updated_color)
    {:noreply, socket |> assign(:color, updated_color) |> assign(:color_hsl, hsl)}
  end

  @impl true
  def handle_event("update_temperature", %{"temperature" => temp_str}, socket) do
    case Integer.parse(temp_str) do
      {temp, _} when temp >= 2200 and temp <= 6500 ->
        {r, g, b} = kelvin_to_rgb(temp)
        # When temperature is set, use temperature mode (ignore hue wheel)
        # Convert Kelvin to RGB for preview only, but use set_temp when applying
        updated_color = Map.merge(socket.assigns.color, %{temperature: temp, r: r, g: g, b: b})
        hsl = rgb_to_hsl(updated_color)
        {:noreply, socket |> assign(:color, updated_color) |> assign(:color_hsl, hsl)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_color_from_hex", params, socket) do
    # HTML5 color input sends value directly or as "hex" depending on name attribute
    hex = params["hex"] || params["value"] || Map.values(params) |> List.first()

    if hex do
      {r, g, b} = hex_to_rgb(hex)
      color = Map.merge(socket.assigns.color, %{r: r, g: g, b: b})
      hsl = rgb_to_hsl(color)

      {:noreply, socket |> assign(:color, color) |> assign(:color_hsl, hsl)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_color", _params, socket) do
    color = socket.assigns.color
    mode = socket.assigns.color_modal_mode

    case mode do
      :all ->
        # Apply to all bulbs
        bulbs = socket.assigns.bulbs

        results =
          Enum.map(bulbs, fn bulb ->
            result =
              if color.temperature do
                # Use temperature if set
                WizHome.set_temp(bulb.ip, color.temperature, color.brightness)
              else
                # Otherwise use RGB
                WizHome.set_rgb(bulb.ip, {color.r, color.g, color.b}, color.brightness)
              end

            case result do
              {:ok, _} ->
                # Update bulb color in database
                Lights.update_bulb_color(bulb, %{
                  last_color_r: color.r,
                  last_color_g: color.g,
                  last_color_b: color.b,
                  last_brightness: color.brightness,
                  last_temperature: color.temperature
                })
                {:ok, bulb}

              {:error, reason} ->
                {:error, bulb, reason}
            end
          end)

        successful = Enum.filter(results, fn r -> match?({:ok, _}, r) end)
        failed = Enum.filter(results, fn r -> match?({:error, _, _}, r) end)

        bulbs = Lights.list_bulbs()

        socket =
          socket
          |> put_flash(
            :info,
            "Color applied to #{length(successful)} light(s)#{if length(failed) > 0, do: ", #{length(failed)} failed", else: ""}"
          )
          |> assign(:bulbs, bulbs)
          |> assign(:show_color_modal, false)

        {:noreply, socket}

      :single ->
        # Apply to single bulb
        if socket.assigns.selected_bulb do
          bulb = socket.assigns.selected_bulb

          # Update bulb color in database
          Lights.update_bulb_color(bulb, %{
            last_color_r: color.r,
            last_color_g: color.g,
            last_color_b: color.b,
            last_brightness: color.brightness,
            last_temperature: color.temperature
          })

          # Apply color to light (use temperature if set, otherwise RGB)
          result =
            if color.temperature do
              WizHome.set_temp(bulb.ip, color.temperature, color.brightness)
            else
              WizHome.set_rgb(bulb.ip, {color.r, color.g, color.b}, color.brightness)
            end

          case result do
            {:ok, _} ->
              bulbs = Lights.list_bulbs()

              socket =
                socket
                |> put_flash(:info, "Color applied to #{bulb.name || bulb.ip}")
                |> assign(:bulbs, bulbs)
                |> assign(:selected_bulb, Lights.get_bulb!(bulb.id))
                |> assign(:show_color_modal, false)

              {:noreply, socket}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Failed to set color: #{inspect(reason)}")}
          end
        else
          {:noreply, put_flash(socket, :error, "Please select a bulb first")}
        end
    end
  end

  @impl true
  def handle_event("set_all_color", _params, socket) do
    color = socket.assigns.color
    bulbs = socket.assigns.bulbs

    results =
      Enum.map(bulbs, fn bulb ->
        case WizHome.set_rgb(bulb.ip, {color.r, color.g, color.b}, color.brightness) do
          {:ok, _} ->
            # Update bulb color in database
            Lights.update_bulb_color(bulb, %{
              last_color_r: color.r,
              last_color_g: color.g,
              last_color_b: color.b,
              last_brightness: color.brightness
            })
            {:ok, bulb}
          {:error, reason} -> {:error, bulb, reason}
        end
      end)

    {successful, failed} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _, _} -> false
      end)

    bulbs = Lights.list_bulbs()

    socket =
      socket
      |> put_flash(
        :info,
        "Color applied to #{length(successful)} bulb(s)#{if length(failed) > 0, do: ", #{length(failed)} failed", else: ""}"
      )
      |> assign(:bulbs, bulbs)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_light", %{"id" => id}, socket) do
    bulb = Lights.get_bulb!(id)

    # Get current status to determine new state
    case WizHome.get_status(bulb.ip) do
      {:ok, %{"result" => %{"state" => current_state}}} ->
        new_state = !current_state

        case WizHome.set_state(bulb.ip, new_state) do
          {:ok, _} ->
            bulbs = Lights.list_bulbs()

            socket =
              socket
              |> put_flash(:info, "Light #{if new_state, do: "turned on", else: "turned off"}")
              |> assign(:bulbs, bulbs)

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to toggle light: #{inspect(reason)}")}
        end

      {:error, _reason} ->
        # If we can't get status, try to turn it on
        case WizHome.set_state(bulb.ip, true) do
          {:ok, _} ->
            bulbs = Lights.list_bulbs()

            socket =
              socket
              |> put_flash(:info, "Light turned on")
              |> assign(:bulbs, bulbs)

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to toggle light: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("set_all_state", %{"state" => state_str}, socket) do
    state = state_str == "true"
    bulbs = socket.assigns.bulbs

    results =
      Enum.map(bulbs, fn bulb ->
        case WizHome.set_state(bulb.ip, state) do
          {:ok, _} -> {:ok, bulb}
          {:error, reason} -> {:error, bulb, reason}
        end
      end)

    {successful, failed} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        {:error, _, _} -> false
      end)

    bulbs = Lights.list_bulbs()

    socket =
      socket
      |> put_flash(
        :info,
        "#{length(successful)} light(s) #{if state, do: "turned on", else: "turned off"}#{if length(failed) > 0, do: ", #{length(failed)} failed", else: ""}"
      )
      |> assign(:bulbs, bulbs)

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_preset_color", %{"color" => color_name}, socket) do
    color = preset_color(color_name)
    hsl = rgb_to_hsl(color)
    {:noreply, socket |> assign(:color, color) |> assign(:color_hsl, hsl)}
  end

  # Helper functions

  defp atomize_color_params(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      case Integer.parse(value) do
        {int, _} -> Map.put(acc, String.to_existing_atom(key), int)
        :error -> acc
      end
    end)
  end

  defp hex_to_rgb(hex) when is_binary(hex) do
    hex = String.replace(hex, "#", "")
    {r, _} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, _} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, _} = Integer.parse(String.slice(hex, 4, 2), 16)
    {r, g, b}
  end

  defp rgb_to_hsl(%{r: r, g: g, b: b}) do
    r_norm = r / 255
    g_norm = g / 255
    b_norm = b / 255

    max = Enum.max([r_norm, g_norm, b_norm])
    min = Enum.min([r_norm, g_norm, b_norm])
    delta = max - min

    l = (max + min) / 2

    {h, s} =
      if delta == 0 do
        {0, 0}
      else
        s =
          if l < 0.5 do
            delta / (max + min)
          else
            delta / (2 - max - min)
          end

        h_raw =
          cond do
            r_norm == max -> (g_norm - b_norm) / delta
            g_norm == max -> (b_norm - r_norm) / delta + 2
            b_norm == max -> (r_norm - g_norm) / delta + 4
            true -> 0
          end

        # Normalize to 0-6 range
        h_raw = h_raw - trunc(h_raw / 6) * 6
        h = h_raw * 60
        h = if h < 0, do: h + 360, else: h

        {h, s * 100}
      end

    %{hue: h, saturation: s, lightness: l * 100}
  end

  # Preset colors optimized for coding/productivity
  defp preset_color("deep_blue"), do: %{r: 0, g: 0, b: 139, brightness: 75, temperature: nil}  # Deep Blue (Calm Focus)
  defp preset_color("soft_teal"), do: %{r: 64, g: 224, b: 208, brightness: 75, temperature: nil}  # Soft Teal (Balanced Productivity)
  defp preset_color("cool_green"), do: %{r: 0, g: 128, b: 128, brightness: 75, temperature: nil}  # Cool Green (Refresh and Clarity)
  defp preset_color("muted_cyan"), do: %{r: 0, g: 191, b: 255, brightness: 75, temperature: nil}  # Muted Cyan (Tech Zen Mode)
  defp preset_color("warm_white"), do: %{r: 255, g: 244, b: 229, brightness: 75, temperature: nil}  # Warm White (Evening Wind Down)
  defp preset_color("pure_white"), do: %{r: 255, g: 255, b: 255, brightness: 75, temperature: nil}  # Pure White
  defp preset_color(_), do: %{r: 255, g: 255, b: 255, brightness: 75, temperature: nil}

  # Convert Kelvin temperature to RGB
  # Based on the algorithm from Tanner Helland: http://www.tannerhelland.com/4435/convert-temperature-rgb-algorithm-code/
  defp kelvin_to_rgb(kelvin) when kelvin >= 2200 and kelvin <= 6500 do
    # Normalize temperature to 0-1 range
    temp = kelvin / 100.0

    # Calculate red
    r =
      cond do
        temp <= 66 -> 255
        true ->
          red = temp - 60
          red = 329.698727446 * :math.pow(red, -0.1332047592)
          red = max(0, min(255, red))
          round(red)
      end

    # Calculate green
    g =
      cond do
        temp <= 66 ->
          green = temp
          green = 99.4708025861 * :math.log(green) - 161.1195681661
          green = max(0, min(255, green))
          round(green)
        true ->
          green = temp - 60
          green = 288.1221695283 * :math.pow(green, -0.0755148492)
          green = max(0, min(255, green))
          round(green)
      end

    # Calculate blue
    b =
      cond do
        temp >= 66 -> 255
        temp <= 19 -> 0
        true ->
          blue = temp - 10
          blue = 138.5177312231 * :math.log(blue) - 305.0447927307
          blue = max(0, min(255, blue))
          round(blue)
      end

    {r, g, b}
  end

  defp kelvin_to_rgb(_), do: {255, 255, 255}
end
