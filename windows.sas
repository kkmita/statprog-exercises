/* TODOS:
-[ ] used relevant CDISC variables in `test` dataset
-[ ] should it be randomization date or other date per SAP for the mentioned windows?
*/

/*https://classic.clinicaltrials.gov/ProvidedDocs/79/NCT03347279/SAP_003.pdf p33*/

/* 01 LOOKUP TABLE */

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

/* 02 DATA SIMULATION TO COVER DIFFERENT SCENARIOS */

/*
Macro to increase a given datetime by a combination of
days and/or hours.

@param dt the numeric datetime value
@param days integer specifying how many days to add
@param hours integer specifying how many hours to add

@examples
%let RANDDT_value = %sysevalf("01JAN2023:10:00:00"dt);
%increase(&RANDDT_value., days=1);
%increase(&RANDDT_value., hours=5);
%increase(&RANDDT_value., days=2, hours = 2);
*/
%macro increase(dt, days=0, hours=0);
	%let output = &dt.;
	%*put [! output = &output.];
	%if &days. ne 0 %then %do;
		%let output = %sysfunc(intnx(dtday, &output., &days., same));
	%end;
	%if &hours. ne 0 %then %do;
		%let output = %sysfunc(intnx(dthour, &output., &hours., same));
	%end;
	%put &output.;
	%*put [>> old date: %sysfunc(putn(&dt., datetime.))];
	%*put [>>   increased by &days. days and &hours. hours];
	%*put [>> new date: %sysfunc(putn(&output., datetime.))];
%mend;

/*[COMMENT:] we will not use the macro above after considerations, yet we leave it
             as a proof of work and for other students to get inspiration*/

* set the randomization value;
%let RANDDT_value = %sysevalf("01JAN2023:10:00:00"dt);


* create test data in two steps ;
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

proc print data=test; where true_flag = "Y"; run;

* `train` dataset without information about answears ;
data train;
set test;
drop true: description;
run;


/* 03 THE TASK */

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


/* === 04 THE SOLUTIONS === */

* Firstly, let's sort the data by the key ;

proc sort data=train;
by date;
run;

proc sort data=visit_windows;
by target_day;
run;

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


data solution_1(drop=i);
array starts{&sqlobs.} _temporary_ (&starts.);
set test;
relday = datdif(datepart(&RANDDT_value.), datepart(date), 'ACT/ACT');
do i=1 to dim(starts);
  if relday >= starts{i} then id_window = i;
end;
output;
run;


data solution_1a;
merge
  solution_1(in=a)
  visit_windows(rename=(true_id_window=id_window) keep=time_point true_id_window target_day)
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
from test as t1
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

/* TBD */

data b1;
set solution_1a;
distance = abs(target_day - relday);
run;


proc sort data=b1;
by id_window distance date;
run;

proc print data=b1(keep=description date relday distance true_flag avaln);
run;

proc rank data=b1 out=b2 ties=mean;
by id_window;
var distance date;
ranks rank_dist rank_date;
run;

proc print data=b2(keep=description time_point date relday distance true_flag avaln rank_dist rank_date);
run;

* a convience macro to create `first.` and `last.` groups for `groups` variable ;



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

%by_groups(din=b2, dout=b3, groups=id_window rank_dist rank_date);

title "Case 1";
proc print data=b3; 
where description="Case 1";
run;

title "Case 4";
proc print data=b3; 
where description="Case 4";
run;
title;

* FIRST WAY - DATA STEPS ;

data b4;
retain sum no rank_date_number;
set b3;
*where description in ("Case 1", "Case 4");
by id_window rank_dist rank_date;
if first.id_window and first.rank_date then do;
  sum = 0;
  no = 0;
  rank_date_number=0;
end;  
sum + avaln;
no + 1;
rank_date_number + last_rank_date;
run;

proc print; run;

data b5;
set b4;
if rank_date_number = 1 then do;
  avaln = sum / no;
  output;
end;

proc print; run;


* SECOND WAY - PROC MEANS ;

data c;
retain group_id;* group_first_id_window;
set b3;
if first_rank_date then do;
  group_id + 1;
  *group_first_id_window = first_id_window;
end;  
run;

proc print; run;


proc means data=c max mean noprint;
by group_id;
var avaln first_id_window;
output out=c1(where=(b=1))
 mean(avaln)=a max(first_id_window)=b;* max first_id_window;
run;



