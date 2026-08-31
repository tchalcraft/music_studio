defmodule MusicStudio.Repo.Migrations.CreateAnalyticsViews do
  use Ecto.Migration

  # Hybrid reporting marts as SQL views: convenient BI grains over the normalized tables,
  # cheap to change and safe to drop. Dimensional modeling proper happens in the lakehouse.
  def up do
    execute("""
    CREATE VIEW analytics_lesson_facts AS
    SELECT
      l.id                AS lesson_id,
      l.scheduled_start   AS scheduled_start,
      l.status            AS status,
      l.duration_minutes  AS duration_minutes,
      l.price_cents       AS price_cents,
      l.currency          AS currency,
      s.id                AS student_id,
      (s.first_name || ' ' || s.last_name) AS student_name,
      t.id                AS teacher_id,
      t.name              AS teacher_name,
      i.name              AS instrument_name,
      o.name              AS offering_name
    FROM lessons l
    JOIN students s    ON s.id = l.student_id
    JOIN teachers t    ON t.id = l.teacher_id
    LEFT JOIN instruments i ON i.id = l.instrument_id
    LEFT JOIN offerings o   ON o.id = l.offering_id
    WHERE l.deleted_at IS NULL
    """)

    execute("""
    CREATE VIEW analytics_funnel AS
    SELECT
      COALESCE(source, 'unknown') AS source,
      status,
      instrument,
      COUNT(*)                          AS lead_count,
      COUNT(converted_student_id)       AS converted_count
    FROM leads
    GROUP BY COALESCE(source, 'unknown'), status, instrument
    """)
  end

  def down do
    execute("DROP VIEW IF EXISTS analytics_funnel")
    execute("DROP VIEW IF EXISTS analytics_lesson_facts")
  end
end
