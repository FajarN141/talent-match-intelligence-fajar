/* ================================
   STEP 0. PARAMETER & BOBOT
   ================================ */
WITH
params AS (
  SELECT
    -- Bobot TGV (default, bisa diubah atau disubstitusi dari JSON)
    0.30::numeric AS w_cognitive,
    0.25::numeric AS w_personality,  -- TGV Personality
    0.20::numeric AS w_leadership,
    0.15::numeric AS w_strengths,
    0.10::numeric AS w_experience,
    -- Strengths jadi "target" jika proporsinya di HP >= threshold
    0.50::numeric AS strengths_majority_threshold
),

-- Mapping arah TV numeric: 1 = higher-is-better, -1 = lower-is-better
tv_direction AS (
  SELECT * FROM (VALUES
    ('Cognitive','iq',       1),
    ('Cognitive','gtq',      1),
    ('Cognitive','tiki',     1),
    ('Cognitive','pauli',    1),
    ('Cognitive','faxtor',   1),

    ('Leadership','pillar_sea', 1),
    ('Leadership','pillar_qdd', 1),
    ('Leadership','pillar_vcu', 1),
    ('Leadership','pillar_lie', 1),

    ('Experience','years_of_service', 1)  -- kita perlakukan YoS sebagai numeric TV sederhana
  ) AS t(tgv, tv, direction)
),

/* ================================
   STEP 1. DATA DASAR & FLAG HP
   ================================ */
base AS (
  SELECT
    employee_id,
    rating,
    (rating = 5) AS is_hp,
    -- numeric TVs
    iq, gtq, tiki, pauli, faxtor,
    pillar_sea, pillar_qdd, pillar_vcu, pillar_lie,
    years_of_service,
    -- categorical TVs (opsional)
    disc, mbti,
    -- strengths (boolean 0/1)
    s_strategic::int AS s_strategic,
    s_learner::int   AS s_learner,
    s_achiever::int  AS s_achiever,
    s_relator::int   AS s_relator,
    s_analytical::int AS s_analytical
  FROM no_null_master_table
),

/* ================================
   STEP 2. BENTUKKAN BENCHMARK SET
   (HP saja, sesuai definisi)
   ================================ */
benchmark_set AS (
  SELECT * FROM base WHERE rating = 5  -- Hanya kandidat dengan rating = 5 yang dijadikan benchmark
),

/* ================================
   STEP 3. HITUNG MEDIAN BENCHMARK
   PER TV NUMERIC (HP ONLY)
   ================================ */
baseline_numeric AS (
  SELECT
    d.tgv, d.tv,
    CASE d.tv
      -- Numeric TV
      WHEN 'iq'  THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.iq)
      WHEN 'gtq' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.gtq)
      WHEN 'tiki' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.tiki)
      WHEN 'pauli' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.pauli)
      WHEN 'faxtor' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.faxtor)
      WHEN 'pillar_sea' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.pillar_sea)
      WHEN 'pillar_qdd' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.pillar_qdd)
      WHEN 'pillar_vcu' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.pillar_vcu)
      WHEN 'pillar_lie' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.pillar_lie)
      WHEN 'years_of_service' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.years_of_service)
    END AS benchmark_med
  FROM tv_direction d
  CROSS JOIN benchmark_set b
  GROUP BY d.tgv, d.tv
),

/* =======================================
   STEP 4. BENTUK TABEL NILAI TV NUMERIC
   (UNION ALL agar generik)
   ======================================= */
tv_numeric_raw AS (
  SELECT employee_id, 'Cognitive'::text AS tgv, 'iq'::text AS tv, iq::numeric AS val FROM base
  UNION ALL SELECT employee_id,'Cognitive','gtq', gtq::numeric FROM base
  UNION ALL SELECT employee_id,'Cognitive','tiki', tiki::numeric FROM base
  UNION ALL SELECT employee_id,'Cognitive','pauli', pauli::numeric FROM base
  UNION ALL SELECT employee_id,'Cognitive','faxtor', faxtor::numeric FROM base

  UNION ALL SELECT employee_id,'Leadership','pillar_sea', pillar_sea::numeric FROM base
  UNION ALL SELECT employee_id,'Leadership','pillar_qdd', pillar_qdd::numeric FROM base
  UNION ALL SELECT employee_id,'Leadership','pillar_vcu', pillar_vcu::numeric FROM base
  UNION ALL SELECT employee_id,'Leadership','pillar_lie', pillar_lie::numeric FROM base

  UNION ALL SELECT employee_id,'Experience','years_of_service', years_of_service::numeric FROM base
),

