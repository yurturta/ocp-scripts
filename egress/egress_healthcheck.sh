#!/usr/bin/env bash
#--------------------------------------------------------
#
#
# by Elton Jani
#--- Tested on version OCP 3.11
#--------------------------------------------------------
#
#
#curl: -s silent, -k - dont check certs, --noproxy URL - dont use proxy for URL
#status.phase=="Running" does not capture CrashLoopBackOff state

LOGDIR="/backup/egress_logs"
LOG="${LOGDIR}/$(basename $0)-$(date +%Y%m%d%H%M).log"
TMPFILE="${LOGDIR}/$(basename $0)-$(date +%Y%m%d%H%M).csv"
EMAIL_RECIPIENT="yurturta@gmail.com"
EXCLUDED_NS="/usr/local/lib/egress_healthcheck_excluded_ns.txt"
EXCLUDED_STRINGS="/usr/local/lib/egress_healthcheck_excluded_strings.txt"
CONFIG="/usr/local/lib/egress-context-config"
SA_TOKEN="/usr/local/lib/sa_egress_token"

if [[ ! -f ${CONFIG} ]]; then
  echo "${CONFIG} does not exist"
  exit 1
fi

if [[ -f ${LOG} ]]; then
  echo "${LOG} already exists"
  exit 1
fi

if [[ -f ${TMPFILE} ]]; then
  echo "${TMPFILE} already exists"
  exit 1
fi

if [[ ! -f ${EXCLUDED_NS} ]]; then
  echo "${EXCLUDED_NS} does not exist"
  exit 1
fi

if [[ ! -f ${EXCLUDED_STRINGS} ]]; then
  echo "${EXCLUDED_NS} does not exist"
  exit 1
fi

if [[ ! -f ${SA_TOKEN} ]]; then
  echo "${SA_TOKEN} does not exist"
  exit 1
fi

exec &>> "${LOG}"

TMPCFG=$(mktemp -t tmp.egress.XXXXX)
cat ${CONFIG} > ${TMPCFG}

OC="oc --config=${TMPCFG} --token=$(cat ${SA_TOKEN})"

a="$(${OC} whoami 2>&1)"
if [[ $? -ne 0 ]]; then
  echo "E: You must be properly oc logged in to continue. ${a}"
  exit 1
else
  echo ${a}
  echo "$(${OC} whoami -c 2>&1)"
fi

${OC} get netnamespace --no-headers -o custom-columns=NS:.netname,NNS_IP:.egressIPs | while read NS NNS_IP; do
  if [[ "${NNS_IP}" != '<none>' ]]; then
    egressIP=$(echo ${NNS_IP}|sed 's/[][]//g')
    TRYPOD=$(${OC} get pod -n ${NS} --no-headers -o jsonpath='{range .items[?(@.status.phase=="Running")]}{.metadata.name}{"\n"}{end}' | tail -1)
    if [[ ! -z "${TRYPOD}" ]] && ! grep -q "${NS}" "${EXCLUDED_NS}"; then
      ${OC} get pod -n ${NS} --no-headers -o custom-columns=POD:.metadata.name,PHASE:.status.phase | while read POD PHASE; do
        if [[ ${PHASE} == 'Running' ]]; then
          WHATISIP=$(${OC} -n ${NS} exec ${POD} -- /usr/bin/curl -s -k -m 20 https://whatismyip.com/ --noproxy whatismyip.com)
          case $? in
            0)
              if ipcalc -cs ${WHATISIP}; then
                if [[ "${egressIP}" == "${WHATISIP}" ]]; then
                  echo "${NS} CORRECT_EGRESS_IP"
                  break
                else
                  echo "${NS} egressIP=${egressIP} whatisIP=${WHATISIP} WRONG_EGRESS_IP"
                fi
              fi
            ;;
            126|127)
              echo "${NS} ${POD} $? CURL_NOT_FOUND"
              #${OC} -n ${NS} exec ${POD} -- /usr/bin/curl -vvv -s -k -m 20 https://whatismyip.com/ --noproxy whatismyip.com
              ;;
            28)
              echo "${NS} ${POD} $? CURL_TIMEOUT"
              ${OC} -n ${NS} exec ${POD} -- /usr/bin/curl -vvv -s -k -m 20 https://whatismyip.com/ --noproxy whatismyip.com
              ;;
            6)
              echo "${NS} ${POD} $? Could not resolve host"
              ${OC} -n ${NS} exec ${POD} -- /usr/bin/curl -vvv -s -k -m 20 https://whatismyip.com/ --noproxy whatismyip.com
              ;;
            *)
              echo "${NS} ${POD} $? INVALID_IP"
              #${OC} -n ${NS} exec ${POD} -- /usr/bin/curl -vvv -s -k -m 20 https://whatismyip.com/ --noproxy whatismyip.com
            ;;
          esac
        fi
      done
    else
      echo "${NS} POD_WAS_NOT_FOUND"
    fi
  fi
