CREATE TABLE final_table AS
SELECT fm.employee_id, em.fullname, em.iq, em.gtq, em.education_level, em.mbti, fm.final_match_rate, em.pillar_sea, em.pillar_qdd, em.pillar_vcu, em.pillar_lie, 
       em.s_strategic, em.s_learner, em.s_achiever, em.s_relator, em.s_analytical, em.years_of_service
FROM final_match fm
JOIN employee_data em USING (employee_id)
ORDER BY fm.final_match_rate DESC;