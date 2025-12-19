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

-- Vi finder lige de patienter vi skal bruge. Med exclusion, kan vi snuppe subject_id og hadm_id fra vanco query. 
filtered_patients AS (
  SELECT distinct subject_id, hadm_id
  FROM Table1 --Navngivet table1 i min mimic, da jeg skulle navngive den noget
),


--Nu laver vi en CTE for vancopatienter
iv_vanco AS (
    SELECT 
        iv.subject_id,
        iv.hadm_id,
        iv.stay_id,
        iv.starttime AS iv_starttime, --Omdøbes da den skal sættes sammen med en anden. For præcisions skyld
        iv.endtime AS iv_endtime, -- Det samme gælder denne
        iv.amount AS iv_amount,
        iv.amountuom AS iv_amount_unit,
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


-- Match infusion med seneste ordination før infusionen (uden at fjerne koncentrationer)
conc_with_iv_and_presc AS (
    SELECT 
        iv.subject_id,
        iv.hadm_id,
        iv.iv_starttime,
        iv.iv_endtime,
        iv.iv_amount,
        iv.iv_amount_unit,
        pr.prescription_starttime,
        pr.dose_val_rx,
        pr.dose_unit_rx,
        pr.doses_per_24_hrs,
        pr.prod_strength,
        iv.patientweight
    FROM iv_vanco AS iv
    LEFT JOIN prescription_vanco AS pr
        ON  iv.subject_id = pr.subject_id
        AND iv.hadm_id    = pr.hadm_id
        AND pr.prescription_starttime = (
            SELECT MAX(pr2.prescription_starttime)
            FROM prescription_vanco pr2
            WHERE pr2.subject_id = iv.subject_id
              AND pr2.hadm_id = iv.hadm_id
              AND pr2.prescription_starttime < iv.iv_starttime
        )
)



SELECT
    c.subject_id,
    c.hadm_id,
    c.iv_starttime,
    c.iv_endtime,
    c.iv_amount,
    c.iv_amount_unit,
    c.prescription_starttime,
    c.dose_val_rx,
    c.dose_unit_rx,
    c.doses_per_24_hrs,
    c.prod_strength,
    c.patientweight
FROM conc_with_iv_and_presc c
JOIN filtered_patients fp
  ON c.subject_id = fp.subject_id
 AND c.hadm_id    = fp.hadm_id
ORDER BY c.subject_id, c.hadm_id;
