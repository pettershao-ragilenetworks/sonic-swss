#!/bin/bash
## This script is to enable the gcov support of the SONiC source codes
work_dir=$(pwd)
env_home=$HOME

GCNO_LIST_FILE="gcno_file_list.txt"
GCDA_DIR_LIST="gcda_dir_list.txt"
TMP_GCDA_FILE_LIST="tmp_gcda_file_list.txt"
GCNO_ALL_TAR_GZ="gcno.tar.gz"

INFO_DIR=info
HTML_DIR=html
ALLMERGE_DIR=AllMergeReport

GCOV_OUTPUT=${work_dir}/gcov_output
GCOV_INFO_OUTPUT=${GCOV_OUTPUT}/${INFO_DIR}
GCOV_HTML_OUTPUT=${GCOV_OUTPUT}/${HTML_DIR}
GCOV_MERGE_REPORT_OUTPUT=${GCOV_OUTPUT}/${ALLMERGE_DIR}

HTML_FILE_PREFIX="GCOVHTML_"
HTML_FILE_LIST=${GCOV_OUTPUT}/htmllist
INFO_FILE_PREFIX="GCOVINFO_"
INFO_FILE_LIST=${GCOV_OUTPUT}/infolist
INFO_ERR_LIST=${work_dir}/info_err_list
CONTAINER_LIST=${work_dir}/containerlist
ALL_INFO_FILES=${work_dir}/allinfofileslist
REPE_INFO_LIST=${work_dir}/tmpinfolist
SINGLE_INFO_LIST=${work_dir}/singleinfolist

# change the env_var $HOME to a temporary one to ensure genhtml's reliability
add_new_home_for_sonic()
{
    local new_home=${work_dir}

    export HOME=${new_home}
    echo "new_home is $HOME"
}

# reset the env_var $HOME
reset_home()
{
    export HOME=${env_home}
    echo "reset to original home: $HOME"
}

# reset compiling environment
gcov_support_clean()
{
    find ${work_dir} -name $INFO_FILE_PREFIX* | xargs rm -rf
    find ${work_dir} -name $HTML_FILE_PREFIX* | xargs rm -rf
    find ${work_dir} -name *.gcno | xargs rm -rf
    find ${work_dir} -name *.gcda | xargs rm -rf
    find ${work_dir} -name $TMP_GCDA_FILE_LIST | xargs rm -rf
    rm $INFO_ERR_LIST
    rm $GCDA_DIR_LIST
}

# verify whether the info file generated is valid
verify_info_file()
{
    local file=$1
    local path=$2
    local FILE_OK=`grep "FN:" ${file} | wc -l`
    if [ $FILE_OK -lt 1 ] ;then
        echo ${path}/${file} >> ${INFO_ERR_LIST}
        rm ${file}
    fi
}

# search and save the dir where the lcov should be implemented
list_lcov_path()
{
    local find_gcda_file
    local gcda_dir=$1

    TMP_FILE=${gcda_dir}/tmpgcdalist
    echo "Start searching .gcda files..."
    exec 4>$TMP_FILE
    find_gcda_file=`find ${gcda_dir} -name *.gcda`
    echo "${find_gcda_file}"
    RESULT=${find_gcda_file}
    echo "$RESULT" >&4
    exec 4>&-
    # save the dirnames where the .gcda files exist
    cat ${TMP_FILE} | xargs dirname | uniq > ${GCDA_DIR_LIST}
#    rm ${TMP_FILE}
}

