﻿drop schema if exists "MW_datamodel" cascade;
create schema "MW_datamodel";

-------------------------
-- 0: Load source data --
-------------------------

--Preferred option to import csv through postgres_scripts/pg_import_csv.py

/* Alternatively you can first create and then upload through code like this
DROP TABLE "mw_source"."Indicators_FCS";
CREATE TABLE "mw_source"."Indicators_FCS" (
	ADM0_NAME text,ADM1_NAME text,ADM2_NAME text,PCODE text,FCS_Mean text,FCS_poor numeric,FCS_Borderline numeric,FCS_Acceptable numeric,Target_Group text,FCS_Month text,FCS_Year text,Methodology text,FCS_LowerThreshold text,FCS_UpperThreshold text,FCS_DataSource text,Indicator_Type text
);
COPY "mw_source"."Indicators_FCS" FROM 'C:\Users\JannisV\Rode Kruis\Malawi data\dbo-foodconsumptionscores.csv' DELIMITER ';' HEADER CSV;
--select * from "mw_source"."Indicators_FCS"
*/

--------------------------------
-- 1: Create datamodel tables --
--------------------------------

-------------------------------
-- 1.1: Boundary data tables --
-------------------------------

drop table if exists "MW_datamodel"."Geo_level2";
select case when t1.district = 'Chikwawa' then 'AFRMWI310' else t1.p_code end as pcode_level2
	,t1.district as name
	,substr(t1.p_code,1,7) as pcode_level1
	,t2.geom
into "MW_datamodel"."Geo_level2"
from "geo_source"."Geo_MW_level2" t1
join "geo_source"."Geo_MW_level2_mapshaper" t2 on t1.gid = t2.gid
;

drop table if exists "MW_datamodel"."Geo_level3";
select p_code as pcode_level3
	,trad_auth as name
	,substr(p_code,1,9) as pcode_level2
--	,substr(p_code,1,7) as pcode_level1
--	,case when pop2008 = 0 then 0 else 1 end as inhabited_ind
	,geom
into "MW_datamodel"."Geo_level3"
from "geo_source"."Geo_MW_level3_mapshaper"
;
/*
drop table if exists "MW_datamodel"."Geo_level4";
select t1.pcode_level3 || '-' || t0.id_3 as pcode_level4
	,name_3 as name
	,pcode_level3
	,geom
into "MW_datamodel"."Geo_level4"
from "geo_source"."Geo_MW_level4_mapshaper_new" t0
left join (select "ID_3" as id_3,max("adm3_P_COD") as pcode_level3 from "mw_source"."EA_GVH_mapping" group by 1) t1 on t0.id_3 = t1.id_3
where name_2 not in ('Lilongwe City','Zomba City','Mzuzu City','Blantyre City') and name_2 not like ('%Lake%')
union all
select p_code || '-1' as pcode_level4
	,trad_auth as name
	,p_code as pcode_level3
	,geom
from "geo_source"."Geo_MW_level3_mapshaper"
where district in ('Lilongwe City','Zomba City','Mzuzu City','Blantyre City')
;


drop table if exists "MW_datamodel"."Geo_level5";
select eacode as pcode_level5
	,ta || ' - EA ' || cast(feature as int) as name
	,adm3_P_COD || '-' || case when t1."ID_3" in (94,975,1987,3126) then 1 else t1."ID_3" end as pcode_level4
	,adm3_p_cod as pcode_level3
	,geom
into "MW_datamodel"."Geo_level5"
from "geo_source"."Geo_MW_level4_mapshaper" t0
left join "mw_source"."EA_GVH_mapping" t1 on t0.eacode = t1."EACODE"
where dist_code <> 0 and pop_sum > 0
;
--select * from "MW_datamodel"."Geo_level5"
*/

drop table if exists "MW_datamodel"."Geo_level4";
select eacode as pcode_level4
	,case when t1."EA_CODE" is not null then t1.name else ta || ' - GVH ' || cast(feature as int) end as name
	,adm3_p_cod as pcode_level3
	,geom
into "MW_datamodel"."Geo_level4"
from "geo_source"."Geo_MW_level4_mapshaper" t0
left join (
	select "EA_CODE"
		,min("GVH_name") || case when min("GVH_name") = max("GVH_name") then '' else '/' || max("GVH_name") end as name
	from mw_source."Indicators_4_GVH_names"
	group by 1) t1