done

NO_CURL="$(grep -i curl_not_found ${LOG} | wc -l)"
NO_POD="$(grep -i pod_was_not_found ${LOG} | wc -l)"
CORRECT_IP="$(grep -i correct_egress ${LOG} | wc -l)"
WRONG_IP="$(grep -i wrong_egress ${LOG} | wc -l)"
INVALID_IP="$(grep -i invalid_ip ${LOG} | wc -l)"
TOTAL_LINES="$(wc -l ${LOG} | cut -d' ' -f1)"
CURL_TIMEOUT="$(grep -i curl_timeout ${LOG} | wc -l)"
OTHER_LINES="$(grep -iv -f ${EXCLUDED_STRINGS} ${LOG} | wc -l)"

echo "CURL_NOT_FOUND, POD_NOT_FOUND, CORRECT_IP, WRONG_IP, INVALID_IP, CURL_TIMEOUT, OTHER_LINES, TOTAL_LINES" >> ${TMPFILE}
echo "${NO_CURL}, ${NO_POD}, ${CORRECT_IP}, ${WRONG_IP}, ${INVALID_IP}, ${CURL_TIMEOUT}, ${OTHER_LINES}, ${TOTAL_LINES}" >> ${TMPFILE}

echo "-----------------" >> ${TMPFILE}
echo "CURL COMMAND NOT FOUND" >> ${TMPFILE}
grep -i curl_not_found ${LOG} >> ${TMPFILE}
echo "-----------------" >>${TMPFILE}
echo "INVALID AND WRONG IP RESULTS" >> ${TMPFILE}
egrep -i 'invalid_ip|wrong' ${LOG} >> ${TMPFILE}
echo "-----------------" >> ${TMPFILE}
echo "OTHER LINES" >> ${TMPFILE}
grep -iv -f ${EXCLUDED_STRINGS} ${LOG} >> ${TMPFILE}
echo "-----------------" >> ${TMPFILE}
echo "CURL_TIMEOUT" >> ${TMPFILE}
grep -i curl_timeout ${LOG} >> ${TMPFILE}
echo "-----------------" >>${TMPFILE}

if [[ ! -f ${TMPFILE} ]]; then
  echo "${TMPFILE} does not exist"
  exit 1
else 
  if [[ ${WRONG_IP} -ne 0 || ${OTHER_LINES} -ne 0 ]]; then
    mailx -a ${TMPFILE} -s "Alert!! Egress Healthcheck as of $(date +%Y%m%d%H%M)" $EMAIL_RECIPIENT < ${TMPFILE}
  fi
  # if [[ ${CURL_TIMEOUT} -ne 0 ]]; then
    # mailx -a ${TMPFILE} -s "Alert!! Egress Healthcheck as of $(date +%Y%m%d%H%M)" $EMAIL_RECIPIENT2 < ${TMPFILE}
  # fi
  # rm -rf ${TMPFILE}
# fi

find /backup/egress_logs/ -mtime 4 -exec rm -rf {} \;

rm -f $TMPCFG

exit 0

