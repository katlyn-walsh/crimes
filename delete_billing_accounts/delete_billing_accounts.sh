#!/opt/homebrew/bin/bash
# Note: If you don't use /opt/homebrew/bin/bash, it will use the default version of bash installed on the Mac, which is old.

# Input CSV file
CSV_FILE="billing_accounts_to_delete.csv"

# This must be run after tunnel has been opened and make dev/grpc-gui is run. Use the port that command uses to display the UI.
GRPC_GUI_PORT="51107"

# Create an array to keep track of any accounts we couldn't resolve. This will get written to a CSV.
declare -ag UNRESOLVED_ACCOUNTS
UNRESOLVED_ACCOUNTS+=("billing_account_internal_id,reason")

# Create an array to track accounts we were able to successfully delete. This will be written to a CSV.
declare -ag RESOLVED_ACCOUNTS
RESOLVED_ACCOUNTS+=("billing_account_internal_id")

echo "Reading in data from $CSV_FILE..."
while IFS=',' read -r BILLING_ACCOUNT_INTERNAL_ID ID ORGANIZATION_ID CREATED_AT NAME; do
  # call delete billing account end point
  echo "Deleting billing account: $BILLING_ACCOUNT_INTERNAL_ID, Name: $NAME, under organization ID: $ORGANIZATION_ID"
  response=$(curl -s "http://127.0.0.1:$GRPC_GUI_PORT/invoke/hashicorp.cloud.internal.billing.BillingAccountService.Delete" \
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
    --data-raw "{\"metadata\":[],\"data\":[{\"organizationId\":\"$ORGANIZATION_ID\",\"id\":\"$ID\",\"overrideFlexCheck\":true}]}")

  error=$(echo $response | jq '.error')
  if [[ "$error" != "null" ]]; then
    error_msg=$(echo $response | jq '.error.message')

    echo "Error deleting account $BILLING_ACCOUNT_INTERNAL_ID: $error_msg"
    UNRESOLVED_ACCOUNTS+=("$BILLING_ACCOUNT_INTERNAL_ID,$error_msg")
  else
    echo "Account ID $BILLING_ACCOUNT_INTERNAL_ID successfully deleted"
  fi
done < <(sed 1d $CSV_FILE)

# Write unsuccessful resolutions to a file.
dt=$(date '+%m-%d_%H:%M:%S');
unresolved_file="unresolved_accounts_$dt.csv"
for ((i = 0; i < ${#UNRESOLVED_ACCOUNTS[@]}; i++))
do
  printf "%s\n" "${UNRESOLVED_ACCOUNTS[@]}" > "$unresolved_file"
done