on t0.eacode = t1."EA_CODE"
where dist_code <> 0 and pop_sum > 0
;


------------------------------------------
-- 1.2: Transform Indicator data tables --
------------------------------------------

------------------
-- Level 5 data --
------------------

drop table if exists "MW_datamodel"."Indicators_4_population";
select eacode as pcode_level4
	,pop_sum as population
	,st_area(st_transform(geom,31467))/1000000 as land_area
into "MW_datamodel"."Indicators_4_population"
from "geo_source"."Geo_MW_level4_mapshaper"
where dist_code <> 0
;
--select count(*) from "MW_datamodel"."Indicators_4_population"

drop table if exists "MW_datamodel"."Indicators_4_poverty";
select "EACODE" as pcode_level4
	,pov_rate as poverty_incidence
into "MW_datamodel"."Indicators_4_poverty"
from "mw_source"."Indicators_4_miscellaneous"
where "DIST_CODE" <> 0
;
--select count(*) from "MW_datamodel"."Indicators_4_poverty"

drop table if exists "MW_datamodel"."Indicators_4_traveltime";
select "EACODE" as pcode_level4
	,traveltime
	,tt_ea_ttcavg as traveltime_city
	,tt_ea_havg as traveltime_hospital
	,tt_ea_psavg as traveltime_prim_school
	,tt_ea_ssavg as traveltime_sec_school
	,tt_ea_tcavg as traveltime_tradingcentre
	,tt_ea_wpavg as traveltime_waterpoint
	,(tt_ea_havg + tt_ea_ssavg + tt_ea_tcavg) / 3 as traveltime_avg
into "MW_datamodel"."Indicators_4_traveltime"
from "mw_source"."Indicators_4_miscellaneous"
where "DIST_CODE" <> 0
;
--select * from "MW_datamodel"."Indicators_4_traveltime"

drop table if exists "MW_datamodel"."Indicators_4_hazards";
select "EACODE" as pcode_level4
--	,drought_in*filter as drought_risk
--	,10-log(1+(10-drought_in*filter))/log(11)*10 as drought_risk
	,drought_risk
	,case when flood_in*filter = 0 then 0
		else flood_in*filter/2 + 5 end as flood_risk
into "MW_datamodel"."Indicators_4_hazards"
from "mw_source"."Indicators_4_miscellaneous" t0
left join (
	select "EACODE" as pcode_level4
		,drought_risk/max_drought_risk*10 as drought_risk
	from mw_source."Indicators_4_drought_new" t0
	left join (select max(drought_risk) as max_drought_risk from mw_source."Indicators_4_drought_new") t1 on 1=1
	) t1
	on t0."EACODE" = t1.pcode_level4
where "DIST_CODE" <> 0
;
--select count(*) from "MW_datamodel"."Indicators_4_hazards"




/*
drop table if exists "MW_datamodel"."Indicators_4_echo2_areas";
select "EACODE" as pcode_level4
	,"filter_GVH" as echo2_area
into "MW_datamodel"."Indicators_4_echo2_areas"
from "mw_source"."Indicators_4_echo2_areas"
;
*/
drop table if exists "MW_datamodel"."Indicators_4_echo2_areas";
select pcode_level4
	,max(case when t1."GVH_name" is not null then 1 else 0 end) as echo2_area
into "MW_datamodel"."Indicators_4_echo2_areas"
from "MW_datamodel"."Geo_level4" t0
left join mw_source."Indicators_4_GVH_names" t1
	on t0.pcode_level4 = t1."EA_CODE"
group by 1
;

--RED CROSS capacity
drop table if exists "MW_datamodel"."Indicators_4_RC_capacity";
select t0.pcode_level4
	,t2.volunteers as rc_capacity
