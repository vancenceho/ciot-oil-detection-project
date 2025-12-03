"""
Database setup and schema initialization
Run this before starting the main application
"""
import os
import sys
import time
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
import boto3
import json

# Database connection parameters
RDS_HOST = os.getenv("RDS_HOST")
RDS_PORT = int(os.getenv("RDS_PORT", "5432"))
RDS_DB = os.getenv("RDS_DB_NAME")
RDS_USER = os.getenv("RDS_USER")
RDS_PASSWORD = os.getenv("RDS_PASSWORD")
RDS_SECRET_ARN = os.getenv("RDS_SECRET_ARN")  # For ECS deployment

AWS_REGION = os.getenv("AWS_REGION", "ap-southeast-1")


def get_db_credentials():
    """Get database credentials from environment or Secrets Manager"""
    if RDS_SECRET_ARN:
        # In ECS: fetch from Secrets Manager
        secrets_client = boto3.client("secretsmanager", region_name=AWS_REGION)
        secret_value = secrets_client.get_secret_value(SecretId=RDS_SECRET_ARN)
        credentials = json.loads(secret_value["SecretString"])
        return credentials["username"], credentials["password"]
    else:
        # Local development: use environment variables
        return RDS_USER, RDS_PASSWORD


def get_db_conn(dbname=None):
    """Create database connection"""
    username, password = get_db_credentials()
    
    return psycopg2.connect(
        host=RDS_HOST,
        port=RDS_PORT,
        dbname=dbname or RDS_DB,
        user=username,
        password=password,
    )


def wait_for_db(max_retries=30, retry_interval=2):
    """Wait for database to be ready"""
    print(f"Waiting for database at {RDS_HOST}:{RDS_PORT}...")
    
    for attempt in range(max_retries):
        try:
            conn = get_db_conn()
            conn.close()
            print("✓ Database is ready!")
            return True
        except psycopg2.OperationalError as e:
            if attempt < max_retries - 1:
                print(f"  Attempt {attempt + 1}/{max_retries}: Database not ready, retrying in {retry_interval}s...")
                time.sleep(retry_interval)
            else:
                print(f"✗ Failed to connect to database after {max_retries} attempts")
                print(f"  Error: {e}")
                return False
    
    return False


def create_schema():
    """Create database tables and schema"""
    print("Creating database schema...")
    
    conn = get_db_conn()
    cur = conn.cursor()
    
    try:
        # ------------------------------------------------------------------
        # buoy_readings table (aligned with Glue setup script)
        # ------------------------------------------------------------------
        # Drop existing table if schema changed
        cur.execute("DROP TABLE IF EXISTS buoy_readings CASCADE;")
        print("Dropped existing 'buoy_readings' table (if any) to update schema")

        cur.execute("""
            CREATE TABLE IF NOT EXISTS buoy_readings (
                id SERIAL PRIMARY KEY,
                buoy_id VARCHAR(50) NOT NULL,
                longitude DECIMAL(10, 6) NOT NULL,
                latitude DECIMAL(10, 6) NOT NULL,
                sensor_data DECIMAL(10, 4) NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        print("Table 'buoy_readings' created with updated schema")

        # Optional: indexes for faster queries
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_buoy_readings_buoy_id
            ON buoy_readings(buoy_id)
        """)
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_buoy_readings_created_at
            ON buoy_readings(created_at DESC)
        """)
        
        # Create readings table for raw sensor data
        cur.execute("""
            CREATE TABLE IF NOT EXISTS readings (
                id SERIAL PRIMARY KEY,
                buoy_id VARCHAR(100),
                timestamp TIMESTAMPTZ NOT NULL,
                latitude DECIMAL(10, 8),
                longitude DECIMAL(11, 8),
                oil_detected BOOLEAN,
                sensor_data JSONB,
                raw_payload JSONB,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )
        """)
        
        # Create index on timestamp for faster queries
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_readings_timestamp 
            ON readings(timestamp DESC)
        """)
        
        # Create index on buoy_id for filtering
        cur.execute("""
            CREATE INDEX IF NOT EXISTS idx_readings_buoy_id 
            ON readings(buoy_id)
        """)
        
        # Create processed_files table to track which S3 files have been processed
        cur.execute("""
            CREATE TABLE IF NOT EXISTS processed_files (
                id SERIAL PRIMARY KEY,
                s3_key VARCHAR(500) UNIQUE NOT NULL,
                processed_at TIMESTAMPTZ DEFAULT NOW(),
                records_inserted INTEGER DEFAULT 0
            )
        """)
        
        conn.commit()
        print("✓ Schema created successfully!")
        
    except Exception as e:
        conn.rollback()
        print(f"✗ Error creating schema: {e}")
        raise
    finally:
        cur.close()
        conn.close()


def verify_schema():
    """Verify that required tables exist"""
    print("Verifying database schema...")
    
    conn = get_db_conn()
    cur = conn.cursor()
    
    try:
        cur.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
            AND table_name IN ('readings', 'processed_files', 'buoy_readings')
        """)
        
        tables = [row[0] for row in cur.fetchall()]
        
        required = {'readings', 'processed_files', 'buoy_readings'}
        if required.issubset(set(tables)):
            print("✓ Schema verification passed!")
            return True
        else:
            print(f"✗ Schema verification failed. Found tables: {tables}")
            return False
            
    except Exception as e:
        print(f"✗ Error verifying schema: {e}")
        return False
    finally:
        cur.close()
        conn.close()


def main():
    """Main setup function"""
    print("=" * 50)
    print("Database Setup and Schema Initialization")
    print("=" * 50)
    
    # Wait for database to be ready
    if not wait_for_db():
        print("✗ Database setup failed: Could not connect to database")
        sys.exit(1)
    
    # Create schema
    try:
        create_schema()
    except Exception as e:
        print(f"✗ Database setup failed: {e}")
        sys.exit(1)
    
    # Verify schema
    if not verify_schema():
        print("✗ Database setup failed: Schema verification failed")
        sys.exit(1)
    
    print("=" * 50)
    print("✓ Database setup completed successfully!")
    print("=" * 50)


if __name__ == "__main__":
    main()