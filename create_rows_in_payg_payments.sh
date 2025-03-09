#!/opt/homebrew/bin/bash
# Note: If you don't use /opt/homebrew/bin/bash, it will use the default version of bash installed on the Mac, which is older.

# Input CSV file
CSV_FILE="customers_missing_payg_payments.csv"

# Stripe secret key
STRIPE_SECRET_KEY=""

# This must be run after tunnel has been opened and make dev/grpc-gui is run. Use the port that command uses to display the UI.
GRPC_GUI_PORT="58531"

# Create an array to keep track of any accounts we couldn't resolve. This will get written to a CSV.
declare -ag UNRESOLVED_ACCOUNTS
UNRESOLVED_ACCOUNTS+=("billing_account_internal_id,stripe_customer_id,statement_internal_id,reason")

# Create an array to track accounts we were able to successfully create a matching payment row for. This will be written to a CSV.
declare -ag RESOLVED_ACCOUNTS
RESOLVED_ACCOUNTS+=("billing_account_internal_id,stripe_customer_id,statement_internal_id,stripe_invoice_id,payment_payg_payments_id")

echo "Reading in data from $CSV_FILE..."
while IFS=',' read -r BILLING_ACCOUNT_INTERNAL_ID STRIPE_CUSTOMER_ID STATEMENT_INTERNAL_ID; do
  echo "Fetching invoice for internal billing account ID: $BILLING_ACCOUNT_INTERNAL_ID, Stripe customer ID: $STRIPE_CUSTOMER_ID, statement internal id: $STATEMENT_INTERNAL_ID"

  # Call Stripe API to get invoice
  response=$(curl -s -G https://api.stripe.com/v1/invoices/search \
    -u $STRIPE_SECRET_KEY: \
    --data-urlencode query="metadata['hcp_statement_id']:'$STATEMENT_INTERNAL_ID' AND customer:'$STRIPE_CUSTOMER_ID'")

  # Check if the request was successful
  has_error=$(echo $response | jq 'has("error")')
  if [[ "$has_error" = "true" ]]; then
    echo "Error searching for invoice for customer $STRIPE_CUSTOMER_ID: $response"
    UNRESOLVED_ACCOUNTS+=("$BILLING_ACCOUNT_INTERNAL_ID,$STRIPE_CUSTOMER_ID,$STATEMENT_INTERNAL_ID,$response")
  else
    # Only one invoice with this ID should be returned.
    invoice_count=$(echo "$response" | jq '.data | length')

    if [[ "$invoice_count" -eq 1 ]]; then
      invoice_id=$(echo "$response" | jq -r '.data[0].id')
      echo "invoice $invoice_id found for customer $STRIPE_CUSTOMER_ID"

      # Call CreatePayment endpoint in PAYG PMI
      echo "creating payment for invoice $invoice_id..."
      response=$(curl -s "http://127.0.0.1:$GRPC_GUI_PORT/invoke/hashicorp.cloud.internal.billing.payment.payg.v1.PaymentPaygService.CreatePayment" \
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
        --data-raw "{\"metadata\":[],\"data\":[{\"accountInternalId\":\"$BILLING_ACCOUNT_INTERNAL_ID\",\"statementInternalId\":\"$STATEMENT_INTERNAL_ID\",\"stripeInvoiceId\":\"$invoice_id\"}]}")

      error=$(echo $response | jq '.error')
      if [[ "$error" != "null" ]]; then
        error_msg=$(echo $response | jq '.error.message')

        echo "Error creating payment for customer invoice $invoice_id: $error_msg"
        UNRESOLVED_ACCOUNTS+=("$BILLING_ACCOUNT_INTERNAL_ID,$STRIPE_CUSTOMER_ID,$STATEMENT_INTERNAL_ID,$error_msg")
      else
        echo "Payment row created successfully for invoice $invoice_id"

        # Get payment ID for posterity
        payment_id=$(echo $response | jq '.responses[0].message.payment.id')
        RESOLVED_ACCOUNTS+=("$BILLING_ACCOUNT_INTERNAL_ID,$STRIPE_CUSTOMER_ID,$STATEMENT_INTERNAL_ID,$invoice_id")
      fi
    else
      echo "Error: Expected 1 invoice, but found $invoice_count."
      UNRESOLVED_ACCOUNTS+=("$BILLING_ACCOUNT_INTERNAL_ID,$STRIPE_CUSTOMER_ID,$STATEMENT_INTERNAL_ID,found more than one Stripe invoice")
    fi
  fi
done < <(sed 1d $CSV_FILE)

# Write unsuccessful resolutions to a file.
dt=$(date '+%d-%m-%Y_%H:%M:%S');
unresolved_file="unresolved_accounts_$dt.csv"
for ((i = 0; i < ${#UNRESOLVED_ACCOUNTS[@]}; i++))
do
    echo "${UNRESOLVED_ACCOUNTS[$i]}" > "$unresolved_file"
done

# Write successful resolutions to a file.
resolved_file="resolved_accounts_$dt.csv"
for ((i = 0; i < ${#RESOLVED_ACCOUNTS[@]}; i++))
do
    echo "${RESOLVED_ACCOUNTS[$i]}" > "$resolved_file"
done
