*---------TASK DESCRIPTION START----------------------------------------------;
/*
This task is about creating an analysis flag for visit windows
per instructions in openly available NAVIGATOR Statistical Analysis Plan, p.33:
https://classic.clinicaltrials.gov/ProvidedDocs/79/NCT03347279/SAP_003.pdf.

In Section I, we create two datasets:
a) `visit_windows`, which is a lookup table implementing rules described in SAP,
b) `test`, which contains unit test cases, together with information about
the expected result.

In `test` dataset, there are two specific flags:
1. `true_flag` in ('Y', 'N'): analysis flag for the record that should be chosen
as the correct analysis observation,
2. `raw` in ('Y', 'N'): whether a given record is the source data (raw data).
Note that the rules in SAP require to calculate average of the values in given cases,
and therefore the correct (i.e., `true_flag` = 'Y') observation may not be raw,
meaning it is not the collected data, but a function of the collected data.

Section II described the rules from SAP that shall be applied by the user
in Section III.

*/
*---------TASK DESCRIPTION END------------------------------------------------;


*###### SECTION I ############################################################;


* set the randomization value;
%let RANDDT_value = %sysevalf("01JAN2023:10:00:00"dt);


data visit_windows;
retain true_id_window -1;
length time_point $20 window $7;
infile datalines delimiter=",";
*Time Point,Target,Day,Visit Window;
input time_point $ target_day window $;
start_window = input(scan(window, 1, '-'), best.);
end_window = input(scan(window, -1, '-'), best.);
true_id_window + 1;
datalines;
Baseline (Week 0),1,
Week 2,15,2-21
Week 4,29,22-42
Week 8,57,43-70
Week 12,85,71-98
Week 16,113,99-126
Week 20,141,127-154
;
run;


data test_raw;
infile datalines delimiter="#";
length true_window $20 true_flag $1 description $200 raw $1;
input relative_day relative_hour true_window $ true_flag $ 
/ description $ raw $;
DATE = intnx('dthour',
              intnx('dtday', &RANDDT_value., relative_day, "same"),
              relative_hour);
USUBJID = "A01";
format DATE datetime.;
datalines;
12#0#Week 2#Y#
Case 1#Y
12#2#Week 2#N#
Case 1#Y
18#0#Week 2#N#
Case 1#Y
24#0#Week 4#N#
Case 2#Y
24#3#Week 4#N#
Case 2#Y
31#1#Week 4#Y#
Case 2#Y
57#0#Week 8#Y#
Case 3#Y
80#0#Week 12#N#
Case 4#Y
87#5#Week 12#N#
Case 4#Y
87#5#Week 12#N#
Case 4#Y
142#5#Week 20#N#
Case 5#Y
142#5#Week 20#N#
Case 5#Y
;
run;

data test_;
retain usubjid aeseq date avaln true_window true_flag;
array randoms{12} _temporary_ (160 180 182  30  56 147 103  66  81  82  37 156);
set test_raw(drop=relative_day relative_hour);
avaln = randoms{_n_};
aeseq + 1;
output;
run;

data test_no_raw(drop=relative_day relative_hour);
infile datalines delimiter="#";
length true_window $20 true_flag $1 description $200 raw $1;
input relative_day relative_hour true_window $ true_flag $ 
/ description $ raw $ avaln;
DATE = intnx('dthour',
              intnx('dtday', &RANDDT_value., relative_day, "same"),
              relative_hour);
USUBJID = "A01";
format DATE datetime.;
datalines;
87#0#Week 12#Y#
Case 4#N#81.5
142#2#Week 20#Y#
Case 5#N#96.5
;
run;

data test;
set test_ test_no_raw;
run;

data train;
set test;
where raw = "Y";
run;


*###### SECTION II ############################################################;


/*
Derive the final dataset `final`.
Rules from SAP (p. 32) re more than one non-missing value in the same window are as follows.

Rule 1. The non-missing value closest to the target day will be selected for analysis at that visit.

Rule 2. If two non-missing values are the same distance from the target day, the earlier of the
two values will be selected for analysis at that visit.

Rule 3. If two non-missing values are recorded on the same day and have a different
assessment time associated with both of them, the value with the earliest assessment
time will be selected for analysis at that visit.

Rule 4. If two non-missing values (for continuous variables) are recorded on the same day and
have no assessment time associated with at least one of them, or the same assessment
time associated with both of them, the average of the two values will be selected for
analysis at that visit. For categorical variables in this situation, the worst case will be
used.

Rule 5. If a subject has no value within a particular visit window, then the subject will have a missing
value at that visit in summaries and analysis.
[NOTE THAT WEEK 8 and 20 ARE MISSING FROM `test`]
*/


*###### SECTION III ############################################################;


/* === STEP (A) ===
join information from window_visits, i.e., an actual window together with its target day.
*/

* Now two ways of joining visit_window to train ;

/* ----- (I) WAY -----
this approach assumes a correct specification of the lookup table `visit_windows`,
i.e., that the windows are disjoint (it is easier to keep lookup table aside and
perform unit tests on it rather than perform it within the analysis program).
Based on that, we can focus only on the `start_window` variable, as it uniquely defines
given windows, and assign the associated ID of a given window.
*/


