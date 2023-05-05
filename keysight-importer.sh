#!/bin/bash


API_KEY="API_KEY"
XRAY_API_KEY="XRAY_API_KEY"
QUERY='{"query":"{ getTestExecutions(jql: \"project=JTP\", limit: 50) { total results { jira(fields: [\"key\"]) tests(limit: 100) { total results { jira(fields: [\"key\"]) } } } } }","variables":null}'
JQL_TEMPLATE='summary~"%s"'


loop_parameters=$(awk -F',' '$3 ~ /^Pass$|^Error$/ && $2 ~ /B[0-9]{1,2}\+B[0-9]{1,2}\+B[0-9]{1,2}\+N[0-9]{1,2}/ {print $0}' data.csv)

function get_issue_id() {
  local jql="$1"
  curl -s -X GET "https://xsquareiot.atlassian.net/rest/api/2/search?jql=$jql" -H "Authorization: Basic $API_KEY" -H "Content-Type: application/json" | jq -r '.issues[0].key'
}

function get_execution_ids() {
  local issue_id="$1"
  curl -s -H "Authorization: Bearer ${XRAY_API_KEY}" \
     -H 'Content-Type: application/json' \
     --data-raw "$QUERY" \
     https://xray.cloud.getxray.app/api/v2/graphql \
     | jq --arg issue_id "$issue_id" '.data.getTestExecutions.results[] | select(.tests.results[].jira.key | contains($issue_id)) | .jira.key'
}

IFS=$'\n' read -d '' -r -a loop_parameters_array <<<"$loop_parameters"
for parameter in "${loop_parameters_array[@]}"; do
  loop_parameter_information=$(echo "$parameter" | awk -F',' '{print $2}')
  verdict=$(echo "$parameter" | awk -F',' '{print $3}')

  jql=$(printf "$JQL_TEMPLATE" "$loop_parameter_information")
  issue_id=$(get_issue_id "$jql")

  execution_ids=$(get_execution_ids "$issue_id")

  echo "$issue_id 有 $(echo "$execution_ids" | wc -l) 個 TestExecution: $(echo "$execution_ids" | tr '\n' ' ')"
  

  if [[ ! -z $issue_id ]]; then
    status=""

    if [[ $verdict == "Pass" ]]; then
        status="PASSED"
    elif [[ $verdict == "Error" ]]; then
        status="FAILED"
    fi

    IFS=$'\n' read -d '' -r -a execution_id_array <<<"$execution_ids"
    for execution_id in "${execution_id_array[@]}"; do
    execution_id=$(echo "$execution_id" | sed 's/"//g')  
     
      
      curl --location --request POST "https://xray.cloud.getxray.app/api/v2/import/execution" \
       --header "Authorization: Bearer $XRAY_API_KEY" \
       --header "Content-Type: application/json" \
       --data-raw "{
        \"testExecutionKey\": \"$execution_id\",  
        \"tests\" : [
         {
           \"testKey\" : \"$issue_id\",
           \"status\" : \"$status\"
         }
        ]
      }"
      sleep 2
      echo "$issue_id 狀態為:$status | TestExecution:$execution_id 更新完成"
    done
  fi
done
