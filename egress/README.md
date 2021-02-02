The CURL_TIMEOUT holds the most important information. 
Its output gives the namespace name, the pod name, the exit code of command and the text CURL_TIMEOUT. 
It shows that the curl command was tried on the pod of that project and it could not run for 20 seconds.
Refer to this line in the script:
```
${OC} -n ${NS} exec ${POD} -- /usr/bin/curl -s -k -m 20 https://whatismyip.com/ --noproxy whatismyip.com
```
Try to check in the logs at /backup/egress_logs the history for this project:
```
grep <project name> *
```
You might get smth like this:
```
egress_healthcheck.sh-202006181540.log:<project name> CORRECT_EGRESS_IP
egress_healthcheck.sh-202006181550.log:<project name> CORRECT_EGRESS_IP
egress_healthcheck.sh-202006181600.log:<project name> CORRECT_EGRESS_IP
```
When this happens it means that egress used to work and suddenly it stopped working and you have to reset the IP address on the netnamespace, that means to delete it and to reassign it again. 