into "MW_datamodel"."Indicators_4_RC_capacity"
from "MW_datamodel"."Geo_level4" t0
left join "MW_datamodel"."Geo_level3" t1 on t0.pcode_level3 = t1.pcode_level3
left join (
	select aa.pcode_level2
		,aa.n_volunteers/(bb.population / 100000) as volunteers
	from (
	select t0.pcode_level2
		,sum("No of Volunteers") as n_volunteers
	from (select case when name in ('Blantyre','Blantyre City') then 'Blantyre'
			when name in ('Zomba','Zomba City') then 'Zomba'
			when name in ('Lilongwe','Lilongwe City') then 'Lilongwe'
			else name end as name
			,pcode_level2
		from "MW_datamodel"."Geo_level2" 
		) t0
	full outer join (
		select *
			,case when "Branch name" in ('Nsanje 1','Nsanje 2') then 'Nsanje'
				when "Branch name" in ('Chitipa 1','Chitipa 2') then 'Chitipa'
				when "Branch name" = 'Nkhatabay' then 'Nkhata Bay'
				when "Branch name" = 'Blantyre ' then 'Blantyre'
				when "Branch name" = 'Mzuzu' then 'Mzuzu City'
				when "Branch name" in ('Lilongwe Bua','Lilongwe') then 'Lilongwe'
				when "Branch name" = 'Mtakataka' then 'Dedza'
				else "Branch name" end as name
		from mw_source."Indicators_2_RC_capacity" 
		) t1	
		on t0.name = t1.name
	group by t0.pcode_level2
		) aa
	left join (
		select t0.pcode_level2
			,sum(population) as population
		from "MW_datamodel"."Geo_level3" t0
		left join "MW_datamodel"."Geo_level4" t1 on t0.pcode_level3 = t1.pcode_level3
		left join "MW_datamodel"."Indicators_5_population" t2 on t1.pcode_level4 = t2.pcode_level5
		group by 1
		) bb
		on aa.pcode_level2 = bb.pcode_level2
	) t2
	on t1.pcode_level2 = t2.pcode_level2
;
--select * from "MW_datamodel"."Indicators_4_RC_capacity";


drop table if exists "MW_datamodel"."Indicators_4_NGO_capacity";
select t0.pcode_level4
	,t2.active_organisations/(t3.population / 100000) as ngo_capacity
into "MW_datamodel"."Indicators_4_NGO_capacity"
from "MW_datamodel"."Geo_level4" t0
left join "MW_datamodel"."Geo_level3" t1 on t0.pcode_level3 = t1.pcode_level3
left join mw_source."Indicators_2_ngo_capacity" t2 on t1.pcode_level2 = t2.pcode_level2
left join (
	select t0.pcode_level2
		,sum(population) as population
	from "MW_datamodel"."Geo_level3" t0
	left join "MW_datamodel"."Geo_level4" t1 on t0.pcode_level3 = t1.pcode_level3
	left join "MW_datamodel"."Indicators_5_population" t2 on t1.pcode_level4 = t2.pcode_level5
	group by 1
	) t3
	on t1.pcode_level2 = t3.pcode_level2
;
--select * from "MW_datamodel"."Indicators_5_NGO_capacity";


------------------
-- Level 3 data --
------------------

--PLACEHOLDER for adding new level 3 indicator
/*
drop table if exists "MW_datamodel"."Indicators_3_XXX";
select <pcode_identifier> as pcode_level3
	,<transformation of indicator_XXX> as <new_name_XXX>
into "MW_datamodel"."Indicators_3_XXX"
from "mw_source"."Indicators_3_XXX"
join <possibly join with any other tables necessary for transformations> 
where <possibly apply any filters here>
;
*/

--Use 2014 district-level population to extrapolate 2008 TA-level population
drop table if exists "MW_datamodel"."Indicators_3_pop_area";
with popgrowth as (
select "Pcode" as pcode_level2
	,cast("population 2014" as float) / cast("population 2008" as float) as pop_growth
--into "MW_datamodel"."Indicators_2_popgrowth"
from "mw_source"."malawi_pop2014"
)
select p_code as pcode_level3
	,substr(p_code,1,9) as pcode_level2
	--,pop2008 * pop_growth as population
	,st_area(st_transform(geom,31467))/1000000 as land_area
into "MW_datamodel"."Indicators_3_pop_area"
from "geo_source"."Geo_MW_level3_mapshaper" t0
left join popgrowth t1 on substr(t0.p_code,1,9) = t1.pcode_level2
;

drop table if exists "MW_datamodel"."Indicators_3_hazards";
select p_code as pcode_level3
	,substr(p_code,1,9) as pcode_level2
	,cs_sum + cy_sum as cyclone_phys_exp 	/* Combine into one variable */
	,dr_sum as drought_phys_exp
	,eq7_sum as earthquake7_phys_exp
	,fl_sum as flood_phys_exp
--	,ls_sum as landslide_phys_exp 		/* Leave out for now (not in INFORM) */
	,ts_sum as tsunami_phys_exp
