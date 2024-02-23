#!/bin/bash

ids=$(cat ./out.txt)

count=1

for id in $ids
do
    echo $id $count
    query1="DELETE FROM statement_aggregated_usages
        WHERE statement_id  in (
        SELECT internal_id FROM statements 
        WHERE account_id = '$id'
        and lower(period) >= '2023-06-15T00:00:00.000Z');"

    sleep 1

    PGPASSWORD=password psql -U username -h billing-writer.us-east-1.rds.aws.hashicorp.cloud -d hcp_billing_prod -c "$query1"

    query2="DELETE FROM statement_charged_usages 
        WHERE statement_id in (
        SELECT internal_id FROM statements 
        WHERE account_id = '$id'
        and lower(period) >= '2023-06-15T00:00:00.000Z');"

    PGPASSWORD=password psql -U username -h billing-writer.us-east-1.rds.aws.hashicorp.cloud -d hcp_billing_prod -c "$query2"

    sleep 1

    query3="DELETE FROM statements
        WHERE account_id = '$id'
        and lower(period) >= '2023-06-15T00:00:00.000Z'
        AND "state" = 'running';"

    PGPASSWORD=password psql -U username -h billing-writer.us-east-1.rds.aws.hashicorp.cloud -d hcp_billing_prod -c "$query3"

    sleep 1

count=$((count+1))
done