/* =======================================
   STEP 5. HITUNG MATCH TV NUMERIC
   Rumus:
   - Higher-is-better : match = 100 * (val / med)
   - Lower-is-better  : match = 100 * ((2*med - val)/med)
   Lalu di-clamp ke [0, 100]
   ======================================= */
tv_match_numeric AS (
  SELECT
    r.employee_id, r.tgv, r.tv,
    CASE
      WHEN bn.benchmark_med IS NULL OR bn.benchmark_med = 0 OR r.val IS NULL THEN NULL
      WHEN d.direction = 1   THEN LEAST(100.0, GREATEST(0.0, 100.0 * (r.val / bn.benchmark_med)))
      WHEN d.direction = -1  THEN LEAST(100.0, GREATEST(0.0, 100.0 * ((2*bn.benchmark_med - r.val)/bn.benchmark_med)))
    END AS tv_match_pct
  FROM tv_numeric_raw r
  JOIN baseline_numeric bn USING (tgv, tv)
  JOIN tv_direction d        USING (tgv, tv)
),

/* =======================================
   STEP 6. TV KATEGORIKAL (DISC, MBTI)
   Benchmark = MODE (kategori terbanyak di HP)
   Match = exact (100/0)
   ======================================= */
baseline_categorical AS (
  SELECT 'disc'::text AS tv,
         (SELECT disc
          FROM benchmark_set
          WHERE disc IS NOT NULL
          GROUP BY disc
          ORDER BY COUNT(*) DESC
          LIMIT 1) AS target_val
  UNION ALL
  SELECT 'mbti'::text AS tv,
         (SELECT mbti
          FROM benchmark_set
          WHERE mbti IS NOT NULL
          GROUP BY mbti
          ORDER BY COUNT(*) DESC
          LIMIT 1) AS target_val
),

tv_categorical_raw AS (
  SELECT employee_id, 'Behavior'::text AS tgv, 'disc'::text AS tv, disc::text AS val FROM base
  UNION ALL
  SELECT employee_id, 'Behavior'::text AS tgv, 'mbti'::text AS tv, mbti::text AS val FROM base
),

tv_match_categorical AS (
  SELECT
    r.employee_id, r.tgv, r.tv,
    CASE
      WHEN r.val IS NULL OR b.target_val IS NULL THEN NULL
      WHEN r.val = b.target_val THEN 100.0
      ELSE 0.0
    END AS tv_match_pct
  FROM tv_categorical_raw r
  JOIN baseline_categorical b USING (tv)
),

/* =======================================
   STEP 7. STRENGTHS (biner)
   Ide: pilih tema yang mayoritas dimiliki HP (>= threshold),
   kandidat "match" jika punya tema tsb (100), jika tidak (0).
   Lalu TGV Strengths = rata-rata match tema-target tsb.
   ======================================= */
