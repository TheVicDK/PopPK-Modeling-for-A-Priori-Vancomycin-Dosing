WITH 

--Vælg kun specifikke subject_ids og hadm_ids
filtered_patients AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM Table1 -- Table1 var det jeg navngav vores query for vanco patienter i mimic 
),

-- Lav en CTE for patient information
patient_info AS (
  SELECT 
    hp.subject_id,
    fp.hadm_id, -- hosp.patient indeholder ikke hadm_id. Derfor snupper vi denne fra vanco query
    hp.gender,
    hp.anchor_age,
    hp.anchor_year,
    hp.dod  --date of death
  FROM mimiciv_hosp.patients hp --Kalder hosp.patients for hp
  JOIN filtered_patients fp --Her lægger vi det op imod de patienter fra vanco query. 
    ON hp.subject_id = fp.subject_id --Og vi tager KUN de patienter som også er i vanco.
),
  
--Lav CTE hvor vi puller height ud. Height ville ellers være en "måling"
height_data AS (
  SELECT 
    subject_id,
    hadm_id,
    MAX( --ensures you get one consistent value per patient admission.
      COALESCE( --picks the cm value if it exists, otherwise uses the converted inches.
        CASE WHEN itemid = 226730 THEN valuenum END,                  -- cm
        CASE WHEN itemid = 226707 THEN valuenum * 2.54 END            -- inches -> cm
      )
    ) AS height_cm
  FROM mimiciv_icu.chartevents
  WHERE itemid IN (226730, 226707)
  GROUP BY subject_id, hadm_id
),
  
-- Lav en CTE for patient admissioner  
patient_admissions AS (
  select
    ha.subject_id,
    ha.hadm_id,
    ha.admittime,
    ha.dischtime,
    ha.deathtime,
    ha.admission_type,
    ha.admit_provider_id,
    ha.admission_location,
    ha.discharge_location,
    ha.insurance,
    hd.height_cm,
    ha.language,
    ha.marital_status,
    ha.race,
    ha.edregtime,
    ha.edouttime,
    ha.hospital_expire_flag -- binær for om de døde under hospitalet
  FROM mimiciv_hosp.admissions ha
    JOIN filtered_patients fp 
      ON ha.subject_id = fp.subject_id --Her lægger vi op imod subject_id fra vanco query
      AND ha.hadm_id = fp.hadm_id --Og hadm_id fra vanco query
    LEFT JOIN height_data hd  --Vi vil have højde med! 
      ON ha.subject_id = hd.subject_id --Og matcher
     AND ha.hadm_id = hd.hadm_id --og matcher
),

  --Nu lægger vi dem sgu sammen. Så vi - ligesom Hannah Montana - får the best of both worlds
info_admission AS (
    SELECT 
      pi.subject_id, --Alle med pi er fra patient_info
      pa.hadm_id, -- Alle med pa er fra patient_admission
      pi.gender,
      pi.anchor_age,
      pi.anchor_year,
      pi.dod,
      pa.height_cm,
      pa.admittime,
      pa.dischtime,
      pa.deathtime,
      pa.admission_type,
      pa.admit_provider_id,
      pa.admission_location,
      pa.discharge_location,
      pa.insurance,
      pa.language,
      pa.marital_status,
      pa.race,
      pa.edregtime,
      pa.edouttime,
      (pa.dischtime - pa.admittime) AS los, --Length of stay beregner vi. Discharge time - admission time
      pa.hospital_expire_flag
    FROM patient_info AS pi
    LEFT JOIN patient_admissions pa --Ligesom før, sikrer vi os at alle subject ids og hadm_ids er ens.
        ON pi.subject_id = pa.subject_id
        AND pi.hadm_id    = pa.hadm_id
)

--Endegyldige SELECT som vi finder vores .csv ud fra.
SELECT *  --Vælger alt
from info_admission  --Fra den sammensatte CTE
ORDER BY subject_id, hadm_id; --Sorteret fra subject_id og hadm_id.

