#!/opt/homebrew/bin/bash
# Note: If you don't use /opt/homebrew/bin/bash, it will use the default version of bash installed on the Mac, which is old.

# Input CSV file
CSV_FILE="remaining_customers_missing_invoices.csv"
#CSV_FILE="dev_test_missing_invoice.csv"

# Stripe secret key
STRIPE_SECRET_KEY=""

# This must be run after tunnel has been opened and make dev/grpc-gui is run. Use the port that command uses to display the UI.
GRPC_GUI_PORT="60837"

# Create an array to keep track of any accounts we couldn't resolve. This will get written to a CSV.
declare -ag UNRESOLVED_ACCOUNTS
UNRESOLVED_ACCOUNTS+=("billing_account_internal_id,stripe_customer_id,statement_internal_id,reason")

# Create an array to track accounts we were able to successfully create a matching payment row for. This will be written to a CSV.
declare -ag RESOLVED_ACCOUNTS
RESOLVED_ACCOUNTS+=("billing_account_internal_id,stripe_customer_id,statement_internal_id,stripe_invoice_id,payment_payg_payments_id")

echo "Reading in data from $CSV_FILE..."
while IFS=',' read -r BILLING_ACCOUNT_INTERNAL_ID ORGANIZATION_ID STRIPE_CUSTOMER_ID STATEMENT_INTERNAL_ID BILLING_PERIOD_START BILLING_PERIOD_END; do
  echo "Creating invoice for organization ID: $ORGANIZATION_ID, internal billing account ID: $BILLING_ACCOUNT_INTERNAL_ID, Stripe customer ID: $STRIPE_CUSTOMER_ID, statement internal id: $STATEMENT_INTERNAL_ID, billing period start: $BILLING_PERIOD_START, billing period end: $BILLING_PERIOD_END"

  # Craft idempotency key.
  # CAUTION: This will only work for 24 hours! Stripe will not prevent retries with the same idempotency key after that.
  IDEMPOTENCY_KEY="invoice/${STATEMENT_INTERNAL_ID}/create"

  # Create an invoice using Stripe API
  response=$(curl -s -X POST https://api.stripe.com/v1/invoices \
    -u $STRIPE_SECRET_KEY: \
    -d "auto_advance=true" \
    -d "customer=$STRIPE_CUSTOMER_ID" \
    -d "collection_method"="charge_automatically" \
    -d "metadata[hcp_invoice_id]"="$STATEMENT_INTERNAL_ID" \
    -d "metadata[hcp_statement_id]"="$STATEMENT_INTERNAL_ID" \
    -d "metadata[hcp_source_system]"="sbe"\
    -d "custom_fields[0][name]"="Period Start (UTC)" \
    -d "custom_fields[0][value]"="$BILLING_PERIOD_START" \
    -d "custom_fields[1][name]"="Period End" \
    -d "custom_fields[1][value]"="$BILLING_PERIOD_END" \
    -d "pending_invoice_items_behavior"="include" \
    -H "Idempotency-Key: $IDEMPOTENCY_KEY")

  # Check if the request was successful
  has_error=$(echo $response | jq 'has("error")')
  if [[ "$has_error" = "true" ]]; then
    error=$(echo $response | jq '.error')
    echo "Error creating invoice for customer $STRIPE_CUSTOMER_ID: $error"
    UNRESOLVED_ACCOUNTS+=("$BILLING_ACCOUNT_INTERNAL_ID,$STRIPE_CUSTOMER_ID,$STATEMENT_INTERNAL_ID,\"$error\"")
  else
    echo "Invoice created successfully for customer $STRIPE_CUSTOMER_ID"
    invoice_id=$(echo $response | jq -r '.id')

    # Create a corresponding row in payments table
    echo "Creating payment for invoice $invoice_id..."
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
  fi
done < <(sed 1d $CSV_FILE)

# Write unsuccessful resolutions to a file.
dt=$(date '+%m-%d_%H:%M:%S');
unresolved_file="unresolved_accounts_$dt.csv"
for ((i = 0; i < ${#UNRESOLVED_ACCOUNTS[@]}; i++))
do
  printf "%s\n" "${UNRESOLVED_ACCOUNTS[@]}" > "$unresolved_file"
done

# Write successful resolutions to a file.
resolved_file="resolved_accounts_$dt.csv"
for ((i = 0; i < ${#RESOLVED_ACCOUNTS[@]}; i++))
do
  printf "%s\n" "${RESOLVED_ACCOUNTS[@]}" > "$resolved_file"
done