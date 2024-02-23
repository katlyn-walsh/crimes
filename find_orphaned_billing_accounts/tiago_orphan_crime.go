package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"time"

	rmpb "github.com/hashicorp/cloud-resource-manager/proto-public/20191210/go"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
)

const sleepInterval = 500 * time.Microsecond

type row struct {
	InternalID     string `json:"internal_id,omitempty"`
	OrganizationID string `json:"organization_id,omitempty"`
}

func main() {
	if len(os.Args) != 4 {
		fmt.Println("usage: verify <resource manager address> <path to accounts json> <path to orphaned files>")
		os.Exit(1)
	}

	input, err := os.Open(os.Args[2])
	if err != nil {
		fmt.Printf("failed to open input file: %v\n", err)
		os.Exit(1)
	}

	defer input.Close()

	output, err := os.Create(os.Args[3])
	if err != nil {
		fmt.Printf("failed to open output file: %v\n", err)
		os.Exit(1)
	}

	defer output.Close()

	failures, err := os.Create("./failures.json")
	if err != nil {
		fmt.Printf("failed to open failures file: %v\n", err)
		os.Exit(1)
	}

	conn, err := grpc.Dial(os.Args[1], grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		fmt.Printf("failed to create connection to resource manager: %v\n", err)
	}

	client := rmpb.NewOrganizationServiceClient(conn)
	ctx := context.Background()

	var accounts []row
	err = json.NewDecoder(input).Decode(&accounts)
	if err != nil {
		fmt.Printf("failed parse input file: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("verifying %d accounts\n", len(accounts))

	var orphanedAccounts []row
	var failedAccounts []row

	for idx, account := range accounts {

		fmt.Printf("validatin [%06d / %d accounts] (orphans: %d / failures: %d) \r \a", idx, len(accounts), len(orphanedAccounts), len(failedAccounts))

		_, err := client.Get(ctx, &rmpb.OrganizationGetRequest{Id: account.OrganizationID})
		if status.Code(err) == codes.NotFound {
			fmt.Printf("\norphaned account found %q (org %q)\n", account.InternalID, account.OrganizationID)
			orphanedAccounts = append(orphanedAccounts, account)
		} else if err != nil {
			failedAccounts = append(failedAccounts, account)
		}

		time.Sleep(sleepInterval)
	}

	fmt.Println("")
	fmt.Println("----------------")
	fmt.Println("Finished running")

	if len(orphanedAccounts) != 0 {
		fmt.Printf("found %d orphaned accounts\n", len(orphanedAccounts))

		err = json.NewEncoder(output).Encode(orphanedAccounts)
		if err != nil {
			fmt.Printf("failed to write to output file: %v\n", err)
			os.Exit(1)
		}
	}

	if len(failedAccounts) != 0 {
		fmt.Printf("%d accounts failed to verify, saving at ./failures.json for retry\n", len(orphanedAccounts))

		err = json.NewEncoder(failures).Encode(failedAccounts)
		if err != nil {
			fmt.Printf("failed to write to failures file: %v\n", err)
			os.Exit(1)
		}
	}
}
