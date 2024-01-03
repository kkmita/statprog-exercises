*---------TASK DESCRIPTION START----------------------------------------------;
/*
This task is about producing a vertically-oriented summary report from typical
data collected in clinical trials.
We will work with a curated artifical dataset provided by the authors of
`mmrm` R package, the dataset is called `fev`
(link to documentation:
https://openpharma.github.io/mmrm/latest-tag/reference/fev_data.html).
It was exported from R to csv file and is stored as `fev.csv` 
(carefully, it contains missing data!).

`fev` dataset, although artificial, resembles a typical dataset from the domain
of clinical trials.

In Section I, we create a much simplified dataset `example`, based on which we produce
Report `Exemplary Report`.

The task is to create appropriate dataset `fev_for_report` of the similar structure as
`example`, and produce identically shaped `FEV Report`.

The `FEV Report` should:
a) contain two groups:
	1. FEV {<25, 25-<50, >50},
	2. FEV {<50, >50},
b) frequencies and percentages (percentages should be based on non-missing data!).

Provide your soultion in Section II
*/
*---------TASK DESCRIPTION END------------------------------------------------;




*###### SECTION I ############################################################;

proc import datafile="/home/u39759751/pharma/fev.csv"
        out=fev_
        dbms=csv
        replace;
     *getnames=no;
run;

/*
csv file was created in R and contains "NA" as missing values in `FEV1` column,
thus SAS treats it as categorical variable and does not recognize "NA" value
as a missing value.
Run `proc contents; run;` to confirm.
*/


data fev;
set fev_(rename=(FEV1 = FEV1C));
if FEV1C = "NA" then call missing(FEV1C);
FEV1 = input(FEV1C, best.);
drop FEV1C;
run;


/*
REPORT TO BE ACHIEVED ON THE EXEMPLARY DATA
*/

data example;
array arr25{4} $ _temporary_ ("NA" "< 25" "25 - <50" ">50");
array arr50{3} $ _temporary_ ("NA" "<50" ">50");
do visit_id="Week 0", "Week 2";
  do treatment="A", "B";
    do i=1 to 4;
      group = "fev25";
      _rvalue = arr25{i};
      _cresult = ROUND(RAND('NORMAL', 100, 50), 1);
      output;
    end;
    do j=1 to 3;
      group = "fev50";
      _rvalue = arr50{j};
      _cresult = ROUND(RAND('NORMAL', 100, 50), 1);
      output;
    end;
  end;
end;
dummy = .;
drop i j;
run;


title 'Exemplary Report';
proc report data=example;
column (visit_id group _rvalue treatment, (_cresult dummy));
define visit_id / group;
define group / group;
define _rvalue / group;
define treatment / across;
define _cresult / display;
define dummy / sum noprint;
run;
title;


*###### SECTION II ############################################################;


proc format;
  value fev25fmt
    .          = 'NA'
    low -< 25  = '< 25'
    25 -< 50   = '25 - <50'
    50 - high  = '>50'
  ;
  value fev50fmt
    .         = 'NA'
    low -< 50 = '<50'
    50 - high = '>50'
  ;
run;


data s1;
set fev;
fev25 = fev1;
fev50 = fev1;
run;

proc sort data=s1;
by armcd avisit fev1;
run;


proc means data=s1 noprint completetypes missing;
by ARMCD AVISIT;
class FEV25 FEV50 / preloadfmt;
var FEV1;
ways 1;
format FEV25 fev25fmt. FEV50 fev50fmt.;
output out=s2 n=;
run;


data s3a;
set s2;
where _TYPE_ = 1;
group = "FEV 50";
dummy = .;
_rvalue = put(FEV50, fev50fmt.);
keep AVISIT ARMCD GROUP _RVALUE _FREQ_ DUMMY;
;
run;

data s3b;
set s2;
where _TYPE_ = 2;
group = "FEV 25";
dummy = .;
_rvalue = put(FEV25, fev25fmt.);
keep AVISIT ARMCD GROUP _RVALUE _FREQ_ DUMMY;
run;

data s4;
length _RVALUE $ 20;
set s3a s3b;
run;


proc sql noprint;
create table s5 as
select t1.AVISIT, t1.ARMCD, t1.GROUP, t1._rvalue, t1._FREQ_, t2.SUM_FREQ,
  (t1._FREQ_ / t2.SUM_FREQ) as PERCENT, t1.DUMMY
from s4 as t1
left join
	(select AVISIT, ARMCD, GROUP, SUM(_FREQ_) as SUM_FREQ
	from s4
	where _rvalue ^= "NA"
	group by AVISIT, ARMCD, GROUP) as t2
on  t1.AVISIT = t2.AVISIT
and t1.ARMCD = t2.ARMCD
and t1.GROUP = t2.GROUP
;
quit;

data s6;
set s5;
_cresult = strip(put(_FREQ_, best12.)) !! " (" !! strip(put(percent, commax10.2)) !! "%)";
run;

title 'FEV Report';
proc report data=s6(where=(_RVALUE NE "NA"));
column (avisit group _rvalue armcd, (_cresult dummy));
define avisit / group;
define group / group;
define _rvalue / group;
define armcd / across;
define _cresult / display;
define dummy / sum noprint;
run;
title;









