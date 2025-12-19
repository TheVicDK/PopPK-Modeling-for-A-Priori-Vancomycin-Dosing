-- -- Tabel 2
with


-- Vi finder lige de patienter vi skal bruge. Med exclusion, kan vi snuppe subject_id og hadm_id fra vanco query. 
filtered_patients AS (
  SELECT distinct subject_id, hadm_id
  FROM Table1 --Navngivet table1 i min mimic, da jeg skulle navngive den noget
),

-- Laver en CTE som vi kalder labevents, som indeholde alle de seje ting fra the lab
labevents AS (
  select --Alle ting er castet som deres datatype, fordi den ellers ikke ville sætte sammen
    le.subject_id,
    le.hadm_id,
    NULL::integer AS stay_id,
    REPLACE(li.label, ',', ' ')::text AS label, --Hov, den her hedder sgu da li. Det er fordi den kommer fra anden csv fil! 
    le.charttime,
    le.storetime,
    le.itemid::integer AS itemid,
    le.value::text AS value,
    le.valuenum::double precision AS valuenum,
    le.valueuom::text AS valueuom,
    le.flag::text AS flag,
    NULL::smallint AS warning,
    'lab'::text AS source   --Vi har lavet en source, så man ved om det kommer fra lab eller vitals
  FROM mimiciv_hosp.labevents le 
  JOIN mimiciv_hosp.d_labitems li --Vi bruger egentlig kun den her til at kunne få en label til lab items
    ON le.itemid = li.itemid
  --Vi anvender lige at vi egentlig kun vil have de patienter som også er med i vores Vanco Query. Resten siger vi "fuck you" til
  JOIN filtered_patients fp 
    ON le.subject_id = fp.subject_id -- subject_id skal være ens
   AND le.hadm_id = fp.hadm_id --Hadm_id skal være ens for at patienten kan forblive
  WHERE le.itemid IN ( -- Vi vil forresten kun have de overstående ting, for disse itemIDs
	50912, --creatinine blood
    52546, --Creatinine blood
	50862, --Creatinine blood
    53085, --Creatinine blood
    53138, --Albumin blood
	51640, --Hemoglobin blood
	50931, --Hemoglobin blood
    52569, --glucose blood
	51755, --glucose blood
    51756, --white blood cells blood
	51279, --red blood cells
	51638, --Red blood cells
    51639, --Hematocrit blood
	53154, --Lactate blood
	50988, --Testosterone blood
	50930, --globulin blood
	50885, --Globulin blood
    53089, --Bilirubin, Total, blood
	50821, --pO2 blood gas
	50816, --oxygen blood gas
	50817, --oxygen saturation blood gas
	50818 -- pCPO2 blood gas
  )
),

-- Nu er vi seje, og gør det præcis samme, men for vitale ting.
vital_charts AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id::integer AS stay_id,
    REPLACE(di.label, ',', ' ')::text AS label, --Label er fra anden csv fil
    ce.charttime,
    ce.storetime,
    ce.itemid::integer AS itemid,
    ce.value::text AS value,
    ce.valuenum::double precision AS valuenum,
    ce.valueuom::text AS valueuom,
    NULL::text AS flag,
    ce.warning::smallint AS warning,
    'vital'::text AS source --fungerer på samme måde som anden source
  FROM mimiciv_icu.chartevents ce
  JOIN mimiciv_icu.d_items di --Her finder vi labels fra
    ON ce.itemid = di.itemid --Så kun der hvor itemid overlapper
  JOIN filtered_patients fp --Igen, vi vil kun have de patienter fra vanco query.
    ON ce.subject_id = fp.subject_id --Vi matcher subject id
   AND ce.hadm_id = fp.hadm_id --Og matcher hadm_id
  WHERE ce.itemid IN ( --Vi vil kun have tingene for disse itemIDS
    223762, -- Temperature Celsius
    220045, -- Heart Rate
    220050, -- Arterial BP systolic
    220051, -- Arterial BP diastolic
    220052, -- Arterial BP mean
    220059, -- Pulmonary Artery Pressure systolic
    220060, -- Pulmonary Artery Pressure diastolic
    220061, -- Pulmonary Artery Pressure mean
    220210  -- Respiratory Rate
  )
) --4665838

 --  ## SKROTTET # (Ikke nok patienter)
-- scores AS (
--   select
--     ce.subject_id,
--     ce.hadm_id,
--     ce.stay_id,
--     di.label, 
--     ce.itemid,
--     ce.caregiver_id,
--     ce.charttime,
--     ce.storetime,
--     ce.value,
--     ce.valuenum,
--     ce.valueuom,
--     ce.warning
--   from mimiciv_icu.chartevents ce
--   join mimiciv_icu.d_items di
--     on ce.itemid = di.itemid
--   JOIN filtered_patients fp
--     ON ce.subject_id = fp.subject_id
--    AND ce.hadm_id = fp.hadm_id
--   WHERE ce.itemid IN (
--   	227428, -- SOFA score
-- 	226743, -- APACHE II
-- 	226996, -- APS
-- 	226991 -- APACHEIII
--   )
-- )

--  -- This do be your output fr fr homie 
SELECT * --Vi vælger alt
FROM labevents --Fra labevents CTE
UNION ALL --Men vi sætter det hele sammen (Det kan vi gøre for de har samme størrelse og indeholder samme ting!)
SELECT * --Vælger alt 
FROM vital_charts --Fra vital CTE
order by subject_id, hadm_id; --Og sorterer efter subject_id og hadm id



