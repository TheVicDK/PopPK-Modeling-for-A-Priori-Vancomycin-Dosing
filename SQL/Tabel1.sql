WITH 
--Laver CTE for dialyse patienter vi ønsker at exklusdere 
exclude_dialysis AS (
    SELECT subject_id, hadm_id FROM mimiciv_icu.chartevents WHERE itemid = 225126 --Finder patienters hadm og subject id med dette itemid anvendt. 225126 = "Dialysis patient"
    UNION ALL -- Sætter sammen
    SELECT subject_id, hadm_id FROM mimiciv_icu.procedureevents WHERE itemid IN (225802, 225803, 225441) -- Vi finder patienters hadm og subject id som anvender disse itemids 
  -- 225802 =  Dialysis - CRRT
  -- 225803 = Dialysis - CVVHD
  -- 225441 = 'Hemodialysis'
    UNION ALL-- sætter sammen
    SELECT subject_id, hadm_id FROM mimiciv_hosp.procedures_icd WHERE icd_code = '3995' --finder patienters hadm og subject id med denne icd code. 3995 = hemodialysis i hosp procedures
),

exclude_pregnant AS ( --Vi samler gravide patienter
    SELECT subject_id, hadm_id FROM mimiciv_icu.chartevents WHERE itemid = 225082 -- 225082 = Pregnant. Finder gravide
),
  
exclude_all AS ( --Sammensætter de tre eksklusionsgrupper vi har lavet til én subgruppe.
    SELECT subject_id, hadm_id FROM exclude_dialysis
    UNION ALL --Sætter dialyse patienter sammen med preganante patienter
    SELECT subject_id, hadm_id FROM exclude_pregnant
),
  
  --Nu laver vi en CTE for vancopatienter
iv_vanco AS (
    SELECT 
        iv.subject_id,
        iv.hadm_id,
        iv.stay_id,
        iv.starttime AS iv_starttime, --Omdøbes da den skal sættes sammen med en anden. For præcisions skyld
        iv.endtime AS iv_endtime, -- Det samme gælder denne
        iv.amount,
        iv.amountuom,
        iv.rate,
        iv.rateuom,
        iv.orderid,
        iv.ordercategoryname,
        iv.ordercategorydescription,
        iv.patientweight,
        iv.totalamount,
        iv.totalamountuom,
        iv.statusdescription
    FROM mimiciv_icu.inputevents iv
    WHERE 
        iv.itemid = 225798 --Vancomycin itemID
        AND iv.ordercategoryname = '08-Antibiotics (IV)' -- og hvor ordercategoryname er antibiotics som er taget med IV
        AND NOT EXISTS ( -- MEN vi udtrækker ikke patienter som findes i vores ekskluderings CTE. 
            SELECT 1
            FROM exclude_all e
            WHERE e.subject_id = iv.subject_id --Alle patinter som overlapper i subject ID fjernes
            AND e.hadm_id    = iv.hadm_id --Alle patienter som overlapper i hadm_id fjernes
        )
),

-- Nu laves prescription CTE  
prescription_vanco AS (
    SELECT 
        pr.subject_id,
        pr.hadm_id,
        pr.starttime AS prescription_starttime, --Omdøbes for præcisions skyld
        pr.stoptime AS prescription_stoptime, --samme her
        pr.drug,
        pr.route,
        pr.dose_val_rx,
        pr.dose_unit_rx,
        pr.doses_per_24_hrs,
        pr.prod_strength,
        pr.form_val_disp,
        pr.form_unit_disp
    FROM mimiciv_hosp.prescriptions pr
    WHERE 
        LOWER(pr.drug) LIKE '%vancomycin%' -- Vi søger efter Vancomycin i DRUG
        AND LOWER(pr.route) = 'iv' --Men kun hvor det er indtaget via IV
    AND NOT EXISTS ( -- Men patienterne maa ikke eksistere i vores exkluderings CTE
            SELECT 1
            FROM exclude_all e 
            WHERE e.subject_id = pr.subject_id --Hvor patient id er ens 
              AND e.hadm_id    = pr.hadm_id -- Hvor hadm id er ens
        )
),

  -- Laver concentrations CTE 
con_vanco AS (
    SELECT 
        con.subject_id,
        con.hadm_id,
        con.charttime AS con_sample_time, --Omdøbes. Vi kommer til det
        con.valuenum AS vanco_concentration, --Omdøbes 
        con.valueuom AS vanco_concentration_unit --omdøbes
    FROM mimiciv_hosp.labevents con
    WHERE 
        con.itemid = 51009 --Itemid = vancomycin i blodet
),

-- Match hver koncentration med den seneste IV infusion før prøvetidspunkt
conc_with_iv AS (
    SELECT 
        con.subject_id,
        con.hadm_id,
        con.con_sample_time,
        con.vanco_concentration,
        con.vanco_concentration_unit,
        iv.iv_starttime,
        iv.iv_endtime,
        iv.patientweight,
        iv.amount AS iv_amount,
        iv.amountuom AS iv_amount_unit,
        ROW_NUMBER() OVER (
            PARTITION BY con.subject_id, con.hadm_id, con.con_sample_time
            ORDER BY iv.iv_starttime DESC
        ) AS rn
    FROM con_vanco AS con
    JOIN iv_vanco AS iv
        ON  con.subject_id = iv.subject_id
        AND con.hadm_id    = iv.hadm_id
        AND iv.iv_starttime < con.con_sample_time
),

-- Match infusion med seneste ordination før infusionen (uden at fjerne koncentrationer)
conc_with_iv_and_presc AS (
    SELECT 
        ci.subject_id,
        ci.hadm_id,
        ci.con_sample_time,
        ci.vanco_concentration,
        ci.vanco_concentration_unit,
        ci.iv_starttime,
        ci.iv_endtime,
        ci.iv_amount,
        ci.iv_amount_unit,
        pr.prescription_starttime,
        pr.dose_val_rx,
        pr.dose_unit_rx,
        pr.doses_per_24_hrs,
        pr.prod_strength,
        ci.patientweight
    FROM conc_with_iv AS ci
    LEFT JOIN prescription_vanco AS pr
        ON  ci.subject_id = pr.subject_id
        AND ci.hadm_id    = pr.hadm_id
        AND pr.prescription_starttime = (
            SELECT MAX(pr2.prescription_starttime)
            FROM prescription_vanco pr2
            WHERE pr2.subject_id = ci.subject_id
              AND pr2.hadm_id = ci.hadm_id
              AND pr2.prescription_starttime < ci.iv_starttime
        )
    WHERE ci.rn = 1
)

SELECT
    subject_id,
    hadm_id,
    con_sample_time,
    vanco_concentration,
    vanco_concentration_unit,
    iv_starttime,
    iv_endtime,
    iv_amount,
    iv_amount_unit,
    prescription_starttime,
    dose_val_rx,
    dose_unit_rx,
    doses_per_24_hrs,
    prod_strength,
    patientweight
FROM conc_with_iv_and_presc
ORDER BY subject_id, hadm_id, con_sample_time;
