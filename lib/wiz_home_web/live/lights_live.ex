defmodule WizHomeWeb.LightsLive do
  use WizHomeWeb, :live_view

  alias WizHome.Lights
  alias WizHome.Lights.Bulb

  @impl true
  def mount(_params, _session, socket) do
    bulbs = Lights.list_bulbs()

    socket =
      socket
      |> assign(:bulbs, bulbs)
      |> assign(:selected_bulb, nil)
      |> assign(:color, %{r: 255, g: 255, b: 255, brightness: 75})
      |> assign(:form, to_form(Bulb.changeset(%Bulb{}, %{})))

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
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
      if bulb.last_color_r && bulb.last_color_g && bulb.last_color_b && bulb.last_brightness do
        %{
          r: bulb.last_color_r,
          g: bulb.last_color_g,
          b: bulb.last_color_b,
          brightness: bulb.last_brightness
        }
      else
        %{r: 255, g: 255, b: 255, brightness: 75}
      end

    socket =
      socket
      |> assign(:selected_bulb, bulb)
      |> assign(:color, color)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_color", %{"color" => color_params}, socket) do
    color =
      socket.assigns.color
      |> Map.merge(atomize_color_params(color_params))

    {:noreply, assign(socket, :color, color)}
  end

  @impl true
  def handle_event("update_color_from_hex", params, socket) do
    # HTML5 color input sends value directly or as "hex" depending on name attribute
    hex = params["hex"] || params["value"] || Map.values(params) |> List.first()

    if hex do
      {r, g, b} = hex_to_rgb(hex)
      color = Map.merge(socket.assigns.color, %{r: r, g: g, b: b})

      {:noreply, assign(socket, :color, color)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_color", _params, socket) do
    if socket.assigns.selected_bulb do
      bulb = socket.assigns.selected_bulb
      color = socket.assigns.color

      # Update bulb color in database
      Lights.update_bulb_color(bulb, %{
        last_color_r: color.r,
        last_color_g: color.g,
        last_color_b: color.b,
        last_brightness: color.brightness
      })

      # Apply color to light
      case WizHome.set_rgb(bulb.ip, {color.r, color.g, color.b}, color.brightness) do
        {:ok, _} ->
          bulbs = Lights.list_bulbs()

          socket =
            socket
            |> put_flash(:info, "Color applied to #{bulb.name || bulb.ip}")
            |> assign(:bulbs, bulbs)
            |> assign(:selected_bulb, Lights.get_bulb!(bulb.id))

          {:noreply, socket}

        {:error, reason} ->
          socket =
            socket
            |> put_flash(:error, "Failed to set color: #{inspect(reason)}")

          {:noreply, socket}
      end
    else
      {:noreply, put_flash(socket, :error, "Please select a bulb first")}
    end
  end

  @impl true
  def handle_event("set_all_color", _params, socket) do
    color = socket.assigns.color
    bulbs = socket.assigns.bulbs

    results =
      Enum.map(bulbs, fn bulb ->
        case WizHome.set_rgb(bulb.ip, {color.r, color.g, color.b}, color.brightness) do
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
    {:noreply, assign(socket, :color, color)}
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

  defp preset_color("red"), do: %{r: 255, g: 0, b: 0, brightness: 75}
  defp preset_color("blue"), do: %{r: 0, g: 0, b: 255, brightness: 75}
  defp preset_color("green"), do: %{r: 0, g: 255, b: 0, brightness: 75}
  defp preset_color("white"), do: %{r: 255, g: 255, b: 255, brightness: 75}
  defp preset_color("warm_white"), do: %{r: 255, g: 147, b: 41, brightness: 75}
  defp preset_color(_), do: %{r: 255, g: 255, b: 255, brightness: 75}
end
