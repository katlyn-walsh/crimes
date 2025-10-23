#!/opt/homebrew/bin/bash
# Note: If you don't use /opt/homebrew/bin/bash, it will use the default version of bash installed on the Mac, which is old.

# Input CSV file
CSV_FILE="billed_resources_to_be_stopped.csv"

# This must be run after tunnel has been opened and make dev/grpc-gui is run. Use the port that command uses to display the UI.
GRPC_GUI_PORT="50011"

# Create an array to keep track of any resources we couldn't stop. This will get written to a CSV.
declare -ag UNRESOLVED_RESOURCES
UNRESOLVED_RESOURCES+=("billing_resource_id,organization_id,reason")

echo "Reading in data from $CSV_FILE..."
while IFS=',' read -r TYPE UUID ORGANIZATION_ID PROJECT_ID PROVIDER REGION ID INTERNAL_ID; do
  CURRENT_TIME="$(date -u +'%Y-%m-%dT%H:%M:%S')Z"
  # call stop billing endpoint
  echo "Stopping resource ID: $UUID, type: $TYPE, organization ID: $ORGANIZATION_ID"
  response=$(curl -s "http://127.0.0.1:$GRPC_GUI_PORT/invoke/hashicorp.cloud.internal.billing.ResourceService.StopBillingForResource" \
    -H 'Accept: */*' \
    -H 'Accept-Language: en-US,en;q=0.9' \
    -H 'Connection: keep-alive' \
    -H 'Content-Type: application/json' \
    -b '_grpcui_csrf_token=TH1dknu-pgv-TlmWTf13HTRSvjJj7zjvurV_o7G4mQc' \
    -H "Origin: http://127.0.0.1:$GRPC_GUI_PORT" \
    -H "Referer: http://127.0.0.1:$GRPC_GUI_PORT/" \
    -H 'Sec-Fetch-Dest: empty' \
    -H 'Sec-Fetch-Mode: cors' \
    -H 'Sec-Fetch-Site: same-origin' \
    -H 'x-grpcui-csrf-token: TH1dknu-pgv-TlmWTf13HTRSvjJj7zjvurV_o7G4mQc' \
    --data-raw "{\"metadata\":[],\"data\":[{\"resource\":{\"type\":\"$TYPE\",\"uuid\":\"$UUID\",\"location\":{\"organization_id\":\"$ORGANIZATION_ID\",\"project_id\":\"$PROJECT_ID\",\"region\":{\"provider\":\"$PROVIDER\",\"region\":\"$REGION\"}},\"id\":\"$ID\",\"internalId\":\"$INTERNAL_ID\"},\"timestamp\":\"$CURRENT_TIME\"}]}")

  error=$(echo $response | jq '.error')
  if [[ "$error" != "null" ]]; then
    error_msg=$(echo $response | jq '.error.message')

    echo "Error stopping resource ID $UUID: $error_msg"
    UNRESOLVED_RESOURCES+=("$UUID,$error_msg")
  else
    echo "Resource successfully stopped: $UUID"
  fi
done < <(sed 1d $CSV_FILE)

# Write unsuccessful resolutions to a file.
dt=$(date '+%m-%d_%H:%M:%S');
unresolved_file="unresolved_accounts_$dt.csv"
for ((i = 0; i < ${#UNRESOLVED_RESOURCES[@]}; i++))
do
  printf "%s\n" "${UNRESOLVED_RESOURCES[@]}" > "$unresolved_file"
done