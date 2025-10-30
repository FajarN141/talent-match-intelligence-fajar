-- ==========================================
-- STEP 0. Parameter dan daftar kolom
-- ==========================================
-- Ganti jika Anda ingin mengubah titik optimum YoS (default 4.5 thn)
WITH params AS (
  SELECT 4.5::numeric AS yos_optimal
),

-- ==========================================
-- STEP 1. Dataset dasar + flag is_hp
-- ==========================================
base AS (
  SELECT
    employee_id,
    rating,
    (rating = 5) AS is_hp,                     -- definisi High Performer
    years_of_service,
    iq, gtq, tiki, pauli, faxtor,              -- kognitif (pakai iq, gtq untuk skor)
    -- PAPI (tersedia bila nanti ingin dikembangkan)
    papi_n, papi_g, papi_a, papi_l, papi_p, papi_i, papi_t, papi_v,
    papi_o, papi_b, papi_s, papi_x, papi_c, papi_d, papi_r, papi_z,
    papi_e, papi_k, papi_f, papi_w,
    -- Strengths (boolean 0/1)
    s_strategic, s_learner, s_achiever, s_relator, s_analytical,
    -- Pilar kompetensi leadership/strategic
    pillar_sea, pillar_qdd, pillar_vcu, pillar_lie
  FROM master_table
),

-- ==========================================
-- STEP 2. Utility: median & statistik tiap fitur
-- (a) Statistik IQ
-- ==========================================
stat_iq AS (
  SELECT
    AVG(iq)::numeric            AS mean_iq,
    STDDEV_SAMP(iq)::numeric    AS std_iq,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY iq) AS med_iq
  FROM base WHERE iq IS NOT NULL
),
-- (b) Statistik GTQ
stat_gtq AS (
  SELECT
    AVG(gtq)::numeric           AS mean_gtq,
    STDDEV_SAMP(gtq)::numeric   AS std_gtq,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gtq) AS med_gtq
  FROM base WHERE gtq IS NOT NULL
),

-- ==========================================
-- STEP 3. Z-score per TV (safe_z style)
-- Logika: null → isi median dulu, lalu (x - mean) / std.
-- Jika std = 0 atau NULL → kembalikan 0 (aman).
-- ==========================================
z_iq AS (
  SELECT
    b.employee_id,
    CASE
      WHEN s.std_iq IS NULL OR s.std_iq = 0 THEN 0
      ELSE (COALESCE(b.iq, s.med_iq) - s.mean_iq) / s.std_iq
    END AS z_iq
  FROM base b CROSS JOIN stat_iq s
),
z_gtq AS (
  SELECT
    b.employee_id,
    CASE
      WHEN s.std_gtq IS NULL OR s.std_gtq = 0 THEN 0
      ELSE (COALESCE(b.gtq, s.med_gtq) - s.mean_gtq) / s.std_gtq
    END AS z_gtq
  FROM base b CROSS JOIN stat_gtq s
),

-- ==========================================
-- STEP 4. TGV: Cognitive = rata-rata z(IQ, GTQ)
-- ==========================================
score_cognitive AS (
  SELECT
    i.employee_id,
    -- rata-rata zscore dua TV kognitif; jika salah satu NULL → diperlakukan 0 via COALESCE
    (COALESCE(i.z_iq, 0) + COALESCE(g.z_gtq, 0)) / 
    NULLIF( (CASE WHEN i.z_iq IS NOT NULL THEN 1 ELSE 0 END +
            CASE WHEN g.z_gtq IS NOT NULL THEN 1 ELSE 0 END), 0 ) AS score_cognitive
  FROM z_iq i
  JOIN z_gtq g USING (employee_id)
),

-- ==========================================
-- STEP 5. TGV: Leadership
-- 1) Hitung rata-rata pilar leadership per kandidat
-- 2) Z-score-kan nilai rata-rata itu (safe_z)
-- ==========================================
leadership_raw AS (
  SELECT
    employee_id,
    -- rata-rata 4 pilar (abaikan NULL secara proporsional)
    (COALESCE(pillar_sea, NULL) + COALESCE(pillar_qdd, NULL) +
     COALESCE(pillar_vcu, NULL) + COALESCE(pillar_lie, NULL))::numeric
     / NULLIF( (CASE WHEN pillar_sea IS NOT NULL THEN 1 ELSE 0 END
              + CASE WHEN pillar_qdd IS NOT NULL THEN 1 ELSE 0 END
              + CASE WHEN pillar_vcu IS NOT NULL THEN 1 ELSE 0 END
              + CASE WHEN pillar_lie IS NOT NULL THEN 1 ELSE 0 END), 0) AS leadership_avg
  FROM base
),
stat_leadership AS (
  SELECT
    AVG(leadership_avg)::numeric          AS mean_lead,
    STDDEV_SAMP(leadership_avg)::numeric  AS std_lead,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY leadership_avg) AS med_lead
  FROM leadership_raw WHERE leadership_avg IS NOT NULL
),
score_leadership AS (
  SELECT
    r.employee_id,
    CASE
      WHEN s.std_lead IS NULL OR s.std_lead = 0 THEN 0
      ELSE (COALESCE(r.leadership_avg, s.med_lead) - s.mean_lead) / s.std_lead
    END AS score_leadership
  FROM leadership_raw r CROSS JOIN stat_leadership s
),