proc sql noprint;
select distinct start_window into :starts separated by ', '
from visit_windows
where start_window ne .;
quit;
%put [&starts.];


data solution_1_(drop=i);
array starts{&sqlobs.} _temporary_ (&starts.);
set train;
relday = datdif(datepart(&RANDDT_value.), datepart(date), 'ACT/ACT');
do i=1 to dim(starts);
  if relday >= starts{i} then id_window = i;
end;
output;
run;


proc sort data=solution_1_;
by id_window;
run;


data solution_1;
merge
  solution_1_(in=a)
  visit_windows(keep=time_point true_id_window target_day
                rename=(true_id_window=id_window) )
;
by id_window;
if a;
if true_window = time_point;
drop true_window;
run;


/* -----(II) WAY-----
This approach is based on PROC SQL, it's easier to read, but
requires more computational resources Cartesian joins are included.
*/


proc sql noprint;
create table solution_2_ as
select t1.*, t2.time_point, t2.target_day
from train as t1
left join visit_windows as t2
/*on t1.reldate between t2.start_window and t2.end_window*/
on datdif(datepart(&RANDDT_value.), datepart(t1.date), 'ACT/ACT') 
between t2.start_window and t2.end_window
;
quit;

data solution_2;
set solution_2_;
if true_window = time_point;
drop true_window;
run;



/* -----(III) WAY-----
Solution with harcoded checking of the time windows.
In general, hardcoding should be avoided as the data
are not isolated, cannot be easily unit tested, and
any changes requiring the windows will require to carefully
reexamine the analysis program.
*/

data solution_3;
length time_point $ 20;
set train;
relday = datdif(datepart(&RANDDT_value.), datepart(date), 'ACT/ACT');
select;
when ( 2  <= relday <= 21 ) time_point = "Week 2";
when ( 22 <= relday <= 42 ) time_point = "Week 4";
when ( 43 <= relday <= 70 ) time_point = "Week 8";
when ( 71 <= relday <= 98 ) time_point = "Week 12";
when ( 99 <= relday <= 126) time_point = "Week 16";
when ( 127<= relday <= 154) time_point = "Week 20";
otherwise time_point = "INCORRECT";
end;
run;


/* === STEP (B) ===
prepare dataset for implementingt rules,
we will need proper sorting and access to `first` and `last` variables.
*/


data rules1;
set solution_1;
distance = abs(target_day - relday);
run;


proc sort data=rules1;
by id_window distance date;
run;

/* proc print data=b1(keep=description date relday distance true_flag avaln); */
/* run; */
/*  */
/* proc rank data=b1 out=b2 ties=mean; */
/* by id_window; */
/* var distance date; */
/* ranks rank_dist rank_date; */
/* run; */


/*
create `first.` and `last.` groups for variables from `groups` 
macrovariable.

@param din a name of the input dataset
@param dout a name of the output dataset
@param groups a list of variable names separated by ' '
*/
%macro by_groups(din=, dout=, groups=);
	%let num=1;
	%let name=%scan(&groups., &num.);
	
data &dout.;
set &din.;
by &groups.;
	%do %while(&name. ne);
first_&name. = first.&name.;
last_&name. = last.&name.;
	  %let num=%eval(&num. + 1);
	  %let name=%scan(&groups., &num.);
	%end;
run;

%mend;


%*by_groups(din=b2, dout=b3, groups=id_window rank_dist rank_date);
%by_groups(din=rules1, dout=rules2, groups=id_window distance date);



/* === STEP (C) ===
Derive analysis flag `ANLFL`
*/


/* ----- (I) WAY -----
Use only data steps
*/

data final_ds1;
retain sum no rank_date_number;
set rules2;
*where description in ("Case 1", "Case 4");
*by id_window rank_dist rank_date;
by id_window distance date;
if first.id_window and first.date then do;
  sum = 0;
  no = 0;
  rank_date_number = 0;
end;  
sum + avaln;
no + 1;
rank_date_number + last_date;
run;

data final_ds2;
set final_ds1;
if rank_date_number = 1 then do;
  avaln = sum / no;
  output;
end;



/* ----- (II) WAY -----
Use proc means
*/


data final_proc1;
retain group_id;
set rules2;
if first_date then do;
  group_id + 1;
end;  
run;


proc means data=final_proc1
  max mean noprint;
by group_id;
var AVALN FIRST_ID_WINDOW;
output out=final_proc2(where=(MAX_WINDOW = 1))
  mean(AVALN)=
  max(FIRST_ID_WINDOW)=MAX_WINDOW
;
run;


proc sql noprint;
create table final_proc3 as
select t1.group_id, t2.time_point, t1.avaln
from final_proc2 as t1
left join (select distinct group_id, time_point
           from final_proc1) as t2
on t1.group_id = t2.group_id
;
quit;


/*---FINAL CHECK---*/

title "Final solution Data Steps";
proc print data=final_ds2;
run;

title "Final Solution with Proc Means";
proc print data=final_proc3;
run;

title "Test Data for Checking";
proc print data=test(where=(TRUE_FLAG = "Y"));
run;
title;
