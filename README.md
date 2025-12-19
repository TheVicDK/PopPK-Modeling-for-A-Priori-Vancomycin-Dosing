This is the readme file for the github files used for the paper "PopPK Modeling for A Priori Vancomycin Dosing: A Comparison of One- and Two-Compartment Models in a Large Clinical Dataset". 

In this github you will find SQL files to extract data from the MIMIC-IV 3.1 database, a model.R script which includes the code for one and two compartment model used in the paper. 

When extracting, please follow these steps: 
  setup a local postgreSQL database 
  run the Tabel1.SQL file. This might take a while. Afterwards save results as Table1
  run Tabel1_v2.SQL file. This gives you patients + dose and concentrations.
  run Tabel2.SQL 
  run Tabel3.SQL

Link to paper: 


If using the code or citing the paper, please cite to DOI: 