into "MW_datamodel"."Indicators_3_hazards"
from "mw_source"."Indicators_Zonal_Stats"
;

drop table if exists "MW_datamodel"."Indicators_3_gdp_traveltime";
select p_code as pcode_level3
	,substr(p_code,1,9) as pcode_level2
	,gdp_sum * 1000 as gdp
	,tt_mean as traveltime
into "MW_datamodel"."Indicators_3_gdp_traveltime"
from "mw_source"."Indicators_Zonal_Stats"
;

drop table if exists "MW_datamodel"."Indicators_3_poverty";
select "P_CODE" as pcode_level3
	,case when pov > 1.00 then 1.00 else pov end as poverty_incidence
into "MW_datamodel"."Indicators_3_poverty"
from "mw_source"."Indicators_3_poverty"
;

drop table if exists "MW_datamodel"."Indicators_3_health";
SELECT "P_CODE" as pcode_level3
	,case when nr_health is null then 0 else nr_health end as nr_health_facilities
INTO "MW_datamodel"."Indicators_3_health"
FROM mw_source."Indicators_3_health"
;

--electricity data Arjen
drop table if exists "MW_datamodel"."Indicators_3_electricity";
select "P_CODE" as pcode_level3
	,case "Elec_Im_Ni" when  'Yes' then 1 when 'No' then 0 else 0.5 end as electricity
into "MW_datamodel"."Indicators_3_electricity"
from "mw_source"."Indicators_3_electricity"
;

------------------
-- Level 2 data --
------------------

--PLACEHOLDER for adding new level2 indicator
/*
drop table if exists "MW_datamodel"."Indicators_2_XXX";
select <pcode_identifier> as pcode_level2
	,<transformation of indicator_XXX> as <new_name_XXX>
into "MW_datamodel"."Indicators_2_XXX"
from "mw_source"."Indicators_2_XXX"
join <possibly join with any other tables necessary for transformations> 
where <possibly apply any filters here>
;
*/



drop table if exists "MW_datamodel"."Indicators_2_FCS";
select pcode as pcode_level2
	,fcs_acceptable / 100 as FCS
into "MW_datamodel"."Indicators_2_FCS"
from "mw_source"."Indicators_FCS"
;

drop table if exists "MW_datamodel"."Indicators_2_knoema";
with temp as (
select "P_CODE_DISTRICT" as pcode_level2
	,avg("Value.Proportion of households with access to mobile phone_Tota")/100 as mobile_access
	,avg(("Value.Life expectancy at birth_Female" + "Value.Life expectancy at birth_Male")/2) as life_expectancy
--	,avg("Value.Poverty status_Poor"/100) as poverty_incidence
--	,avg("Value.Poverty status_Ultra poor") as poverty_incidence_ultra
	,avg("Value.Proportion with access to improved sanitation_Total_Perce"/100) as improved_sanitation
	,avg("Value.Source of drinking water_Spring/River/Stream/Pond/Lake/Da"/100) as watersource_spring
	,avg("Value.Source of drinking water_Piped into dwelling_Percent"/100) as watersource_pipe_personal
	,avg("Value.Source of drinking water_Piped into yard/plot/Communal St"/100) as watersource_pipe_communal
	,avg("Value.Source of drinking water_Protected well in yard/plot/publ"/100) as watersource_well_protected
	,avg("Value.Source of drinking water_Open well in yard/plot/open publ"/100) as watersource_well_open
	,avg("Value.Infant mortality rate_Total <1 yr") as infant_mortality
	,avg("Value.Type of construction materials_Permanent"/100) as construction_permanent
	,avg("Value.Type of construction materials_Traditional"/100) as construction_traditional
	,avg("Value.Type of construction materials_Semi-permanent"/100) as construction_semipermanent
FROM mw_source."Indicators_Thomas"
group by 1
)
select pcode_level2
	,mobile_access
	,life_expectancy
--	,poverty_incidence
	,improved_sanitation
	,(watersource_pipe_personal+watersource_pipe_communal)/(watersource_pipe_personal+watersource_pipe_communal+watersource_well_protected+watersource_well_open+watersource_spring) as watersource_piped
	,infant_mortality
	,(construction_permanent+construction_semipermanent)/(construction_permanent+construction_traditional+construction_semipermanent) as construction_semipermanent
INTO "MW_datamodel"."Indicators_2_knoema"
FROM temp
;


