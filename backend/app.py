import os
import time
import boto3
import json
from datetime import datetime, timezone, timedelta
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from db_setup import get_db_conn

S3_BUCKET = os.getenv("S3_BUCKET")
AWS_REGION = os.getenv("AWS_REGION", "ap-southeast-1")

s3 = boto3.client("s3", region_name=AWS_REGION)

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://127.0.0.1:3000",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


def process_s3_objects():
    """Process S3 objects: read, transform, and insert into RDS"""
    if not S3_BUCKET:
        print("S3_BUCKET is not set, skipping S3 processing")
        return
    
    resp = s3.list_objects_v2(Bucket=S3_BUCKET, Prefix="raw/")
    if "Contents" not in resp:
        return

    conn = get_db_conn()
    cur = conn.cursor()
    
    try:
        # Check which files have already been processed
        cur.execute("SELECT s3_key FROM processed_files")
        processed_keys = {row[0] for row in cur.fetchall()}

        # Take only the 10 most recently modified objects
        latest_objects = sorted(
            resp["Contents"],
            key=lambda o: o.get("LastModified"),
            reverse=True,
        )[:10]

        for obj in latest_objects:
            key = obj["Key"]
            
            # Skip if already processed
            if key in processed_keys:
                continue
            
            if not key.endswith(".json"):
                continue
            
            # Read and parse JSON from S3
            body = s3.get_object(Bucket=S3_BUCKET, Key=key)["Body"].read()
            data = json.loads(body.decode("utf-8"))
            
            # Transform and insert into database
            raw_ts = data.get("timestamp") or time.time()
            # Assume incoming timestamp is UTC; store as UTC+8
            if isinstance(raw_ts, (int, float)):
                ts_utc8 = datetime.fromtimestamp(raw_ts, tz=timezone.utc) + timedelta(hours=8)
            else:
                # Expect ISO8601 string, e.g. "2025-12-02T12:00:00Z"
                value = str(raw_ts).replace("Z", "+00:00")
                try:
                    dt = datetime.fromisoformat(value)
                    if dt.tzinfo is None:
                        dt = dt.replace(tzinfo=timezone.utc)
                    ts_utc8 = dt + timedelta(hours=8)
                except Exception:
                    ts_utc8 = datetime.now(timezone.utc) + timedelta(hours=8)

            cur.execute("""
                INSERT INTO readings (
                    buoy_id, timestamp, latitude, longitude, 
                    oil_detected, sensor_data, raw_payload
                ) VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (
                data.get("buoy_id"),
                ts_utc8,
                data.get("coordinates", {}).get("lat"),
                data.get("coordinates", {}).get("lon"),
                data.get("sensor_data", {}).get("oil_detected"),
                json.dumps(data.get("sensor_data", {})),
                json.dumps(data)
            ))
            
            # Mark file as processed
            cur.execute("""
                INSERT INTO processed_files (s3_key, records_inserted)
                VALUES (%s, 1)
                ON CONFLICT (s3_key) DO NOTHING
            """, (key,))
        
        conn.commit()
        # Note: we only process a subset (latest_objects), not all listed objects
        print(f"Processed {len(latest_objects)} objects from S3 (out of {len(resp['Contents'])} listed)")
        
    except Exception as e:
        conn.rollback()
        print(f"Error processing S3 objects: {e}")
        raise
    finally:
        cur.close()
        conn.close()

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/db-health")
def db_health():
    """Simple DB connectivity check"""
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.fetchone()
        cur.close()
        conn.close()
        return {"status": "ok"}
    except Exception as e:
        # Surface the DB error so we can debug from curl/CloudWatch
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/readings-latest")
def readings_latest(limit: int = 10):
    try:
        conn = get_db_conn()
        cur = conn.cursor()
        cur.execute(
            """
            SELECT
                id,
                buoy_id,
                timestamp,
                latitude,
                longitude,
                oil_detected,
                sensor_data,
                raw_payload,
                created_at
            FROM readings
            ORDER BY created_at DESC
            LIMIT %s
        """,
            (limit,),
        )
        rows = cur.fetchall()
        cur.close()
        conn.close()
        return {
            "rows": [
                {
                    "id": r[0],
                    "buoy_id": r[1],
                    "timestamp": r[2],
                    "latitude": r[3],
                    "longitude": r[4],
                    "oil_detected": r[5],
                    "sensor_data": r[6],
                    "raw_payload": r[7],
                    "created_at": r[8],
                }
                for r in rows
            ]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    def loop():
        while True:
            process_s3_objects()
            time.sleep(60)

    import threading
    t = threading.Thread(target=loop, daemon=True)
    t.start()
    uvicorn.run(app, host="0.0.0.0", port=8080)