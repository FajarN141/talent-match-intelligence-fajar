/* ============================================================
   VARIAN: Benchmark–Median Match Rate + PAPI + Bobot per-TV
   ============================================================ */
WITH
/* -------------------------
   PARAMS & BOBOT
   ------------------------- */
params AS (
  SELECT
    -- Bobot antar-TGV (boleh diubah)
    0.30::numeric AS w_cognitive,
    0.25::numeric AS w_personality,  -- TGV baru: Personality (PAPI)
    0.20::numeric AS w_leadership,
    0.15::numeric AS w_strengths,
    0.10::numeric AS w_experience,
    -- Strengths jadi "target" jika proporsinya di HP >= threshold
    0.50::numeric AS strengths_majority_threshold
),
/* Bobot per-TV di dalam TGV.
   -> Jika ingin equal weight, isi saja semua "1".
   -> Jika ingin custom, atur per TV di bawah. */
tv_weight AS (
  SELECT * FROM ( VALUES
    -- TGV Cognitive
    ('Cognitive','iq',               1.0),
    ('Cognitive','gtq',              1.0),
    ('Cognitive','tiki',             0.8),
    ('Cognitive','pauli',            0.6),
    ('Cognitive','faxtor',           0.6),

    -- TGV Personality (PAPI 1–9), contoh: bobotkan lebih tinggi pada N/A/P/I/L
    ('Personality','papi_n',         1.0),
    ('Personality','papi_a',         1.0),
    ('Personality','papi_p',         1.0),
    ('Personality','papi_i',         1.0),
    ('Personality','papi_l',         1.0),
    ('Personality','papi_t',         0.8),
    ('Personality','papi_o',         0.8),
    ('Personality','papi_s',         0.8),
    ('Personality','papi_e',         0.7),
    ('Personality','papi_d',         0.7),
    ('Personality','papi_r',         0.7),
    ('Personality','papi_c',         0.7),
    ('Personality','papi_k',         0.7),
    ('Personality','papi_b',         0.7),
    ('Personality','papi_f',         0.7),
    ('Personality','papi_g',         0.7),
    ('Personality','papi_h',         0.7),
    ('Personality','papi_m',         0.7),
    ('Personality','papi_j',         0.7),
    ('Personality','papi_q',         0.7),
    ('Personality','papi_w',         0.7),

    -- TGV Leadership (competency pillars)
    ('Leadership','pillar_sea',      1.0),
    ('Leadership','pillar_qdd',      1.0),
    ('Leadership','pillar_vcu',      0.9),
    ('Leadership','pillar_lie',      0.9),

    -- TGV Experience
    ('Experience','years_of_service',1.0)

    -- TGV Strengths dihitung terpisah (sudah berupa rata-rata target themes)
  ) AS t(tgv, tv, w_tv)
),

/* Arah perbandingan numeric TV: 1=higher-is-better, −1=lower-is-better */
tv_direction AS (
  SELECT * FROM ( VALUES
    ('Cognitive','iq',               1),
    ('Cognitive','gtq',              1),
    ('Cognitive','tiki',             1),
    ('Cognitive','pauli',            1),
    ('Cognitive','faxtor',           1),

    ('Personality','papi_n',         1),
    ('Personality','papi_a',         1),
    ('Personality','papi_p',         1),
    ('Personality','papi_i',         1),
    ('Personality','papi_l',         1),
    ('Personality','papi_t',         1),
    ('Personality','papi_o',         1),
    ('Personality','papi_s',         1),
    ('Personality','papi_e',         1),
    ('Personality','papi_d',         1),
    ('Personality','papi_r',         1),
    ('Personality','papi_c',         1),
    ('Personality','papi_k',         1),
    ('Personality','papi_b',         1),
    ('Personality','papi_f',         1),
    ('Personality','papi_g',         1),
    ('Personality','papi_h',         1),
    ('Personality','papi_m',         1),
    ('Personality','papi_j',         1),
    ('Personality','papi_q',         1),
    ('Personality','papi_w',         1),

    ('Leadership','pillar_sea',      1),
    ('Leadership','pillar_qdd',      1),
    ('Leadership','pillar_vcu',      1),
    ('Leadership','pillar_lie',      1),

    -- contoh jika ada metrik yang makin kecil makin baik:
    -- ('Experience','avg_error_rate', -1),

    ('Experience','years_of_service',1)
  ) AS t(tgv, tv, direction)
),