-----------------------------------------------
-- 1.3: Create one Indicator table per level--
-----------------------------------------------

drop table if exists "MW_datamodel"."Indicators_4_TOTAL_temp";
select t0.pcode_level4 as pcode
	,t0.pcode_level3 as pcode_parent
	,t1.population
	,t1.land_area
	,population / land_area as pop_density
	,t2.poverty_incidence
	,t3.traveltime
	,t3.traveltime_hospital,traveltime_sec_school,traveltime_tradingcentre
	,t4.drought_risk,flood_risk
	,t5.echo2_area
	,t6.rc_capacity
	,t7.ngo_capacity
into "MW_datamodel"."Indicators_4_TOTAL_temp"
from "MW_datamodel"."Geo_level4" t0
left join "MW_datamodel"."Indicators_4_population" t1	on t0.pcode_level4 = t1.pcode_level4
left join "MW_datamodel"."Indicators_4_poverty" t2	on t0.pcode_level4 = t2.pcode_level4
left join "MW_datamodel"."Indicators_4_traveltime" t3	on t0.pcode_level4 = t3.pcode_level4
left join "MW_datamodel"."Indicators_4_hazards" t4	on t0.pcode_level4 = t4.pcode_level4
left join "MW_datamodel"."Indicators_4_echo2_areas" t5	on t0.pcode_level4 = t5.pcode_level4
left join "MW_datamodel"."Indicators_4_RC_capacity" t6	on t0.pcode_level4 = t6.pcode_level4
left join "MW_datamodel"."Indicators_4_NGO_capacity" t7	on t0.pcode_level4 = t7.pcode_level4
;
--select * from "MW_datamodel"."Indicators_4_TOTAL_temp"
/*
drop table if exists "MW_datamodel"."Indicators_5_TOTAL_temp";
select t0.pcode_level5 as pcode
	,t0.pcode_level4 as pcode_parent
--	,t0.pcode_level3 as pcode_parent
	,t1.population
	,t1.land_area
	,population / land_area as pop_density
	,t2.poverty_incidence
	,t3.traveltime
	,t3.traveltime_hospital,traveltime_sec_school,traveltime_tradingcentre
	,t4.drought_risk,flood_risk
	,t5.echo2_area
	,t6.rc_capacity
	,t7.ngo_capacity
into "MW_datamodel"."Indicators_5_TOTAL_temp"
from "MW_datamodel"."Geo_level5" t0
left join "MW_datamodel"."Indicators_5_population" t1	on t0.pcode_level5 = t1.pcode_level5
left join "MW_datamodel"."Indicators_5_poverty" t2	on t0.pcode_level5 = t2.pcode_level5
left join "MW_datamodel"."Indicators_5_traveltime" t3	on t0.pcode_level5 = t3.pcode_level5
left join "MW_datamodel"."Indicators_5_hazards" t4	on t0.pcode_level5 = t4.pcode_level5
left join "MW_datamodel"."Indicators_5_echo2_areas" t5	on t0.pcode_level5 = t5.pcode_level5
left join "MW_datamodel"."Indicators_5_RC_capacity" t6	on t0.pcode_level5 = t6.pcode_level5
left join "MW_datamodel"."Indicators_5_NGO_capacity" t7	on t0.pcode_level5 = t7.pcode_level5
;
--select * from "MW_datamodel"."Indicators_5_TOTAL_temp"
--drop table if exists "MW_datamodel"."Indicators_4_TOTAL_temp";
--select *
--into "MW_datamodel"."Indicators_4_TOTAL_temp"
--from "MW_datamodel"."Indicators_5_TOTAL_temp";

drop table if exists "MW_datamodel"."Indicators_4_TOTAL_temp";
select t0.pcode_level4 as pcode
	,t0.pcode_level3 as pcode_parent
	,level5.population,land_area,pop_density,poverty_incidence,traveltime,traveltime_hospital,traveltime_sec_school,traveltime_tradingcentre
		,echo2_area
		,drought_risk,flood_risk
		,rc_capacity,ngo_capacity
into "MW_datamodel"."Indicators_4_TOTAL_temp"
from "MW_datamodel"."Geo_level4" t0
left join (
	select pcode_parent
		,sum(population) as population
		,sum(land_area) as land_area
		,sum(pop_density * land_area) / sum(land_area) as pop_density
		,sum(poverty_incidence * population) / sum(population) as poverty_incidence
		,sum(traveltime * population) / sum(population) as traveltime
		,sum(flood_risk * population) / sum(population) as flood_risk
		,sum(drought_risk * population) / sum(population) as drought_risk
		,sum(traveltime_hospital * population) / sum(population) as traveltime_hospital
		,sum(traveltime_sec_school * population) / sum(population) as traveltime_sec_school
		,sum(traveltime_tradingcentre * population) / sum(population) as traveltime_tradingcentre
		,max(echo2_area) as echo2_area
		,max(rc_capacity) as rc_capacity
		,max(ngo_capacity) as ngo_capacity
	from "MW_datamodel"."Indicators_5_TOTAL_temp"
	group by 1
	) level5
	on t0.pcode_level4 = level5.pcode_parent
;
--select * from "MW_datamodel"."Indicators_4_TOTAL_temp"
*/

