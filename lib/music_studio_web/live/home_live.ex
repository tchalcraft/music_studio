defmodule MusicStudioWeb.HomeLive do
  @moduledoc """
  The public marketing site: a single scrolling page (Hero → About →
  Lessons & Rates → Contact) with an inquiry form wired to `MusicStudio.Leads`.

  Interim implementation while the CMS decision (Beacon vs. alternatives) is pending
  — see the project `checkpoint.md`. The section markup and the `ms-` design-system
  classes port directly into a Beacon page template + site stylesheet later.
  """
  use MusicStudioWeb, :live_view

  alias MusicStudio.Leads
  alias MusicStudio.Leads.Lead
  alias MusicStudio.Leads.Notifier

  @instrument_options [{"Voice", "voice"}, {"Piano", "piano"}, {"Guitar", "guitar"}]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Voice, Piano & Guitar Lessons")
     |> assign(:sent, false)
     |> assign_form(Leads.change_lead(%Lead{}))}
  end

  @impl true
  def handle_event("validate", %{"lead" => params}, socket) do
    changeset =
      %Lead{}
      |> Leads.change_lead(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:sent, false) |> assign_form(changeset)}
  end

  def handle_event("submit", %{"lead" => params}, socket) do
    case Leads.create_lead(params) do
      {:ok, lead} ->
        _ = Notifier.deliver_inquiry_notification(lead)

        {:noreply,
         socket
         |> assign(:sent, true)
         |> assign_form(Leads.change_lead(%Lead{}))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, :form, to_form(changeset, as: :lead))
  end

  # Interpolate changeset error placeholders (e.g. %{count}) without Gettext domains.
  defp error_message({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end

  defp field_errors(field) do
    if Phoenix.Component.used_input?(field), do: field.errors, else: []
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :instrument_options, @instrument_options)

    ~H"""
    <div class="ms-root">
      <header class="ms-nav">
        <div class="ms-container ms-nav__inner">
          <a href="#top" class="ms-nav__brand">Tristan</a>
          <nav class="ms-nav__links">
            <a class="ms-nav__link" href="#about">About</a>
            <a class="ms-nav__link" href="#lessons">Lessons &amp; Rates</a>
            <a class="ms-nav__link" href="#contact">Contact</a>
          </nav>
          <a class="ms-btn ms-btn--primary" href="#contact">Inquire</a>
        </div>
      </header>

      <main id="top">
        <%!-- Hero --%>
        <section class="ms-section">
          <div class="ms-container">
            <p class="ms-eyebrow">Voice · Piano · Guitar</p>
            <h1 class="ms-h1" style="margin-top:1rem;max-width:18ch">
              Music lessons for every age and stage.
            </h1>
            <p class="ms-lead" style="margin-top:1.5rem;max-width:42ch">
              Classically trained voice, piano, and guitar instruction in a welcoming
              local studio — for beginners and returning musicians alike.
            </p>
            <div style="margin-top:2rem;display:flex;gap:0.75rem;flex-wrap:wrap">
              <a class="ms-btn ms-btn--primary" href="#contact">Inquire about lessons</a>
              <a class="ms-btn ms-btn--ghost" href="#lessons">See lessons &amp; rates</a>
            </div>
          </div>
        </section>

        <%!-- About --%>
        <section id="about" class="ms-section ms-section--tint">
          <div class="ms-container">
            <p class="ms-eyebrow">About</p>
            <h2 class="ms-h2" style="margin-top:0.75rem">Meet your teacher</h2>
            <div
              class="ms-grid"
              style="margin-top:2rem;grid-template-columns:1fr;gap:2.5rem"
            >
              <div class="ms-prose" style="max-width:60ch">
                <p>
                  Tristan began his post-secondary music studies at Capilano University,
                  earning diplomas in Piano, Voice, and Conducting, then completed a
                  Bachelor of Music in Voice at the University of Victoria, where he was
                  awarded the Bea Scott Scholarship in 2014. In 2010 he received the City
                  of White Rock Award for Musical Excellence.
                </p>
                <p>
                  An accomplished pianist, organist, and guitarist as well as a singer, he
                  has performed with acclaimed ensembles including the Vancouver Chamber
                  Choir, Vancouver Opera Chorus, Laudate Singers, and Vox Humana, and has
                  appeared as a soloist with the University of Victoria Orchestra, Vancouver
                  Chamber Choir, and Vancouver Bach Choir.
                </p>
                <p>
                  Years of experience as both performer and educator let him bring a
                  versatile, well-rounded approach to every lesson.
                </p>
              </div>
              <div>
                <h3 class="ms-h3" style="margin-bottom:1rem">Training &amp; honours</h3>
                <ul class="ms-list">
                  <li>Diplomas in Piano, Voice &amp; Conducting — Capilano University</li>
                  <li>Bachelor of Music, Voice — University of Victoria</li>
                  <li>Bea Scott Scholarship, 2014</li>
                  <li>City of White Rock Award for Musical Excellence, 2010</li>
                </ul>
              </div>
            </div>
          </div>
        </section>

        <%!-- Lessons & Rates --%>
        <section id="lessons" class="ms-section">
          <div class="ms-container">
            <p class="ms-eyebrow">Lessons</p>
            <h2 class="ms-h2" style="margin-top:0.75rem">What I teach</h2>
            <p class="ms-lead" style="margin-top:0.75rem;max-width:44ch">
              All ages and levels welcome, in person at a local studio.
            </p>

            <div class="ms-grid ms-grid--3" style="margin-top:2rem">
              <div class="ms-card">
                <div class="ms-card__title">Voice</div>
                <p class="ms-prose" style="margin-top:0.5rem">
                  Technique, breath, and repertoire across classical and contemporary
                  styles — from first lessons to audition prep.
                </p>
              </div>
              <div class="ms-card">
                <div class="ms-card__title">Piano</div>
                <p class="ms-prose" style="margin-top:0.5rem">
                  Fundamentals, reading, and musicianship at the keyboard, tailored to
                  each student's goals and pace.
                </p>
              </div>
              <div class="ms-card">
                <div class="ms-card__title">Guitar</div>
                <p class="ms-prose" style="margin-top:0.5rem">
                  Chords, technique, and songs for acoustic or classical guitar, for
                  players just starting out or picking it back up.
                </p>
              </div>
            </div>

            <div class="ms-card" style="margin-top:2rem;max-width:32rem">
              <h3 class="ms-h3" style="margin-bottom:0.75rem">Rates</h3>
              <table class="ms-rates">
                <thead>
                  <tr>
                    <th>Lesson length</th><th>Rate</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>60 minutes</td><td>$60</td>
                  </tr>
                  <tr>
                    <td>45 minutes</td><td>$45</td>
                  </tr>
                  <tr>
                    <td>30 minutes</td><td>$30</td>
                  </tr>
                </tbody>
              </table>
              <p class="ms-note" style="margin-top:0.75rem">Payment by cash or e-transfer.</p>
            </div>
          </div>
        </section>

        <%!-- Contact --%>
        <section id="contact" class="ms-section ms-section--tint">
          <div class="ms-container" style="max-width:38rem">
            <p class="ms-eyebrow">Contact</p>
            <h2 class="ms-h2" style="margin-top:0.75rem">Inquire about lessons</h2>
            <p class="ms-lead" style="margin-top:0.75rem">
              Tell me a little about who the lessons are for and what you'd like to learn.
            </p>

            <div
              :if={@sent}
              class="ms-card"
              style="margin-top:1.5rem;border-color:var(--ms-accent)"
              role="status"
            >
              <strong>Thank you — your inquiry has been sent.</strong>
              <p class="ms-prose" style="margin-top:0.35rem">
                I'll be in touch by email as soon as I can.
              </p>
            </div>

            <.form
              for={@form}
              phx-change="validate"
              phx-submit="submit"
              style="margin-top:1.5rem"
            >
              <div class="ms-field">
                <label class="ms-label" for={@form[:name].id}>Name</label>
                <input
                  class="ms-input"
                  type="text"
                  id={@form[:name].id}
                  name={@form[:name].name}
                  value={Phoenix.HTML.Form.normalize_value("text", @form[:name].value)}
                  autocomplete="name"
                  required
                />
                <span :for={err <- field_errors(@form[:name])} class="ms-error">
                  {error_message(err)}
                </span>
              </div>

              <div class="ms-field">
                <label class="ms-label" for={@form[:email].id}>Email</label>
                <input
                  class="ms-input"
                  type="email"
                  id={@form[:email].id}
                  name={@form[:email].name}
                  value={Phoenix.HTML.Form.normalize_value("email", @form[:email].value)}
                  autocomplete="email"
                  required
                />
                <span :for={err <- field_errors(@form[:email])} class="ms-error">
                  {error_message(err)}
                </span>
              </div>

              <div class="ms-field">
                <label class="ms-label" for={@form[:instrument].id}>Instrument</label>
                <select
                  class="ms-select"
                  id={@form[:instrument].id}
                  name={@form[:instrument].name}
                >
                  <option value="">Choose one…</option>
                  <option
                    :for={{label, value} <- @instrument_options}
                    value={value}
                    selected={to_string(@form[:instrument].value) == value}
                  >
                    {label}
                  </option>
                </select>
                <span :for={err <- field_errors(@form[:instrument])} class="ms-error">
                  {error_message(err)}
                </span>
              </div>

              <div class="ms-field">
                <label class="ms-label" for={@form[:message].id}>Message</label>
                <textarea
                  class="ms-textarea"
                  id={@form[:message].id}
                  name={@form[:message].name}
                  placeholder="Who are the lessons for? What would you like to learn?"
                >{Phoenix.HTML.Form.normalize_value("textarea", @form[:message].value)}</textarea>
                <span :for={err <- field_errors(@form[:message])} class="ms-error">
                  {error_message(err)}
                </span>
              </div>

              <button type="submit" class="ms-btn ms-btn--primary ms-btn--block">
                Send inquiry
              </button>
            </.form>
          </div>
        </section>
      </main>

      <footer class="ms-footer">
        <div class="ms-container" style="padding-block:2rem">
          <p>© {Date.utc_today().year} Tristan · Music lessons in the Greater Vancouver area.</p>
        </div>
      </footer>
    </div>
    """
  end
end
