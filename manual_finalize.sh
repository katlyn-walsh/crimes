#!/bin/bash

accounts=( 
"000-00000")

for account in "${accounts[@]}"
do
    echo "triggering finalize workflow for ${account}"

    requestBody="{\"account_id\": \"$account\", \"period_end\": \"2023-07-01T00:00:00Z\", \"dry_run\": false}"

    #echo grpcurl -protoset api.bin -plaintext -d "${requestBody}" 10.0.73.201:22725 hashicorp.cloud.internal.billing.statement.v1.StatementService/FinalizeStatement
    grpcurl -protoset api.bin -plaintext -d "${requestBody}" 10.0.65.142:31414 hashicorp.cloud.internal.billing.statement.v1.StatementService/FinalizeStatement

done