-- ==========================================
-- STEP 6. TGV: Strengths
-- 1) Hitung proporsi tema strengths (mean binary)
-- 2) Z-score-kan proporsi tsb (safe_z)
-- ==========================================
strengths_raw AS (
  SELECT
    employee_id,
    (
      COALESCE(s_strategic::int, 0) +
      COALESCE(s_learner::int, 0) +
      COALESCE(s_achiever::int, 0) +
      COALESCE(s_relator::int, 0) +
      COALESCE(s_analytical::int, 0)
    )::numeric / 5.0 AS strengths_mean
  FROM base
),
stat_strengths AS (
  SELECT
    AVG(strengths_mean)::numeric         AS mean_str,
    STDDEV_SAMP(strengths_mean)::numeric AS std_str,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY strengths_mean) AS med_str
  FROM strengths_raw
),
score_strengths AS (
  SELECT
    r.employee_id,
    CASE
      WHEN s.std_str IS NULL OR s.std_str = 0 THEN 0
      ELSE (COALESCE(r.strengths_mean, s.med_str) - s.mean_str) / s.std_str
    END AS score_strengths
  FROM strengths_raw r CROSS JOIN stat_strengths s
),

-- ==========================================
-- STEP 7. TGV: Experience
-- 1) Transformasi parabola: - (YoS - a)^2 + a^2  (a = yos_optimal)
-- 2) Z-score-kan hasil transformasi (safe_z)
-- ==========================================
experience_raw AS (
  SELECT
    b.employee_id,
    -- clamp YoS agar tidak negatif (sesuai notebook: clip lower=0)
    GREATEST(b.years_of_service, 0)::numeric AS yos,
    p.yos_optimal
  FROM base b
  CROSS JOIN params p
),
experience_parabola AS (
  SELECT
    employee_id,
    (-1 * (yos - yos_optimal) * (yos - yos_optimal) + (yos_optimal * yos_optimal))::numeric
      AS exp_score_raw
  FROM experience_raw
),
stat_experience AS (
  SELECT
    AVG(exp_score_raw)::numeric          AS mean_exp,
    STDDEV_SAMP(exp_score_raw)::numeric  AS std_exp,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY exp_score_raw) AS med_exp
  FROM experience_parabola
),
score_experience AS (
  SELECT
    e.employee_id,
    CASE
      WHEN s.std_exp IS NULL OR s.std_exp = 0 THEN 0
      ELSE (COALESCE(e.exp_score_raw, s.med_exp) - s.mean_exp) / s.std_exp
    END AS score_experience
  FROM experience_parabola e CROSS JOIN stat_experience s
),

-- ==========================================
-- STEP 8. Gabungkan semua TGV & hitung Success Score v1
-- Bobot: Cognitive 0.35, Leadership 0.30, Strengths 0.20, Experience 0.15
-- ==========================================
final_scores AS (
  SELECT
    b.employee_id,
    b.is_hp,
    COALESCE(c.score_cognitive, 0)  AS score_cognitive,
    COALESCE(l.score_leadership, 0) AS score_leadership,
    COALESCE(s.score_strengths, 0)  AS score_strengths,
    COALESCE(x.score_experience, 0) AS score_experience,
    0.35 * COALESCE(c.score_cognitive, 0) +
    0.30 * COALESCE(l.score_leadership, 0) +
    0.20 * COALESCE(s.score_strengths, 0) +
    0.15 * COALESCE(x.score_experience, 0) AS success_score_v1
  FROM base b
  LEFT JOIN score_cognitive  c USING (employee_id)
  LEFT JOIN score_leadership l USING (employee_id)
  LEFT JOIN score_strengths  s USING (employee_id)
  LEFT JOIN score_experience x USING (employee_id)
),

-- ==========================================
-- STEP 9. Validasi ringkas: HP vs Non-HP
-- ==========================================
validate_hp AS (
  SELECT
    is_hp,
    COUNT(*)                           AS n,
    AVG(success_score_v1)              AS mean_success,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY success_score_v1) AS median_success,
    STDDEV_SAMP(success_score_v1)      AS std_success
  FROM final_scores
  GROUP BY is_hp
)

-- ==========================================
-- OUTPUT:
-- 1) Skor per kandidat (success_score_v1)
-- 2) Ringkasan validasi (HP vs Non-HP)
-- ==========================================
SELECT * FROM final_scores ORDER BY success_score_v1 DESC, employee_id;

-- Untuk melihat validasi:
-- SELECT * FROM validate_hp ORDER BY is_hp DESC;
