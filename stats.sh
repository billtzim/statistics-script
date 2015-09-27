#!/bin/bash

if [ $# -lt 1 ]; then
	echo "No arguments given!"
	echo "valid format --> service:metric:period"
	echo "valid format --> service:metric:period:startdate:enddate"
	exit
fi

query=""
startdate=""
enddate=""
dry_run=0
base_dir="$(dirname $(readlink -f ${BASH_SOURCE[0]}))/"
query_date=""

check_ui_prereq()
{
	dialog=$(which dialog)
	if [[ -z "$dialog" ]]; then
		echo "You need to install dialog command for the UI to work --> apt-get install dialog"
		exit
	fi 
}

ask_past_dates()
{
	startdat=$(dialog --stdout --date-format %d-%m-%Y --title "My Statistics Start Date for ${METRICARRAY[$z-1]}" --calendar "Select a start date:" 0 0 $(date +%d) $(date +%m) $(date +%Y))
	if [[ ! -z "$startdat" ]]; then
		enddat=$(dialog --stdout --date-format %d-%m-%Y --title "My Statistics End Date for ${METRICARRAY[$z-1]}" --calendar "Select an end date:" 0 0 $(date +%d) $(date +%m) $(date +%Y))
	fi

	if [ ":"$startdat":"$enddat == "::" ] ; then
		echo ""
	else
		echo ":"$startdat":"$enddat
	fi
}

showui()
{
	rm -f ./parameters
	COUNTER=1
	CHECKLIST=""
	SRVARRAY=(`echo 'select group_concat(distinct Service order by Service Asc SEPARATOR " ") from stat' | mysql -uUSER -pPASS -h DBSERVER -N -D stats`)
	for i in ${SRVARRAY[*]}; do
    		CHECKLIST="$CHECKLIST $COUNTER $i off "
    		let COUNTER=COUNTER+1
	done

	dialog --checklist "Choose services:" 15 40 35 $CHECKLIST 2> tempfile

	SelectedSrvs=(`cat tempfile && rm tempfile`)
	#echo "ARRAY is: "${SelectedSrvs[*]}
	for x in ${SelectedSrvs[*]}; do
		#echo ${SRVARRAY[i-1]}
	        METRICARRAY=(`echo 'select group_concat(distinct metric.id order by metric.id Asc SEPARATOR " ") from metric left join stat on metric.id=stat.metric where Service="'${SRVARRAY[x-1]}'";' | mysql -uUSER -pPASS -h DBSERVER -N -D stats`)
		COUNTER=1
		CHECKLIST=""
		for y in ${METRICARRAY[*]}; do
        	        CHECKLIST="$CHECKLIST $COUNTER $y off "
                	let COUNTER=COUNTER+1
	        done

		dialog --checklist "Choose metric for service <${SRVARRAY[x-1]}>:" 15 40 35 $CHECKLIST 2> tempfile

		SelectedMetrics=(`cat tempfile && rm tempfile`)
		for z in ${SelectedMetrics[*]}; do
			case "${METRICARRAY[$z-1]}" in
				daily*)
					echo -n "${SRVARRAY[$x-1]}:${METRICARRAY[$z-1]}:daily"`ask_past_dates` >> parameters
					;;
				monthly*)
					echo -n "${SRVARRAY[$x-1]}:${METRICARRAY[$z-1]}:monthly"`ask_past_dates` >> parameters
					;;
				yearly*)
					echo -n "${SRVARRAY[$x-1]}:${METRICARRAY[$z-1]}:yearly"`ask_past_dates` >> parameters
					;;
				current*)
					PERIOD_TYPES=(daily monthly yearly)
					dialog --checklist "Choose period for type CURRENT metric for service ${SRVARRAY[$x-1]}:" 15 40 35 1 daily off 2 monthly off 3 yearly off 2> tempfile
					period=(`cat tempfile && rm tempfile`)
					#period=$1 #(`cat tempfile && rm tempfile`)
					echo -n "${SRVARRAY[$x-1]}:${METRICARRAY[$z-1]}:${PERIOD_TYPES[$period-1]}"`ask_past_dates` >> parameters
					;;
				*) ;;
			esac
		done
	done
}


check_dated()
{
        if [ ! -z "$startdate" ]; then # -z string = True if the length of string is zero.
                if [ -z "$enddate" ]; then
                        enddate=$(date +%F)
                fi
		value="-dated"
        else
                value=""
        fi

        echo $value
}

build_query()
{
	if [ "$value" == "not implemented" ]; then
		exit
	fi
	if [ ! -z "$startdate" ]; then
		echo "replace into stat values('','$service','$metric','$startdate','$period','$value');"
	else
		echo "insert into stat values('','$service','$metric','$query_date','$period','$value');"
		#echo "insert into stat values('','$service','$metric','$(date +%F)','$period','$value');"
		#echo "insert into stat values('','$service','$metric','$(date +%Y-%m-01 --date="last month")','$period','$value');"
	fi
}


while getopts ":du" flag; 
do
	case "$flag" in
		d|dry-run)
			dry_run=1
			shift
			;;
		u|ui)
			check_ui_prereq
			showui
			shift
			;;
		*)
			;;
	esac
done

while [ "$1" != "" ]; do
	IFS=":" read service metric period startdate enddate <<< "$1"
	# rsync -avz -t "remoterepo:/noc/scripts/conf/"$service".cfg ./conf
	source $base_dir"conf/"$service".cfg"
	case "$period" in
		daily)
			query_date=`date +%F`
			value=$("$metric"`check_dated`)
			;;
		monthly)
			query_date=`date +%Y-%m-01 --date="last month"`
			value=$("$metric"`check_dated`)
			;;
		yearly)
			query_date=`date +%Y-01-01 --date="last year"`
			value=$("$metric"`check_dated`)
			;;
		#current)
		#	value=$("$metric-$period"`check_dated`)
		#	;;
		*)
			value="NULL"
			echo "no valid period for $service $metric"
	esac
	query+=`build_query`
	shift
done

if [ "$dry_run" == 1 ]; then
	echo "DRY - "$query 
else
	echo $query | mysql -uUSER  -pPASS -D stats -h DBSERVER
fi
