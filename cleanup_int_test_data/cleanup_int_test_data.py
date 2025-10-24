import csv
import json
import psycopg2

int_db_host = "billing-writer.us-east-1.rds.aws.hcp.to"
int_db_name = "hcp_billing_int"

# Used to test the script against PRDE first
prde_db_host = "localhost"
prde_db_name = "hcp_billing_dev"


def main():

  # read in database credentials from JSON file created by output of vault read command
  # VAULT_ADDR="https://vault.service.consul:8200" VAULT_FORMAT=json vault read billing/database/postgres/creds/rw_role | tee ./billing.rw.json
  with open("./billing.rw.json", 'r') as db_creds_file:
    db_creds_json = json.load(db_creds_file)
    db_user = db_creds_json["data"]["username"]
    db_pass = db_creds_json["data"]["password"]

  # connect to database
  conn = None
  try:
    db_conn_string = f"dbname={int_db_name} user='{db_user}' host='{int_db_host}' password='{db_pass}'"
    print(f"Database connection string: {db_conn_string}")

    conn = psycopg2.connect(db_conn_string)
    print(conn.get_dsn_parameters())
    print("Succesfully connected to database\n")

     # read in CSV file
    print("Reading in billing account IDs from CSV...")
    with open('billing_accounts_to_cleanup.csv', 'r', newline='') as csvfile:
      dict_reader = csv.DictReader(csvfile)

      # internal_id,id,organization_id,created_at,name
      for row in dict_reader:
        print("Cleaning up data for billing account ID:", row["internal_id"])

        cur = conn.cursor()

        # clean up fcp_running_transactions
        try:
          print("Deleting running transactions...")
          cur.execute(f"delete from fcp_running_transactions where billing_account_internal_id='{row["internal_id"]}'")
        except (Exception, psycopg2.DatabaseError) as error:
          print(f"Error while deleting running transctions: {error}")

        # statement_charged_usages
        try:
          print("Deleting charged usages...")
          cur.execute(f"delete from statement_charged_usages scu using statements s where scu.account_id = '{row["internal_id"]}' and scu.statement_id = s.internal_id and s.finalized is false")
        except (Exception, psycopg2.DatabaseError) as error:
          print(f"Error while deleting charged usages: {error}")

        # statement_rated_usages
        try:
          print("Deleting rated usages...")
          cur.execute(f"delete from statement_rated_usages sru where sru.account_id = '{row["internal_id"]}' and sru.id not in(select scu.rated_usage_id from statement_charged_usages scu inner join statements s on scu.statement_id = s.internal_id where scu.account_id='{row["internal_id"]}')")
        except (Exception, psycopg2.DatabaseError) as error:
          print(f"Error while deleting rated usages: {error}")

        # statement_aggregated_usages
        try:
          print("Deleting statement aggregated usages...")
          cur.execute(f"delete from statement_aggregated_usages sau using statements s where sau.statement_id = s.internal_id and finalized is false and account_id='{row["internal_id"]}'")
        except (Exception, psycopg2.DatabaseError) as error:
          print(f"Error while deleting statement aggregated usages: {error}")

        # statements
        try:
          print("Deleting unfinalized statements...")
          cur.execute(f"delete from statements where finalized is false and account_id='{row["internal_id"]}'")
        except (Exception, psycopg2.DatabaseError) as error:
          print(f"Error while unfinalized statements: {error}")

        conn.commit()
  except psycopg2.Error as e:
    print(f"Connecting to database failed: {e}")


main()