/* -------------------------
   DATA DASAR & HP SET
   ------------------------- */
base AS (
  SELECT DISTINCT ON (employee_id)
    employee_id, rating, (rating=5) AS is_hp,
    iq, gtq, tiki, pauli, faxtor,
    pillar_sea, pillar_qdd, pillar_vcu, pillar_lie,
    years_of_service,
    disc, mbti,
    s_strategic::int AS s_strategic,
    s_learner::int   AS s_learner,
    s_achiever::int  AS s_achiever,
    s_relator::int   AS s_relator,
    s_analytical::int AS s_analytical,
    -- PAPI 1–9
    papi_n, papi_g, papi_a, papi_l, papi_p, papi_i, papi_t, papi_v,
    papi_o, papi_b, papi_s, papi_x, papi_c, papi_d, papi_r, papi_z,
    papi_e, papi_k, papi_f, papi_w
  FROM master_table
  WHERE rating IS NOT NULL
  ORDER BY employee_id, year DESC
),
benchmark_set AS (
  SELECT * FROM base WHERE is_hp = TRUE
),

/* -------------------------
   MEDIAN BENCHMARK (HP only)
   ------------------------- */
baseline_numeric AS (
  SELECT
    d.tgv, d.tv,
    CASE d.tv
      WHEN 'iq'  THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.iq)
      WHEN 'gtq' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.gtq)
      WHEN 'tiki' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.tiki)
      WHEN 'pauli' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.pauli)
      WHEN 'faxtor' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.faxtor)

      WHEN 'papi_n' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_n)
      WHEN 'papi_g' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_g)
      WHEN 'papi_a' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_a)
      WHEN 'papi_l' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_l)
      WHEN 'papi_p' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_p)
      WHEN 'papi_i' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_i)
      WHEN 'papi_t' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_t)
      WHEN 'papi_v' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_v)
      WHEN 'papi_o' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_o)
      WHEN 'papi_b' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_b)
      WHEN 'papi_s' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_s)
      WHEN 'papi_x' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_x)
      WHEN 'papi_c' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_c)
      WHEN 'papi_d' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_d)
      WHEN 'papi_r' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_r)
      WHEN 'papi_z' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_z)
      WHEN 'papi_e' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_e)
      WHEN 'papi_k' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_k)
      WHEN 'papi_f' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_f)
      WHEN 'papi_w' THEN PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY b.papi_w)

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

/* -------------------------
   RAW TV NUMERIC (UNION)
   ------------------------- */
tv_numeric_raw AS (
  -- Cognitive
  SELECT employee_id,'Cognitive'::text AS tgv,'iq'::text AS tv, iq::numeric AS val FROM base
  UNION ALL SELECT employee_id,'Cognitive','gtq', gtq::numeric FROM base
  UNION ALL SELECT employee_id,'Cognitive','tiki', tiki::numeric FROM base
  UNION ALL SELECT employee_id,'Cognitive','pauli', pauli::numeric FROM base
  UNION ALL SELECT employee_id,'Cognitive','faxtor', faxtor::numeric FROM base
  -- Personality (PAPI)
  UNION ALL SELECT employee_id,'Personality','papi_n', papi_n::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_g', papi_g::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_a', papi_a::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_l', papi_l::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_p', papi_p::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_i', papi_i::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_t', papi_t::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_v', papi_v::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_o', papi_o::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_b', papi_b::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_s', papi_s::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_x', papi_x::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_c', papi_c::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_d', papi_d::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_r', papi_r::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_z', papi_z::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_e', papi_e::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_k', papi_k::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_f', papi_f::numeric FROM base
  UNION ALL SELECT employee_id,'Personality','papi_w', papi_w::numeric FROM base
  -- Leadership
  UNION ALL SELECT employee_id,'Leadership','pillar_sea', pillar_sea::numeric FROM base
  UNION ALL SELECT employee_id,'Leadership','pillar_qdd', pillar_qdd::numeric FROM base
  UNION ALL SELECT employee_id,'Leadership','pillar_vcu', pillar_vcu::numeric FROM base
  UNION ALL SELECT employee_id,'Leadership','pillar_lie', pillar_lie::numeric FROM base
  -- Experience
  UNION ALL SELECT employee_id,'Experience','years_of_service', years_of_service::numeric FROM base
),