strengths_hp_stats AS (
  SELECT
    -- Menggunakan nilai integer langsung (1 untuk TRUE, 0 untuk FALSE)
    AVG(CASE WHEN s_strategic = 1 THEN 100.0 ELSE 0.0 END) AS p_strategic,
    AVG(CASE WHEN s_learner = 1 THEN 100.0 ELSE 0.0 END) AS p_learner,
    AVG(CASE WHEN s_achiever = 1 THEN 100.0 ELSE 0.0 END) AS p_achiever,
    AVG(CASE WHEN s_relator = 1 THEN 100.0 ELSE 0.0 END) AS p_relator,
    AVG(CASE WHEN s_analytical = 1 THEN 100.0 ELSE 0.0 END) AS p_analytical
  FROM benchmark_set
),
strengths_targets AS (
  SELECT
    (p.p_strategic >= par.strengths_majority_threshold) AS t_strategic,
    (p.p_learner   >= par.strengths_majority_threshold) AS t_learner,
    (p.p_achiever  >= par.strengths_majority_threshold) AS t_achiever,
    (p.p_relator   >= par.strengths_majority_threshold) AS t_relator,
    (p.p_analytical>= par.strengths_majority_threshold) AS t_analytical
  FROM strengths_hp_stats p CROSS JOIN params par
),
tv_match_strengths AS (
  SELECT
    b.employee_id,
    'Strengths'::text AS tgv,
    -- rata-rata match atas tema yang menjadi target (mayoritas di HP)
    (
      (CASE WHEN t.t_strategic  THEN (CASE WHEN b.s_strategic = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END) +
      (CASE WHEN t.t_learner    THEN (CASE WHEN b.s_learner = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END) +
      (CASE WHEN t.t_achiever   THEN (CASE WHEN b.s_achiever = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END) +
      (CASE WHEN t.t_relator    THEN (CASE WHEN b.s_relator = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END) +
      (CASE WHEN t.t_analytical THEN (CASE WHEN b.s_analytical = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END)
    )
    / NULLIF(
        (CASE WHEN t.t_strategic  THEN 1 ELSE 0 END) +
        (CASE WHEN t.t_learner    THEN 1 ELSE 0 END) +
        (CASE WHEN t.t_achiever   THEN 1 ELSE 0 END) +
        (CASE WHEN t.t_relator    THEN 1 ELSE 0 END) +
        (CASE WHEN t.t_analytical THEN 1 ELSE 0 END)
      ,0) AS tgv_match_pct
  FROM base b CROSS JOIN strengths_targets t
),

/* =======================================
   STEP 8. UNION SELURUH TV MATCH
   (numeric + categorical → lalu agregasi ke TGV)
   ======================================= */
tv_match_all AS (
  SELECT employee_id, tgv, tv, tv_match_pct FROM tv_match_numeric
  UNION ALL
  SELECT employee_id, tgv, tv, tv_match_pct FROM tv_match_categorical
),
-- Agregasi TGV: rata-rata TV match (equal weight TV dalam TGV)
tgv_match AS (
  SELECT
    employee_id, tgv,
    AVG(tv_match_pct)::numeric AS tgv_match_pct
  FROM tv_match_all
  GROUP BY employee_id, tgv
),
-- Masukkan Strengths (sudah dalam bentuk TGV)
tgv_union AS (
  SELECT employee_id, tgv, tgv_match_pct FROM tgv_match
  UNION ALL
  SELECT employee_id, 'Strengths'::text AS tgv, tgv_match_pct FROM tv_match_strengths
),

/* =======================================
   STEP 9. FINAL MATCH (weighted across TGV)
   ======================================= */
final_match AS (
  SELECT
    b.employee_id,
    b.is_hp,
    -- Ambil tiap TGV
    MAX(CASE WHEN tgv='Cognitive'  THEN tgv_match_pct END) AS m_cognitive,
    MAX(CASE WHEN tgv='Leadership' THEN tgv_match_pct END) AS m_leadership,
    MAX(CASE WHEN tgv='Strengths'  THEN tgv_match_pct END) AS m_strengths,
    MAX(CASE WHEN tgv='Experience' THEN tgv_match_pct END) AS m_experience,
    -- Weighted final (default w dari params)
    (
      COALESCE(MAX(CASE WHEN tgv='Cognitive'  THEN tgv_match_pct END), 0) * p.w_cognitive +
      COALESCE(MAX(CASE WHEN tgv='Leadership' THEN tgv_match_pct END), 0) * p.w_leadership +
      COALESCE(MAX(CASE WHEN tgv='Strengths'  THEN tgv_match_pct END), 0) * p.w_strengths +
      COALESCE(MAX(CASE WHEN tgv='Experience' THEN tgv_match_pct END), 0) * p.w_experience
    ) AS final_match_rate
  FROM base b
  LEFT JOIN tgv_union u USING (employee_id)
  CROSS JOIN params p
  GROUP BY b.employee_id, b.is_hp, p.w_cognitive, p.w_leadership, p.w_strengths, p.w_experience
),

/* =======================================
   STEP 10. VALIDASI HP vs NON-HP
   ======================================= */
validate_hp AS (
  SELECT
    is_hp,
    COUNT(*) AS n,
    AVG(final_match_rate) AS mean_final,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY final_match_rate) AS median_final
  FROM final_match
  GROUP BY is_hp
)

-- ============ OUTPUT ============
-- 1) Skor final per kandidat (0-100)
SELECT
  f.employee_id,
  f.is_hp,
  f.m_cognitive,
  f.m_leadership,
  f.m_strengths,
  f.m_experience,
  f.final_match_rate
FROM final_match f
ORDER BY f.final_match_rate DESC, f.employee_id;

-- 2) Ringkasan validasi (jalankan terpisah saat perlu)
-- SELECT * FROM validate_hp ORDER BY is_hp DESC;