drop table if exists "MW_datamodel"."Indicators_3_TOTAL_temp";
select t0.pcode_level3 as pcode
	,t0.pcode_level2 as pcode_parent
	,level4.population,poverty_incidence,traveltime/*traveltime_hospital,traveltime_sec_school,traveltime_tradingcentre,*/
		,echo2_area,rc_capacity,ngo_capacity,drought_risk
	,land_area
	,population / land_area as pop_density	
--	,case when population = 0 then null else cyclone_phys_exp / population end as cyclone_phys_exp
--	,case when population = 0 then null else drought_phys_exp / population end as drought_phys_exp
	,case when population = 0 then null else earthquake7_phys_exp / population end as earthquake7_phys_exp
	,case when population = 0 then null else flood_phys_exp / population end as flood_phys_exp
--	,case when population = 0 then null else tsunami_phys_exp / population end as tsunami_phys_exp
--	,case when population = 0 then null else gdp / population end as gdp_per_capita
--	,traveltime
	,t4.nr_health_facilities
	,case when population/10000 = 0 then null else cast(t4.nr_health_facilities as float)/ (cast(population as float) / 10000) end as health_density
	--,t5.poverty_incidence
	,t6.electricity
	--ADD NEW VARIABLES HERE
	--,t6.XXX
into "MW_datamodel"."Indicators_3_TOTAL_temp"
from "MW_datamodel"."Geo_level3" t0
left join (
	select pcode_parent
		,sum(population) as population
		,sum(land_area) as land_area
		,sum(pop_density * land_area) / sum(land_area) as pop_density
		,sum(poverty_incidence * population) / sum(population) as poverty_incidence
		,sum(traveltime * population) / sum(population) as traveltime
		,sum(drought_risk * population) / sum(population) as drought_risk
		,sum(traveltime_hospital * population) / sum(population) as traveltime_hospital
		,sum(traveltime_sec_school * population) / sum(population) as traveltime_sec_school
		,sum(traveltime_tradingcentre * population) / sum(population) as traveltime_tradingcentre
		,max(echo2_area) as echo2_area
		,max(rc_capacity) as rc_capacity
		,max(ngo_capacity) as ngo_capacity
	from "MW_datamodel"."Indicators_4_TOTAL_temp"
	group by 1
	) level4
	on t0.pcode_level3 = level4.pcode_parent
--left join "MW_datamodel"."Indicators_3_pop_area" 	t1	on t0.pcode_level3 = t1.pcode_level3
left join "MW_datamodel"."Indicators_3_hazards" 	t2	on t0.pcode_level3 = t2.pcode_level3
--left join "MW_datamodel"."Indicators_3_gdp_traveltime" 	t3	on t0.pcode_level3 = t3.pcode_level3
left join "MW_datamodel"."Indicators_3_health" 		t4	on t0.pcode_level3 = t4.pcode_level3
--left join "MW_datamodel"."Indicators_3_poverty" 	t5	on t0.pcode_level3 = t5.pcode_level3
left join "MW_datamodel"."Indicators_3_electricity" 	t6	on t0.pcode_level3 = t6.pcode_level3
--ADD NEW JOINED TABLE HERE
--left join "MW_datamodel"."Indicators_3_XXX" 		t6	on t0.pcode_level3 = t6.pcode_level3
;