/* -------------------------
   MATCH TV NUMERIC (clamped)
   ------------------------- */
tv_match_numeric AS (
  SELECT
    r.employee_id, r.tgv, r.tv,
    CASE
      WHEN bn.benchmark_med IS NULL OR bn.benchmark_med = 0 OR r.val IS NULL THEN NULL
      WHEN d.direction = 1  THEN LEAST(100.0, GREATEST(0.0, 100.0 * (r.val / bn.benchmark_med)))
      WHEN d.direction = -1 THEN LEAST(100.0, GREATEST(0.0, 100.0 * ((2*bn.benchmark_med - r.val)/bn.benchmark_med)))
    END AS tv_match_pct
  FROM tv_numeric_raw r
  JOIN baseline_numeric bn USING (tgv, tv)
  JOIN tv_direction d      USING (tgv, tv)
),

/* -------------------------
   KATEGORIKAL: DISC/MBTI
   ------------------------- */
baseline_categorical AS (
  SELECT 'disc'::text AS tv,
         (SELECT disc FROM benchmark_set WHERE disc IS NOT NULL
          GROUP BY disc ORDER BY COUNT(*) DESC LIMIT 1) AS target_val
  UNION ALL
  SELECT 'mbti'::text AS tv,
         (SELECT mbti FROM benchmark_set WHERE mbti IS NOT NULL
          GROUP BY mbti ORDER BY COUNT(*) DESC LIMIT 1) AS target_val
),
tv_categorical_raw AS (
  SELECT employee_id,'Behavior'::text AS tgv,'disc'::text AS tv, disc::text AS val FROM base
  UNION ALL
  SELECT employee_id,'Behavior'::text AS tgv,'mbti'::text AS tv, mbti::text AS val FROM base
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

/* -------------------------
   STRENGTHS → TGV langsung
   ------------------------- */
strengths_hp_stats AS (
  SELECT
    AVG(s_strategic)::numeric AS p_strategic,
    AVG(s_learner)::numeric   AS p_learner,
    AVG(s_achiever)::numeric  AS p_achiever,
    AVG(s_relator)::numeric   AS p_relator,
    AVG(s_analytical)::numeric AS p_analytical
  FROM benchmark_set
),
strengths_targets AS (
  SELECT
    (p.p_strategic >= par.strengths_majority_threshold)  AS t_strategic,
    (p.p_learner   >= par.strengths_majority_threshold)  AS t_learner,
    (p.p_achiever  >= par.strengths_majority_threshold)  AS t_achiever,
    (p.p_relator   >= par.strengths_majority_threshold)  AS t_relator,
    (p.p_analytical>= par.strengths_majority_threshold)  AS t_analytical
  FROM strengths_hp_stats p CROSS JOIN params par
),
tgv_strengths AS (
  SELECT
    b.employee_id,
    'Strengths'::text AS tgv,
    (
      (CASE WHEN t.t_strategic  THEN (CASE WHEN b.s_strategic = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END) +
      (CASE WHEN t.t_learner    THEN (CASE WHEN b.s_learner   = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END) +
      (CASE WHEN t.t_achiever   THEN (CASE WHEN b.s_achiever  = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END) +
      (CASE WHEN t.t_relator    THEN (CASE WHEN b.s_relator   = 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END) +
      (CASE WHEN t.t_analytical THEN (CASE WHEN b.s_analytical= 1 THEN 100.0 ELSE 0.0 END) ELSE NULL END)
    ) / NULLIF(
        (CASE WHEN t.t_strategic  THEN 1 ELSE 0 END) +
        (CASE WHEN t.t_learner    THEN 1 ELSE 0 END) +
        (CASE WHEN t.t_achiever   THEN 1 ELSE 0 END) +
        (CASE WHEN t.t_relator    THEN 1 ELSE 0 END) +
        (CASE WHEN t.t_analytical THEN 1 ELSE 0 END)
      ,0) AS tgv_match_pct
  FROM base b CROSS JOIN strengths_targets t
),

/* -------------------------
   UNION TV MATCH & AGREGASI TGV
   -> di sini kita pakai BOBOT per-TV
   ------------------------- */
tv_match_all AS (
  SELECT employee_id, tgv, tv, tv_match_pct FROM tv_match_numeric
  UNION ALL
  SELECT employee_id, tgv, tv, tv_match_pct FROM tv_match_categorical
),
tgv_match_weighted AS (
  SELECT
    m.employee_id, m.tgv,
    SUM(m.tv_match_pct * COALESCE(w.w_tv, 1.0)) / NULLIF(SUM(COALESCE(w.w_tv, 1.0)),0) AS tgv_match_pct
  FROM tv_match_all m
  LEFT JOIN tv_weight w USING (tgv, tv)
  GROUP BY m.employee_id, m.tgv
),
tgv_union AS (
  SELECT * FROM tgv_match_weighted
  UNION ALL
  SELECT * FROM tgv_strengths    -- Strengths sudah dalam bentuk TGV
),

/* -------------------------
   FINAL MATCH (bobot TGV)
   ------------------------- */
final_match AS (
  SELECT
    b.employee_id,
    b.is_hp,
    MAX(CASE WHEN tgv='Cognitive'   THEN tgv_match_pct END) AS m_cognitive,
    MAX(CASE WHEN tgv='Personality' THEN tgv_match_pct END) AS m_personality,
    MAX(CASE WHEN tgv='Leadership'  THEN tgv_match_pct END) AS m_leadership,
    MAX(CASE WHEN tgv='Strengths'   THEN tgv_match_pct END) AS m_strengths,
    MAX(CASE WHEN tgv='Experience'  THEN tgv_match_pct END) AS m_experience,
    (
      COALESCE(MAX(CASE WHEN tgv='Cognitive'   THEN tgv_match_pct END),0)*p.w_cognitive +
      COALESCE(MAX(CASE WHEN tgv='Personality' THEN tgv_match_pct END),0)*p.w_personality +
      COALESCE(MAX(CASE WHEN tgv='Leadership'  THEN tgv_match_pct END),0)*p.w_leadership +
      COALESCE(MAX(CASE WHEN tgv='Strengths'   THEN tgv_match_pct END),0)*p.w_strengths +
      COALESCE(MAX(CASE WHEN tgv='Experience'  THEN tgv_match_pct END),0)*p.w_experience
    ) AS final_match_rate
  FROM base b
  LEFT JOIN tgv_union u USING (employee_id)
  CROSS JOIN params p
  GROUP BY b.employee_id, b.is_hp, p.w_cognitive, p.w_personality, p.w_leadership, p.w_strengths, p.w_experience
),
validate_hp AS (
  SELECT is_hp,
         COUNT(*) AS n,
         AVG(final_match_rate) AS mean_final,
         PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY final_match_rate) AS median_final
  FROM final_match
  GROUP BY is_hp
)

/* OUTPUT */
SELECT * FROM final_match ORDER BY final_match_rate DESC, employee_id;
/* Untuk validasi:
   SELECT * FROM validate_hp ORDER BY is_hp DESC; */
