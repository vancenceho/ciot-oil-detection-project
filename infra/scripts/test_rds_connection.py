import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.dynamicframe import DynamicFrame
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import SparkSession

# Initialize Glue context
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'CONNECTION_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Get the connection name from job arguments
connection_name = args.get('CONNECTION_NAME', 'ciot-rds-connection-dev')

print(f"Testing connection to: {connection_name}")

try:
    print("=" * 80)
    print("Testing Glue connection to RDS...")
    print("=" * 80)
    print(f"Connection name: {connection_name}")
    
    # Use Glue's native connection support - this handles drivers automatically
    # The connection is already specified in the job's connections list
    # We just need to use it with the right format
    
    # Use Glue connection directly - it handles the driver automatically
    # Read from information_schema.tables (always exists in PostgreSQL)
    print("\nAttempting to read from information_schema.tables...")
    print("(This table always exists, even in empty databases)")
    
    # Use the connection name directly - Glue will handle the driver
    df = glueContext.create_dynamic_frame.from_options(
        connection_type="jdbc",
        connection_options={
            "connectionName": connection_name,
            "dbtable": "information_schema.tables"
        }
    )
    
    # Convert to DataFrame and get a sample
    spark_df = df.toDF()
    
    # Just try to get the schema and count - this proves the connection works
    print("✓ Successfully connected! Getting table information...")
    schema = spark_df.schema
    print(f"Schema fields: {len(schema.fields)}")
    
    # Try to get a small sample (limit to avoid processing all system tables)
    sample = spark_df.limit(5)
    count = sample.count()
    
    print("=" * 80)
    print("✓ SUCCESS: Glue can connect to RDS!")
    print("=" * 80)
    print(f"Retrieved {count} sample records from information_schema.tables")
    print("\nThe connection is working. Glue can successfully:")
    print("  1. Use the Glue connection")
    print("  2. Connect to RDS using JDBC")
    print("  3. Read data from the database")
    print("=" * 80)
    
    job.commit()
    print("\nJob completed successfully! Glue can connect to RDS.")
    
except Exception as e:
    print(f"\n{'=' * 80}")
    print(f"ERROR: Failed to connect to RDS")
    print(f"{'=' * 80}")
    print(f"Error message: {str(e)}")
    print(f"Error type: {type(e).__name__}")
    import traceback
    print("\nFull traceback:")
    traceback.print_exc()
    raise

