# Sums up the amount and quantity in the rated usage records returned by the ListRatedUsages endpoint in the statement service.
# Usage is python3 sumSBERatedUsage.py <json file containing response>
from decimal import *
import json
import sys

def main():
    fileName = sys.argv[1]

    print("reading in json file " + fileName)
    f = open(fileName)

    data = json.load(f)

    totalRecords = 0
    grossAmount = 0
    quantity = 0

    for ratedUsage in data["rated_usages"]:
        totalRecords = totalRecords + 1
        grossAmount = grossAmount + Decimal(ratedUsage["gross_amount"])
        quantity = quantity + Decimal(ratedUsage["quantity"])

    print("total number of records: " + str(totalRecords))
    print("total gross amount: " + str(grossAmount))
    print("total quantity: " + str(quantity))

main()