drop table if exists "MW_datamodel"."Indicators_2_TOTAL_temp";
select t0.pcode_level2 as pcode
	,t0.pcode_level1 as pcode_parent
	,level3.population,land_area,pop_density,echo2_area,rc_capacity,ngo_capacity
		,drought_risk,earthquake7_phys_exp,flood_phys_exp
		,traveltime,nr_health_facilities,health_density,poverty_incidence
		,electricity
	--PLACEHOLDER: Add the newly added level3 indicators here again as well
	--,level3.XXX
	,t1.FCS
	,t2.mobile_access,life_expectancy,improved_sanitation,infant_mortality,watersource_piped,construction_semipermanent
	--ADD NEW VARIABLES HERE
	--,t3.XXX
into "MW_datamodel"."Indicators_2_TOTAL_temp"
from "MW_datamodel"."Geo_level2" t0
left join (
	select pcode_parent
		,sum(population) as population
		,sum(land_area) as land_area
		,sum(pop_density * land_area) / sum(land_area) as pop_density
		,max(echo2_area) echo2_area
		,max(rc_capacity) as rc_capacity
		,max(ngo_capacity) as ngo_capacity
--		,sum(cyclone_phys_exp * population) / sum(population) as cyclone_phys_exp
--		,sum(drought_phys_exp * population) / sum(population) as drought_phys_exp
		,sum(earthquake7_phys_exp * population) / sum(population) as earthquake7_phys_exp
		,sum(flood_phys_exp * population) / sum(population) as flood_phys_exp
		,sum(drought_risk * population) / sum(population) as drought_risk
--		,sum(tsunami_phys_exp * population) / sum(population) as tsunami_phys_exp
--		,sum(gdp_per_capita * population) / sum(population) as gdp_per_capita
		,sum(traveltime * population) / sum(population) as traveltime
		,sum(nr_health_facilities) as nr_health_facilities
		,sum(health_density * population) / sum(population) as health_density
		,sum(poverty_incidence * population) / sum(population) as poverty_incidence
		,sum(electricity * population) / sum(population) as electricity
		--PLACEHOLDER: ADD THE NEWLY ADDED LEVEL4 INDICATORS HERE AGAIN AS WELL with the appropriate transformation
		--,sum(XXX * population) / sum(population) as XXX
	from "MW_datamodel"."Indicators_3_TOTAL_temp"
	group by 1
	) level3
	on t0.pcode_level2 = level3.pcode_parent
left join "MW_datamodel"."Indicators_2_FCS" 	t1	on t0.pcode_level2 = t1.pcode_level2
left join "MW_datamodel"."Indicators_2_knoema" 	t2	on t0.pcode_level2 = t2.pcode_level2
--PLACEHOLDER: ADD TABLE WITH NEW VARIABLES HERE (IT SHOULD BE LEVEL2 ALREADY) 
--left join "MW_datamodel"."Indicators_2_XXX" 	t2	on t0.pcode_level2 = t2.pcode_level2
;


----------------------------------
-- 2.1: Calculate INFORM-scores --
----------------------------------

--calculate INFORM-scores at lowest level:level2
select usp_inform('MW',2);
select usp_inform('MW',3);
select usp_inform('MW',4);

-------------
-- Level 2 --
-------------

--ADD risk scores to Indicators_TOTAL table
drop table if exists "MW_datamodel"."Indicators_2_TOTAL";
select *
into "MW_datamodel"."Indicators_2_TOTAL"
from "MW_datamodel"."Indicators_2_TOTAL_temp" t0
left join "MW_datamodel"."total_scores_level2" t1
on t0.pcode = t1.pcode_level2
;
--select * from "MW_datamodel"."Indicators_2_TOTAL" 


--ADD risk scores to Indicators_TOTAL table
drop table if exists "MW_datamodel"."Indicators_3_TOTAL";
select *
into "MW_datamodel"."Indicators_3_TOTAL"
from "MW_datamodel"."Indicators_3_TOTAL_temp" t0
left join "MW_datamodel"."total_scores_level3" t1
on t0.pcode = t1.pcode_level3
;
--select * from "MW_datamodel"."Indicators_3_TOTAL" 

--ADD risk scores to Indicators_TOTAL table
drop table if exists "MW_datamodel"."Indicators_4_TOTAL";
select *
into "MW_datamodel"."Indicators_4_TOTAL"
from "MW_datamodel"."Indicators_4_TOTAL_temp" t0
left join "MW_datamodel"."total_scores_level4" t1
on t0.pcode = t1.pcode_level4
;
--select * from "MW_datamodel"."Indicators_4_TOTAL" order by volunteers_score