# generate gcov base info and html report for specified range files
lcov_genhtml_report()
{
    local gcda_file_range=$1
    list_lcov_path ${gcda_file_range}

    while read line
    do
        local fullpath=$line
        local infoname=${INFO_FILE_PREFIX}${fullpath##*/}.info
        htmldirname=${HTML_FILE_PREFIX}${fullpath##*/}

        echo "###ENTERING ${fullpath}"
        cd ${fullpath}
        GCDA_COUNT=`find -name "*.gcda" | wc -l`
        echo "gcda count: $GCDA_COUNT"
        if [ $GCDA_COUNT -ge 1 ]; then
            echo "Executing lcov -c -d . -o ${infoname}"
            lcov -c -d . -o ${infoname} 2>/dev/null
            if [ "$?" != "0" ]; then
                echo "lcov fail!"
                rm ${infoname}
            fi
            #verify_info_file ${infoname} ${fullpath}
        fi

        # generate html report
        local SOURCE_CODE_COUNT=`find . -name "*\.[c|cpp]" | wc -l`
        if [ $SOURCE_CODE_COUNT -lt 1 ]; then
            genhtml -o ${htmldirname} -t ${fullpath##*/} --no-source *.info
        else
            echo "Executing genhtml..."
            genhtml -o ${htmldirname} -t ${fullpath##*/} *.info
        fi
    done < ${GCDA_DIR_LIST}

    cd ${work_dir}
}

# generate html reports for all eligible submodules
lcov_genhtml_all()
{
    echo " === Start generating all gcov reports === "
    lcov_genhtml_report ${work_dir}
}

lcov_merge_all()
{
    local project_c_source
    local all_info_files
    
    # check c/cpp source files
    project_c_source=`find -name "*\.[c|cpp]" 2>/dev/null | wc -l`
    
    pushd gcov_output/
    if [ ! -d ${ALLMERGE_DIR} ]; then
        mkdir -p ${ALLMERGE_DIR}
    fi

    all_info_files=`find . -name *\.info`
    if [ ${project_c_source} -lt 1 ]; then
        echo "############# build reports without sources ###############"
        genhtml -o $ALLMERGE_DIR --no-source ${all_info_files}
    else
        echo "############# build reports with sources ##################"
        genhtml -o $ALLMERGE_DIR ${all_info_files}
    fi
    popd
}

get_info_file()
{
    echo "### Start collecting info files generated by lcov"
    find -name "${INFO_FILE_PREFIX}*" > ${INFO_FILE_LIST}

    while read line
    do
        local info_file=${line}
        local FromFullpath=${line%/*}
        local ToFullpath

        if [ ! -d ${GCOV_INFO_OUTPUT} ]; then
            mkdir -p ${GCOV_INFO_OUTPUT}
        fi
        pushd ${GCOV_INFO_OUTPUT}
        mkdir -p ${FromFullpath}
        popd
        ToFullpath=${GCOV_INFO_OUTPUT}/${FromFullpath#*/}
        cp ${info_file} ${ToFullpath}
    done < ${INFO_FILE_LIST}
}

get_html_file()
{
    echo "### Start collecting html files generated by genhtml"
    find -name "${HTML_FILE_PREFIX}*" > ${HTML_FILE_LIST}

    while read line
    do
        local html_report=${line}
        local FromFullpath=${line%/*}
        local ToFullpath

        if [ ! -d ${GCOV_HTML_OUTPUT} ]; then
            mkdir -p ${GCOV_HTML_OUTPUT}
        fi
        pushd ${GCOV_HTML_OUTPUT}
        mkdir -p ${FromFullpath}
        popd
        ToFullpath=${GCOV_HTML_OUTPUT}/${FromFullpath#*/}
        cp ${html_report} ${ToFullpath}
    done < ${HTML_FILE_LIST}
}

gcov_merge_info()
{
    local build_dir

    build_dir=$1

    docker kill --signal "TERM" $(docker ps -q -a)
    sleep 120
    docker start $(docker ps -q -a)

    mkdir -p ${build_dir}/gcov_tmp
    mkdir -p ${build_dir}/gcov_tmp/gcov_output
    mkdir -p ${build_dir}/gcov_tmp/gcov_output/info

    echo "### Start collecting info files from existed containers"
    docker ps -q > ${CONTAINER_LIST}

    while read line
    do
        local container_id=${line}
        script_count=`docker exec -i ${container_id} find / -name gcov_support.sh | wc -l`
        if [ ${script_count} -gt 0 ]; then
            docker exec -i ${container_id} /tmp/gcov/gcov_support.sh collect_gcda
            docker exec -i ${container_id} /tmp/gcov/gcov_support.sh generate
        fi
        info_count=`docker exec -i ${container_id} find / -name *.info | wc -l`
        if [ ${info_count} -gt 0 ]; then
            mkdir -p ${build_dir}/gcov_tmp/${container_id}
            pushd ${build_dir}/gcov_tmp/${container_id}
            docker cp ${container_id}:/tmp/gcov/gcov_output .
            cp gcov_output/* ../gcov_output/
            popd
        fi
    done < ${CONTAINER_LIST}
    rm ${CONTAINER_LIST}

    pushd ${build_dir}/gcov_tmp
    find -name *.info > ${ALL_INFO_FILES}
    while read line
    do
        local info_file_name=${line##*/}
        local info_repeat_times=`grep ${info_file_name} ${ALL_INFO_FILES} | wc -l`
        if [ ${info_repeat_times} -gt 1 ]; then
            echo ${info_file_name} >> ${REPE_INFO_LIST}
        fi
    done < ${ALL_INFO_FILES}

    echo ${REPE_INFO_LIST} | while read line
    do
        local info_name=${line%.*}
        find -name ${info_name} > ${SINGLE_INFO_LIST}
        while read line
        do
            if [ ! -f "total_${info_name}.info" ]; then
                lcov -o total_${info_name}.info -a ${line}
            else
                lcov -o total_${info_name}.info -a total_${info_name}.info -a ${line}
            fi
            cp total_${info_name}.info gcov_output/info/
        done < ${SINGLE_INFO_LIST}
    done < ${REPE_INFO_LIST}
    lcov_merge_all
    tar_gcov_output

    popd
}

tar_gcov_output()
{
    local time_stamp

    time_stamp=$(date "+%Y%m%d%H%M")
    tar -czvf ${time_stamp}_SONiC_gcov_report.tar.gz gcov_output
}

collect_merged_report()
{
    get_info_file
    get_html_file
    #lcov_merge_all
    mv $INFO_ERR_LIST $GCOV_OUTPUT
    mv $GCDA_DIR_LIST $GCOV_OUTPUT
    #tar_gcov_output
}

gcov_support_generate_html()
{
    local submodule_name
    local gcda_count

    gcov_support_clean

    add_new_home_for_sonic
    pushd /tmp/gcov
    gcno_count=`find -name gcno*.tar.gz 2>/dev/null | wc -l`
    if [ ${gcno_count} -lt 1 ]; then
        echo "### Fail! Cannot find any gcno files, please check."
        return -1
    fi

    gcda_count=`find -name gcda*.tar.gz 2>/dev/null | wc -l`
    if [ ${gcda_count} -lt 1 ]; then
        echo "### Cannot find any gcda files, please check."
        return 0
    fi

    # echo "### Extract .gcda and .gcno files..."
    # tar -zxvf $GCNO_ALL_TAR_GZ
    find -name gcda*.tar.gz > tmp_gcda.txt
    while read LINE ; do
        tar -zxvf ${LINE#*.}
    done < tmp_gcda.txt
    rm tmp_gcda.txt

    find -name gcno*.tar.gz > tmp_gcno.txt
    while read LINE ; do
        submodule_name=`echo ${LINE%%.*} | awk -F _ '{print $2}' | awk -F . '{print $1}'`
        cp ${LINE#*/} /tmp/gcov/src/sonic-${submodule_name}
        pushd /tmp/gcov/src/sonic-${submodule_name}/
        tar -zxvf ${LINE#*.}
        popd
    done < tmp_gcno.txt
    rm tmp_gcno.txt

    popd

    # remove old output dir
    rm -rf ${work_dir}/gcov_output
    mkdir -p $GCOV_OUTPUT

    lcov_genhtml_all
    if [ "$?" != "0" ]; then
        echo "###lcov operation fail.."
        return -1
    fi

    # collect gcov output
    collect_merged_report
    reset_home
    echo "### Make gcovhtml completed !!"
}

# list and save the generated .gcda files
gcov_support_collect_gcda()
{
    local gcda_files_count

    pushd /
    # check whether .gcda files exist
    gcda_files_count=`find \. -name "*\.gcda" 2>/dev/null | wc -l`
    if [ ${gcda_files_count} -lt 1 ]; then
        echo "### no gcda files found!"
        return 0
    fi

    pushd /sonic
    tar -zcvf /tmp/gcov/gcda.tar.gz *
    popd

    popd

}

# list and save the generated .gcno files
gcov_support_collect_gcno()
{
    local find_command
    local tar_command
    local submodule_name

    find gcno*.tar.gz > tmp_gcno.txt
    while read LINE ; do
        rm -f ${LINE}
    done < tmp_gcno.txt
    rm tmp_gcno.txt

    # rename .tmp*_gcno files generated
    for tmp_gcno in `find -name .tmp_*.gcno`
    do
        new_gcno=`echo ${tmp_gcno} | sed 's/.tmp_//g'`
        echo ${new_gcno}
        mv ${tmp_gcno} ${new_gcno}
    done

    echo " === Start collecting .gcno files... === "
    submodule_name=$1
    exec 3>$GCNO_LIST_FILE
    find_command=`find -name *.gcno`
    echo "${find_command}"
    if [ -z "${find_command}" ]; then
        echo "### Error! no gcno files found!"
        return -1
    fi
    RESULT=${find_command}
    echo "$RESULT" >&3
    exec 3>&-
    
    local filesize=`ls -l $GCNO_LIST_FILE | awk '{print $5}'`
    # Empty gcno_file_list indicates the non-gcov compling mode
    if [ ${filesize} -le 1 ]; then
        echo "empty gcno_file_list.txt"
        rm $GCNO_LIST_FILE
    else
        echo " === Output archive file... === "
        tar_command="tar -T $GCNO_LIST_FILE -zcvf gcno_$submodule_name.tar.gz"
        echo "${tar_command}"
        ${tar_command}
        # temporarily using fixed dir
        cp gcno_$submodule_name.tar.gz ${work_dir}/debian/$submodule_name/tmp/gcov
        cp gcov_support.sh ${work_dir}/debian/$submodule_name/tmp/gcov
        rm $GCNO_LIST_FILE
        echo " === Collect finished... === "
    fi
}

main()
{
    case $1 in
        collect)
            gcov_support_collect_gcno $2
            ;;
        collect_gcda)
            gcov_support_collect_gcda
            ;;
        generate)
            gcov_support_generate_html
            ;;
        clean)
            gcov_support_clean
            ;;
        tar_output)
            tar_gcov_output
            ;;
        merge_container_info)
            gcov_merge_info $2
            ;;
        *)
            echo "Usage:"
            echo " collect               collect .gcno files based on module"
            echo " collect_gcda          collect .gcda files"
            echo " collect_gcda_files    collect .gcda files in a docker"
            echo " generate              generate gcov report in html form (all or submodule_name)"
            echo " clean                 reset environment"
            echo " tar_output            tar gcov_output forder"
            echo " merge_container_info  merge homonymic info files from different container"
    esac
}

main $1 $2
exit

